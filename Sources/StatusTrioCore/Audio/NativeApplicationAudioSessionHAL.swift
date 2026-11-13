import ApplicationAudioDSP
import CoreAudio
import Foundation

@available(macOS 14.2, *)
struct NativeApplicationAudioSessionHAL: ApplicationAudioSessionHAL {
    func validate(processIDs: [AudioObjectID], outputDeviceUID: String) throws {
        let output = try device(uid: outputDeviceUID)
        // Aggregate/multi-output devices have routing semantics this first engine does not own.
        let deviceClass: AudioClassID = try value(output, kAudioObjectPropertyClass, initial: 0)
        guard deviceClass != kAudioAggregateDeviceClassID else { throw CoreAudioApplicationAudioError.unsupportedRoute }
        let outputStreams = try streams(output, scope: kAudioObjectPropertyScopeOutput)
        try Self.validateTopology(inputStreamCount: streams(output, scope: kAudioObjectPropertyScopeInput).count,
                                  outputStreamCount: outputStreams.count)
        var format = try streamFormat(outputStreams[0])
        guard STAudioDSPSupportsFormat(&format) else { throw CoreAudioApplicationAudioError.unsupportedFormat }
        for process in processIDs {
            let routes = try objectIDs(process, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput)
            guard routes == [output] else { throw CoreAudioApplicationAudioError.unsupportedRoute }
        }
    }

    func createTap(processIDs: [AudioObjectID], outputDeviceUID: String) throws -> AudioObjectID {
        let description = CATapDescription(processes: processIDs, deviceUID: outputDeviceUID, stream: 0)
        description.name = "Status Trio Application Output"
        description.isPrivate = true
        // A created but unread tap never mutes native playback on partial setup failure.
        description.muteBehavior = .mutedWhenTapped
        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tap), "create tap")
        return tap
    }

    func tapFormat(_ tap: AudioObjectID) throws -> AudioStreamBasicDescription {
        try value(tap, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
    }

    func createAggregate(tap: AudioObjectID, outputDeviceUID: String) throws -> AudioObjectID {
        let tapUID: CFString = try value(tap, kAudioTapPropertyUID, initial: "" as CFString)
        let composition: [String: Any] = [
            kAudioAggregateDeviceUIDKey: "com.statustrio.application-audio.\(UUID().uuidString)",
            kAudioAggregateDeviceNameKey: "Status Trio Application Output",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [[
                kAudioSubDeviceUIDKey: outputDeviceUID,
                kAudioSubDeviceInputChannelsKey: 0,
                kAudioSubDeviceOutputChannelsKey: 2
            ]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapUID,
                kAudioSubTapDriftCompensationKey: true
            ]],
            // Do not wait for an application's first audio buffer on the main actor.
            kAudioAggregateDeviceTapAutoStartKey: false
        ]
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregate), "create output device")
        return aggregate
    }

    func validateAggregate(_ aggregate: AudioObjectID, tap: AudioObjectID, outputDeviceUID: String,
                           tapFormat: AudioStreamBasicDescription) throws {
        let physicalOutput = try device(uid: outputDeviceUID)
        try Self.validateTopology(inputStreamCount: streams(physicalOutput, scope: kAudioObjectPropertyScopeInput).count,
                                  outputStreamCount: streams(physicalOutput, scope: kAudioObjectPropertyScopeOutput).count)
        let expectedUID: CFString = try value(tap, kAudioTapPropertyUID, initial: "" as CFString)
        let tapUIDs: CFArray = try value(aggregate, kAudioAggregateDevicePropertyTapList, initial: [] as CFArray)
        let activeTaps = try objectIDs(aggregate, kAudioAggregateDevicePropertySubTapList)
        try Self.validateTapMembership(expected: expectedUID as String, actual: tapUIDs as? [String] ?? [],
                                       activeCount: activeTaps.count)
        // A physical input stream must never be mistaken for tapped process output.
        // Reject rather than reading any microphone channels if HAL ignored channels-in=0.
        let inputs = try streams(aggregate, scope: kAudioObjectPropertyScopeInput)
        let outputs = try streams(aggregate, scope: kAudioObjectPropertyScopeOutput)
        guard inputs.count == 1, outputs.count == 1 else { throw CoreAudioApplicationAudioError.unsupportedFormat }
        for stream in inputs + outputs {
            var format = try streamFormat(stream)
            guard STAudioDSPSupportsFormat(&format), format.mSampleRate == tapFormat.mSampleRate else {
                throw CoreAudioApplicationAudioError.unsupportedFormat
            }
        }
    }

    func registerIO(_ aggregate: AudioObjectID, context: OpaquePointer) throws -> AudioDeviceIOProcID {
        var io: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcID(aggregate, STAudioDSPIOProc, UnsafeMutableRawPointer(context), &io), "register processor")
        guard let io else { throw CoreAudioApplicationAudioError.allocationFailed }
        return io
    }

    func start(_ aggregate: AudioObjectID, io: AudioDeviceIOProcID) throws {
        try check(AudioDeviceStart(aggregate, io), "start processor")
    }

    func stop(_ aggregate: AudioObjectID, io: AudioDeviceIOProcID) -> OSStatus { AudioDeviceStop(aggregate, io) }
    func unregisterIO(_ aggregate: AudioObjectID, io: AudioDeviceIOProcID) -> OSStatus { AudioDeviceDestroyIOProcID(aggregate, io) }
    func destroyAggregate(_ aggregate: AudioObjectID) -> OSStatus { AudioHardwareDestroyAggregateDevice(aggregate) }
    func destroyTap(_ tap: AudioObjectID) -> OSStatus { AudioHardwareDestroyProcessTap(tap) }

    static func validateTopology(inputStreamCount: Int, outputStreamCount: Int) throws {
        guard inputStreamCount == 0, outputStreamCount == 1 else {
            throw CoreAudioApplicationAudioError.unsupportedRoute
        }
    }

    static func validateTapMembership(expected: String, actual: [String], activeCount: Int) throws {
        guard actual == [expected], activeCount == 1 else {
            throw CoreAudioApplicationAudioError.unsupportedFormat
        }
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw CoreAudioApplicationAudioError.hardware(operation: operation, status: status) }
    }

    private func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, initial: T) throws -> T {
        var result = initial
        var property = address(selector, scope: scope)
        var size = UInt32(MemoryLayout<T>.size)
        let expected = size
        let status = withUnsafeMutablePointer(to: &result) { pointer in
            AudioObjectGetPropertyData(object, &property, 0, nil, &size, UnsafeMutableRawPointer(pointer))
        }
        try check(status, "read property")
        guard size == expected else { throw CoreAudioApplicationAudioError.unsupportedFormat }
        return result
    }

    private func objectIDs(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                           scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [AudioObjectID] {
        var property = address(selector, scope: scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &property, 0, nil, &size), "read object list size")
        guard size % UInt32(MemoryLayout<AudioObjectID>.stride) == 0, size <= 65_536 else {
            throw CoreAudioApplicationAudioError.unsupportedRoute
        }
        guard size != 0 else { return [] }
        let expected = size
        var result = Array(repeating: AudioObjectID(kAudioObjectUnknown), count: Int(size) / MemoryLayout<AudioObjectID>.stride)
        let status = result.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(object, &property, 0, nil, &size, bytes.baseAddress!)
        }
        try check(status, "read object list")
        guard size == expected else { throw CoreAudioApplicationAudioError.unsupportedRoute }
        return result
    }

    private func streams(_ device: AudioObjectID, scope: AudioObjectPropertyScope) throws -> [AudioObjectID] {
        try objectIDs(device, kAudioDevicePropertyStreams, scope: scope)
    }

    private func streamFormat(_ stream: AudioObjectID) throws -> AudioStreamBasicDescription {
        try value(stream, kAudioStreamPropertyVirtualFormat, initial: AudioStreamBasicDescription())
    }

    private func device(uid: String) throws -> AudioObjectID {
        let devices = try objectIDs(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
        for device in devices {
            let deviceUID: CFString = try value(device, kAudioDevicePropertyDeviceUID, initial: "" as CFString)
            if deviceUID as String == uid { return device }
        }
        throw CoreAudioApplicationAudioError.unsupportedRoute
    }
}
