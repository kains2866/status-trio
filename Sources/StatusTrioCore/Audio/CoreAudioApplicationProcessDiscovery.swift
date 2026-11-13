import AppKit
import CoreAudio
import CoreFoundation
import Darwin
import Foundation

@MainActor
final class CoreAudioApplicationProcessDiscovery: ApplicationAudioProcessDiscovering {
    private let worker = CoreAudioApplicationProcessWorker()
    private let workspaceNotifications = NSWorkspace.shared.notificationCenter
    // MainActor installs/removes this token. Nonisolated deinit only removes its registration;
    // the callback captures the Sendable worker, never this token or its owning discovery object.
    nonisolated(unsafe) private var terminationObserver: NSObjectProtocol?

    func start(_ receive: @escaping @MainActor @Sendable (Result<[ApplicationAudioProcessSnapshot], Error>) -> Void) {
        if terminationObserver == nil {
            let worker = worker
            terminationObserver = workspaceNotifications.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: nil
            ) { _ in worker.workspaceDidChange() }
        }
        worker.start(receive)
    }

    func stop() {
        if let terminationObserver { workspaceNotifications.removeObserver(terminationObserver) }
        terminationObserver = nil
        worker.stop()
    }

    deinit {
        if let terminationObserver { workspaceNotifications.removeObserver(terminationObserver) }
        worker.stop()
    }
}

private enum ApplicationAudioDiscoveryError: Error, LocalizedError {
    case property(OSStatus)
    case invalidProperty

    var errorDescription: String? {
        switch self {
        case .property(let status): return "CoreAudio (\(status))"
        case .invalidProperty: return "CoreAudio: invalid process or device property"
        }
    }
}

/// All mutable worker state and HAL property reads are confined to `queue`.
/// The unchecked conformance bridges CoreAudio's C listener blocks; no hardware object crosses to UI.
private final class CoreAudioApplicationProcessWorker: @unchecked Sendable {
    private struct Key: Hashable {
        let objectID: AudioObjectID
        let selector: AudioObjectPropertySelector
        let scope: AudioObjectPropertyScope
        var address: AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        }
    }
    private let queue = DispatchQueue(label: "StatusTrio.application-audio.discovery", qos: .utility)
    private let ownPID = getpid()
    private var handler: (@MainActor @Sendable (Result<[ApplicationAudioProcessSnapshot], Error>) -> Void)?
    private var registrations: [Key: AudioObjectPropertyListenerBlock] = [:]
    private var refreshScheduled = false

    func start(_ receive: @escaping @MainActor @Sendable (Result<[ApplicationAudioProcessSnapshot], Error>) -> Void) {
        queue.async { [self] in
            removeListeners()
            handler = receive
            refresh()
        }
    }

    func stop() {
        // This block retains the worker until removal finishes, even when its MainActor owner deinitializes.
        queue.async { [self] in
            handler = nil
            refreshScheduled = false
            removeListeners()
        }
    }

    func workspaceDidChange() {
        // An app can leave HAL while paused. Workspace termination still wakes owner-liveness
        // reconciliation and releases its saved adjustment without any background polling.
        queue.async { [weak self] in self?.scheduleRefresh() }
    }

    private func refresh() {
        guard let handler else { return }
        do {
            let system = AudioObjectID(kAudioObjectSystemObject)
            // Install the list listener before enumeration so additions during the read cannot be lost.
            for selector in [kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDevices,
                             kAudioHardwarePropertyDefaultOutputDevice] {
                try addListener(Key(objectID: system, selector: selector, scope: kAudioObjectPropertyScopeGlobal))
            }
            let processes = try readIDs(system, kAudioHardwarePropertyProcessObjectList)
            let deviceIDs = try readIDs(system, kAudioHardwarePropertyDevices).filter {
                try !readString($0, kAudioDevicePropertyDeviceUID).hasPrefix("com.statustrio.application-audio.")
            }
            var wanted: Set<Key> = [
                Key(objectID: system, selector: kAudioHardwarePropertyProcessObjectList, scope: kAudioObjectPropertyScopeGlobal),
                Key(objectID: system, selector: kAudioHardwarePropertyDevices, scope: kAudioObjectPropertyScopeGlobal),
                Key(objectID: system, selector: kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
            ]
            for id in processes {
                for selector in [kAudioProcessPropertyPID, kAudioProcessPropertyBundleID,
                                 kAudioProcessPropertyIsRunningInput, kAudioProcessPropertyIsRunningOutput] {
                    wanted.insert(Key(objectID: id, selector: selector, scope: kAudioObjectPropertyScopeGlobal))
                }
                for scope in [kAudioDevicePropertyScopeInput, kAudioDevicePropertyScopeOutput] {
                    wanted.insert(Key(objectID: id, selector: kAudioProcessPropertyDevices, scope: scope))
                }
            }
            for id in deviceIDs {
                for selector in [kAudioDevicePropertyDeviceIsAlive, kAudioDevicePropertyDeviceUID,
                                 kAudioObjectPropertyName, kAudioDevicePropertyNominalSampleRate] {
                    wanted.insert(Key(objectID: id, selector: selector, scope: kAudioObjectPropertyScopeGlobal))
                }
                let streamsKey = Key(objectID: id, selector: kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
                wanted.insert(streamsKey)
                try addListener(streamsKey)
                for stream in try readIDs(id, kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput) {
                    for selector in [kAudioStreamPropertyVirtualFormat, kAudioStreamPropertyPhysicalFormat] {
                        wanted.insert(Key(objectID: stream, selector: selector, scope: kAudioObjectPropertyScopeGlobal))
                    }
                }
            }
            for key in Array(registrations.keys) where !wanted.contains(key) { removeListener(key) }
            for key in wanted where registrations[key] == nil {
                // Processes/devices can disappear between list enumeration and listener registration.
                // A failed subscription must not leave an adjusted process without exit/route observation.
                try addListener(key)
            }
            let snapshots = try processes.compactMap { try readProcess($0) }
            Task { @MainActor in handler(.success(snapshots)) }
        } catch {
            // A failed read or subscription is a safety boundary: restore native playback upstream.
            self.handler = nil
            removeListeners()
            Task { @MainActor in handler(.failure(error)) }
        }
    }

    private func readProcess(_ id: AudioObjectID) throws -> ApplicationAudioProcessSnapshot? {
        let pid: Int32 = try readValue(id, kAudioProcessPropertyPID, initial: 0)
        guard pid > 0, pid != ownPID else { return nil }
        let input: UInt32 = try readValue(id, kAudioProcessPropertyIsRunningInput, initial: 0)
        let output: UInt32 = try readValue(id, kAudioProcessPropertyIsRunningOutput, initial: 0)
        guard input <= 1, output <= 1 else { throw ApplicationAudioDiscoveryError.invalidProperty }
        // Keep idle process identities to distinguish playback pause from exit or PID reuse.
        let bundle = try? readString(id, kAudioProcessPropertyBundleID)
        let inputs = input == 1 ? readDevices(id, scope: kAudioDevicePropertyScopeInput) : ([], true)
        let outputs = output == 1 ? readDevices(id, scope: kAudioDevicePropertyScopeOutput) : ([], true)
        return ApplicationAudioProcessSnapshot(objectID: id, pid: pid, bundleID: bundle,
            isRunningInput: input == 1, isRunningOutput: output == 1,
            inputDevices: inputs.0, outputDevices: outputs.0, outputRouteIsComplete: outputs.1)
    }

    private func readDevices(_ processID: AudioObjectID, scope: AudioObjectPropertyScope) -> ([ApplicationAudioDeviceSnapshot], Bool) {
        do {
            let ids = try readIDs(processID, kAudioProcessPropertyDevices, scope: scope)
            var devices: [ApplicationAudioDeviceSnapshot] = []
            for id in ids {
                let alive: UInt32 = try readValue(id, kAudioDevicePropertyDeviceIsAlive, initial: 0)
                guard alive == 1 else { return ([], false) }
                let uid = try readString(id, kAudioDevicePropertyDeviceUID)
                guard !uid.isEmpty else { return ([], false) }
                // Our private output is an implementation detail, never an independently routed app.
                guard !uid.hasPrefix("com.statustrio.application-audio.") else { continue }
                let name = try readString(id, kAudioObjectPropertyName)
                let fingerprint = scope == kAudioDevicePropertyScopeOutput ? try routeFingerprint(id) : ""
                devices.append(ApplicationAudioDeviceSnapshot(id: id, uid: uid, name: name, routeFingerprint: fingerprint))
            }
            return (devices, !devices.isEmpty)
        } catch {
            return ([], false)
        }
    }

    private func routeFingerprint(_ device: AudioObjectID) throws -> String {
        let rate: Float64 = try readValue(device, kAudioDevicePropertyNominalSampleRate, initial: 0)
        let streams = try readIDs(device, kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
        var values = ["rate:\(rate)"]
        for stream in streams.sorted() {
            for selector in [kAudioStreamPropertyVirtualFormat, kAudioStreamPropertyPhysicalFormat] {
                let format = try readValue(stream, selector, initial: AudioStreamBasicDescription())
                values.append("\(stream):\(selector):\(format.mSampleRate):\(format.mFormatID):\(format.mFormatFlags):\(format.mBytesPerPacket):\(format.mFramesPerPacket):\(format.mBytesPerFrame):\(format.mChannelsPerFrame):\(format.mBitsPerChannel)")
            }
        }
        return values.joined(separator: "|")
    }

    private func addListener(_ key: Key) throws {
        guard registrations[key] == nil else { return }
        var address = key.address
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.scheduleRefresh()
        }
        let status = AudioObjectAddPropertyListenerBlock(key.objectID, &address, queue, block)
        guard status == noErr else { throw ApplicationAudioDiscoveryError.property(status) }
        registrations[key] = block
    }

    private func scheduleRefresh() {
        guard handler != nil, !refreshScheduled else { return }
        refreshScheduled = true
        // Coalesce the current batch of HAL events; no timer, retry loop or periodic idle work.
        queue.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.refresh()
        }
    }

    private func removeListener(_ key: Key) {
        guard let block = registrations.removeValue(forKey: key) else { return }
        var address = key.address
        _ = AudioObjectRemovePropertyListenerBlock(key.objectID, &address, queue, block)
    }

    private func removeListeners() {
        for key in Array(registrations.keys) { removeListener(key) }
    }

    private func readIDs(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [AudioObjectID] {
        var address = Key(objectID: id, selector: selector, scope: scope).address
        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size)
        guard sizeStatus == noErr else { throw ApplicationAudioDiscoveryError.property(sizeStatus) }
        guard Int(size) % MemoryLayout<AudioObjectID>.size == 0 else { throw ApplicationAudioDiscoveryError.invalidProperty }
        guard size > 0 else { return [] }
        let expectedSize = size
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = ids.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, bytes.baseAddress!)
        }
        guard status == noErr else { throw ApplicationAudioDiscoveryError.property(status) }
        guard size == expectedSize else { throw ApplicationAudioDiscoveryError.invalidProperty }
        return ids.filter { $0 != kAudioObjectUnknown }
    }

    private func readValue<Value>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, initial: Value) throws -> Value {
        var address = Key(objectID: id, selector: selector, scope: kAudioObjectPropertyScopeGlobal).address
        var value = initial
        var size = UInt32(MemoryLayout<Value>.size)
        let status = withUnsafeMutableBytes(of: &value) { bytes in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, bytes.baseAddress!)
        }
        guard status == noErr else { throw ApplicationAudioDiscoveryError.property(status) }
        guard size == MemoryLayout<Value>.size else { throw ApplicationAudioDiscoveryError.invalidProperty }
        return value
    }

    private func readString(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var address = Key(objectID: id, selector: selector, scope: kAudioObjectPropertyScopeGlobal).address
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        guard status == noErr else { throw ApplicationAudioDiscoveryError.property(status) }
        guard let value else { throw ApplicationAudioDiscoveryError.invalidProperty }
        let string = value.takeRetainedValue()
        guard size == MemoryLayout<CFString?>.size else { throw ApplicationAudioDiscoveryError.invalidProperty }
        return string as String
    }
}
