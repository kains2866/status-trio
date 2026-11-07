import AudioToolbox
import CoreAudio
import Darwin
import Foundation

/// Injectable command boundary; tests exercise identity and routing without HAL writes.
struct AudioOutputCommandAccess: Sendable {
    let currentDeviceID: @MainActor @Sendable () -> AudioDeviceID?
    let uid: @MainActor @Sendable (AudioDeviceID) -> String?
    let level: @MainActor @Sendable (AudioDeviceID) -> AudioDeviceLevel
    let writeVolume: @MainActor @Sendable (AudioDeviceID, Float32) -> Bool
    let writeMute: @MainActor @Sendable (AudioDeviceID, Bool) -> Bool
}

@MainActor
final class CoreAudioOutputController: AudioOutputControlling {
    nonisolated private let systemObjectID = AudioObjectID(kAudioObjectSystemObject)

    private let commandAccess: AudioOutputCommandAccess?

    nonisolated init() { commandAccess = nil }

    init(commandAccess: AudioOutputCommandAccess) { self.commandAccess = commandAccess }

    // Read-only helpers use local storage and immutable device identifiers, so
    // the background snapshot reader never accesses command-side actor state.
    nonisolated func outputDevices() -> [AudioOutputDevice] {
        guard let deviceIDs = audioObjectIDs(
            objectID: systemObjectID,
            selector: kAudioHardwarePropertyDevices
        ) else {
            return []
        }

        let currentDeviceID = defaultOutputDeviceID()
        return deviceIDs
            .filter(isOutputDevice)
            .compactMap { deviceID -> AudioOutputDevice? in
                guard !isHidden(deviceID) else { return nil }

                return AudioOutputDevice(
                    id: deviceID,
                    name: deviceName(for: deviceID),
                    uid: deviceUID(for: deviceID),
                    isCurrent: deviceID == currentDeviceID,
                    transport: transport(for: deviceID),
                    dataSource: dataSource(for: deviceID),
                    iconURL: iconURL(for: deviceID),
                    modelUID: stringProperty(
                        for: deviceID,
                        selector: kAudioDevicePropertyModelUID
                    ),
                    level: level(for: deviceID)
                )
            }
            .sorted { lhs, rhs in
                if lhs.isCurrent != rhs.isCurrent {
                    return lhs.isCurrent
                }
                return (lhs.name ?? "").localizedStandardCompare(rhs.name ?? "") == .orderedAscending
            }
    }

    @discardableResult
    func setVolume(_ scalar: Double) -> Bool {
        guard let deviceID = defaultOutputDeviceID() else { return false }

        let volume = Float32(min(1, max(0, scalar)))
        var didSetVolume = setScalarProperty(
            volume,
            objectID: deviceID,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        )

        if !didSetVolume {
            for element in CoreAudioOutputChannelElements.channels(for: deviceID) {
                if setScalarProperty(
                    volume,
                    objectID: deviceID,
                    selector: kAudioDevicePropertyVolumeScalar,
                    scope: kAudioObjectPropertyScopeOutput,
                    element: element
                ) {
                    didSetVolume = true
                }
            }
        }

        guard didSetVolume else { return false }

        if isMuted(for: deviceID) {
            _ = setMuted(false, for: deviceID)
        }
        return true
    }

    /// Explicit-device writes never change the system route or implicitly unmute.
    @discardableResult
    func setVolume(_ scalar: Double, forDeviceID deviceID: AudioDeviceID, expectedUID: String?) -> Bool {
        guard scalar.isFinite, matchesIdentity(deviceID, expectedUID: expectedUID),
              commandLevel(for: deviceID).canAdjust else { return false }
        let value = Float32(min(1, max(0, scalar)))
        return commandAccess?.writeVolume(deviceID, value) ?? writeVolume(value, for: deviceID)
    }

    @discardableResult
    func toggleMute(forDeviceID deviceID: AudioDeviceID, expectedUID: String?) -> Bool {
        guard matchesIdentity(deviceID, expectedUID: expectedUID) else { return false }
        let snapshot = commandLevel(for: deviceID)
        guard snapshot.canMute, snapshot.muteState != .unknown else { return false }
        let muted = snapshot.muteState != .muted
        return commandAccess?.writeMute(deviceID, muted) ?? setMuted(muted, for: deviceID)
    }

    func isCurrentOutputDevice(_ deviceID: AudioDeviceID, expectedUID: String?) -> Bool {
        let currentID = commandAccess.map { $0.currentDeviceID() } ?? defaultOutputDeviceID()
        return currentID == deviceID && matchesIdentity(deviceID, expectedUID: expectedUID)
    }

    private func matchesIdentity(_ deviceID: AudioDeviceID, expectedUID: String?) -> Bool {
        guard deviceID != kAudioObjectUnknown, let expectedUID, !expectedUID.isEmpty,
              (commandAccess.map { $0.uid(deviceID) } ?? deviceUID(for: deviceID)) == expectedUID else { return false }
        return commandAccess != nil || hasOutputStreams(deviceID: deviceID)
    }

    private func commandLevel(for deviceID: AudioDeviceID) -> AudioDeviceLevel {
        commandAccess?.level(deviceID) ?? level(for: deviceID)
    }

    private func writeVolume(_ value: Float32, for deviceID: AudioDeviceID) -> Bool {
        if setScalarProperty(value, objectID: deviceID, selector: kAudioDevicePropertyVolumeScalar,
                             scope: kAudioObjectPropertyScopeOutput, element: kAudioObjectPropertyElementMain) {
            return true
        }
        var written = false
        for element in CoreAudioOutputChannelElements.channels(for: deviceID) {
            if setScalarProperty(value, objectID: deviceID, selector: kAudioDevicePropertyVolumeScalar,
                                 scope: kAudioObjectPropertyScopeOutput, element: element) { written = true }
        }
        return written
    }

    nonisolated func level(for deviceID: AudioDeviceID) -> AudioDeviceLevel {
        let elements = CoreAudioOutputChannelElements.all(for: deviceID)
        let scalar = volume(for: deviceID)
        let masterMute = readUInt32Property(
            objectID: deviceID, selector: kAudioDevicePropertyMute,
            scope: kAudioObjectPropertyScopeOutput, element: kAudioObjectPropertyElementMain
        )
        let channelMutes: [UInt32] = masterMute == nil ? elements.filter {
            $0 != kAudioObjectPropertyElementMain
        }.compactMap { element in
            readUInt32Property(objectID: deviceID, selector: kAudioDevicePropertyMute,
                               scope: kAudioObjectPropertyScopeOutput, element: element)
        } : []
        let muteState = Self.muteState(master: masterMute, channels: channelMutes)
        func canWrite(_ selector: AudioObjectPropertySelector) -> Bool {
            elements.contains { element in
                var address = propertyAddress(selector: selector, scope: kAudioObjectPropertyScopeOutput, element: element)
                return isSettable(objectID: deviceID, address: &address)
            }
        }
        return AudioDeviceLevel(scalar: scalar, canAdjust: scalar != nil && canWrite(kAudioDevicePropertyVolumeScalar),
                                muteState: muteState, canMute: muteState != .unknown && canWrite(kAudioDevicePropertyMute))
    }

    /// A readable master control is authoritative, matching `setMuted`'s master-first writes.
    /// Channel aggregation is needed only for devices without a readable master.
    nonisolated static func muteState(master: UInt32?, channels: [UInt32]) -> AudioDeviceMuteState {
        if let master { return master == 0 ? .unmuted : .muted }
        guard !channels.isEmpty else { return .unknown }
        if channels.allSatisfy({ $0 != 0 }) { return .muted }
        if channels.allSatisfy({ $0 == 0 }) { return .unmuted }
        return .partial
    }

    @discardableResult
    func toggleMute() -> Bool {
        guard let deviceID = defaultOutputDeviceID() else { return false }
        return setMuted(!isMuted(for: deviceID), for: deviceID)
    }

    @discardableResult
    func selectOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        guard deviceID != kAudioObjectUnknown,
              canBeDefaultOutputDevice(deviceID) else {
            return false
        }

        if #available(macOS 15.0, *) {
            let device = AudioHardwareDevice(id: deviceID)
            do {
                try AudioHardwareSystem.shared.setDefaultOutputDevice(device)
                try AudioHardwareSystem.shared.setDefaultSoundEffectsDevice(device)
                return true
            } catch {
                return setLegacyDefaultOutputDevice(deviceID)
            }
        }

        return setLegacyDefaultOutputDevice(deviceID)
    }

    private func setMuted(_ isMuted: Bool, for deviceID: AudioDeviceID) -> Bool {
        let value: UInt32 = isMuted ? 1 : 0
        var didSetMute = setUInt32Property(
            value,
            objectID: deviceID,
            selector: kAudioDevicePropertyMute,
            scope: kAudioObjectPropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        )

        if !didSetMute {
            for element in CoreAudioOutputChannelElements.channels(for: deviceID) {
                if setUInt32Property(
                    value,
                    objectID: deviceID,
                    selector: kAudioDevicePropertyMute,
                    scope: kAudioObjectPropertyScopeOutput,
                    element: element
                ) {
                    didSetMute = true
                }
            }
        }

        return didSetMute
    }

    private func isMuted(for deviceID: AudioDeviceID) -> Bool {
        for element in CoreAudioOutputChannelElements.all(for: deviceID) {
            guard let value = readUInt32Property(
                objectID: deviceID,
                selector: kAudioDevicePropertyMute,
                scope: kAudioObjectPropertyScopeOutput,
                element: element
            ) else {
                continue
            }
            return value != 0
        }
        return false
    }

    nonisolated private func isOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        hasOutputStreams(deviceID: deviceID) && canBeDefaultOutputDevice(deviceID)
    }

    nonisolated private func hasOutputStreams(deviceID: AudioDeviceID) -> Bool {
        var address = propertyAddress(
            selector: kAudioDevicePropertyStreams,
            scope: kAudioObjectPropertyScopeOutput
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        return status == noErr && dataSize >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    nonisolated private func canBeDefaultOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        if #available(macOS 15.0, *) {
            let device = AudioHardwareDevice(id: deviceID)
            return (try? device.canBeDefaultOutputDevice) == true
        }

        return audioDeviceCanBeDefault(deviceID)
    }

    nonisolated private func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = propertyAddress(selector: kAudioHardwarePropertyDefaultOutputDevice)
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            systemObjectID,
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    nonisolated private func isHidden(_ deviceID: AudioDeviceID) -> Bool {
        var address = propertyAddress(selector: kAudioDevicePropertyIsHidden)
        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var value = UInt32(0)
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &value)
        return status == noErr && value != 0
    }

    nonisolated private func deviceName(for deviceID: AudioDeviceID) -> String? {
        stringProperty(
            for: deviceID,
            selector: kAudioObjectPropertyName
        )
    }

    nonisolated private func deviceUID(for deviceID: AudioDeviceID) -> String? {
        stringProperty(
            for: deviceID,
            selector: kAudioDevicePropertyDeviceUID
        )
    }

    /// `kAudioDevicePropertyTransportType` is the public property that describes
    /// the hardware family of a device, which is what the system volume menu
    /// uses to tell headphones, displays and speakers apart.
    nonisolated private func transport(for deviceID: AudioDeviceID) -> AudioOutputTransport? {
        readUInt32Property(
            objectID: deviceID,
            selector: kAudioDevicePropertyTransportType,
            scope: kAudioObjectPropertyScopeGlobal,
            element: kAudioObjectPropertyElementMain
        )
        .map { AudioOutputTransport(coreAudioValue: $0) }
    }

    /// `kAudioDevicePropertyDataSource` reports the live source of a built-in
    /// output device, for example whether the headphone jack or the internal
    /// speakers are active.
    nonisolated private func dataSource(for deviceID: AudioDeviceID) -> AudioOutputDataSource? {
        readUInt32Property(
            objectID: deviceID,
            selector: kAudioDevicePropertyDataSource,
            scope: kAudioObjectPropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        )
        .map { AudioOutputDataSource(coreAudioValue: $0) }
    }

    /// `kAudioDevicePropertyIcon` is an optional CFURLRef to an image file the
    /// driver ships for the device, for example the icon of a HAL plugin.
    nonisolated private func iconURL(for deviceID: AudioDeviceID) -> URL? {
        var address = propertyAddress(selector: kAudioDevicePropertyIcon)
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var icon: Unmanaged<CFURL>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFURL>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &icon
        )

        guard status == noErr, let icon else { return nil }
        return icon.takeRetainedValue() as URL
    }

    nonisolated private func stringProperty(
        for deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = propertyAddress(selector: selector)
        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &name
        )

        guard status == noErr, let name else { return nil }
        let value = name.takeRetainedValue() as String
        return value.isEmpty ? nil : value
    }

    nonisolated private func audioObjectIDs(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> [AudioObjectID]? {
        var address = propertyAddress(selector: selector)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &dataSize) == noErr else {
            return nil
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var deviceIDs = Array(repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        var mutableDataSize = dataSize
        let status = deviceIDs.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &mutableDataSize,
                buffer.baseAddress!
            )
        }

        guard status == noErr else { return nil }
        return deviceIDs.filter { $0 != kAudioObjectUnknown }
    }

    nonisolated private func volume(for deviceID: AudioDeviceID) -> Double? {
        if let masterVolume = readFloat32Property(
            objectID: deviceID,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        ), isValidVolumeScalar(masterVolume) {
            return Double(masterVolume)
        }

        let channelVolumes = CoreAudioOutputChannelElements.channels(for: deviceID).compactMap { element -> Float32? in
            guard let value = readFloat32Property(
                objectID: deviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioObjectPropertyScopeOutput,
                element: element
            ), isValidVolumeScalar(value) else { return nil }
            return value
        }

        guard !channelVolumes.isEmpty else { return nil }
        let total = channelVolumes.reduce(Float32(0), +)
        return Double(total / Float32(channelVolumes.count))
    }

    nonisolated private func isValidVolumeScalar(_ value: Float32) -> Bool {
        value.isFinite && (0...1).contains(value)
    }

    nonisolated private func readFloat32Property(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Float32? {
        var address = propertyAddress(selector: selector, scope: scope, element: element)
        guard AudioObjectHasProperty(objectID, &address) else { return nil }

        var value = Float32(0)
        var dataSize = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value)
        return status == noErr ? value : nil
    }

    nonisolated private func readUInt32Property(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> UInt32? {
        var address = propertyAddress(selector: selector, scope: scope, element: element)
        guard AudioObjectHasProperty(objectID, &address) else { return nil }

        var value = UInt32(0)
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value)
        return status == noErr ? value : nil
    }

    private func setScalarProperty(
        _ value: Float32,
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Bool {
        var address = propertyAddress(selector: selector, scope: scope, element: element)
        guard isSettable(objectID: objectID, address: &address) else { return false }

        var mutableValue = value
        return AudioObjectSetPropertyData(
            objectID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &mutableValue
        ) == noErr
    }

    private func setUInt32Property(
        _ value: UInt32,
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Bool {
        var address = propertyAddress(selector: selector, scope: scope, element: element)
        guard isSettable(objectID: objectID, address: &address) else { return false }

        var mutableValue = value
        return AudioObjectSetPropertyData(
            objectID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &mutableValue
        ) == noErr
    }

    nonisolated private func isSettable(
        objectID: AudioObjectID,
        address: inout AudioObjectPropertyAddress
    ) -> Bool {
        guard AudioObjectHasProperty(objectID, &address) else { return false }

        var isSettable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(objectID, &address, &isSettable) == noErr
            && isSettable.boolValue
    }

    nonisolated private func audioDeviceCanBeDefault(_ deviceID: AudioDeviceID) -> Bool {
        var address = propertyAddress(
            selector: kAudioDevicePropertyDeviceCanBeDefaultDevice,
            scope: kAudioObjectPropertyScopeOutput
        )
        var canBeDefault = UInt32(0)
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &canBeDefault
        )
        return status == noErr && canBeDefault != 0
    }

    private func setLegacyDefaultOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        setDefaultAudioDevice(deviceID, selector: kAudioHardwarePropertyDefaultOutputDevice)
            && setDefaultAudioDevice(deviceID, selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
    }

    private func setDefaultAudioDevice(
        _ deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> Bool {
        var address = propertyAddress(selector: selector)
        var mutableDeviceID = deviceID
        return AudioObjectSetPropertyData(
            systemObjectID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &mutableDeviceID
        ) == noErr
    }

    nonisolated private func propertyAddress(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
    }
}
