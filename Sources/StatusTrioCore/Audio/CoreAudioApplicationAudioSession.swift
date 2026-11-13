import ApplicationAudioDSP
import CoreAudio
import Foundation

@available(macOS 14.2, *)
protocol ApplicationAudioSessionHAL: Sendable {
    func validate(processIDs: [AudioObjectID], outputDeviceUID: String) throws
    func createTap(processIDs: [AudioObjectID], outputDeviceUID: String) throws -> AudioObjectID
    func tapFormat(_ tap: AudioObjectID) throws -> AudioStreamBasicDescription
    func createAggregate(tap: AudioObjectID, outputDeviceUID: String) throws -> AudioObjectID
    func validateAggregate(_ aggregate: AudioObjectID, tap: AudioObjectID, outputDeviceUID: String, tapFormat: AudioStreamBasicDescription) throws
    func registerIO(_ aggregate: AudioObjectID, context: OpaquePointer) throws -> AudioDeviceIOProcID
    func start(_ aggregate: AudioObjectID, io: AudioDeviceIOProcID) throws
    func stop(_ aggregate: AudioObjectID, io: AudioDeviceIOProcID) -> OSStatus
    func unregisterIO(_ aggregate: AudioObjectID, io: AudioDeviceIOProcID) -> OSStatus
    func destroyAggregate(_ aggregate: AudioObjectID) -> OSStatus
    func destroyTap(_ tap: AudioObjectID) -> OSStatus
}

enum CoreAudioApplicationAudioError: LocalizedError {
    case unsupportedRoute
    case unsupportedFormat
    case allocationFailed
    case hardware(operation: String, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .unsupportedRoute: "This application needs one stereo output endpoint with no microphone input streams."
        case .unsupportedFormat: "This output does not support the application's stereo audio format."
        case .allocationFailed: "The application audio processor could not be created."
        case let .hardware(operation, status): "Application audio \(operation) failed (\(status))."
        }
    }
}

/// Demand-owned interception. Construction alone never creates a tap or requests access.
@available(macOS 14.2, *)
@MainActor
final class CoreAudioApplicationAudioSession {
    private let hal: any ApplicationAudioSessionHAL
    private var resources: ApplicationAudioSessionResources?
    private(set) var cleanupErrors: [OSStatus] = []
    var onCleanupFailure: (([OSStatus]) -> Void)?
    var hasUnreleasedResources: Bool { resources?.hasOwnedHandles ?? false }

    convenience init() { self.init(hal: NativeApplicationAudioSessionHAL()) }

    init(hal: any ApplicationAudioSessionHAL) { self.hal = hal }

    func start(processIDs: [AudioObjectID], outputDeviceUID: String, gain: Float) throws {
        stop()
        guard resources == nil else {
            throw CoreAudioApplicationAudioError.hardware(operation: "release previous output", status: cleanupErrors.first ?? -1)
        }
        cleanupErrors = []
        guard !processIDs.isEmpty, !processIDs.contains(kAudioObjectUnknown), !outputDeviceUID.isEmpty else {
            throw CoreAudioApplicationAudioError.unsupportedRoute
        }
        try hal.validate(processIDs: processIDs, outputDeviceUID: outputDeviceUID)
        guard let context = STAudioDSPCreate(gain) else { throw CoreAudioApplicationAudioError.allocationFailed }
        let pending = ApplicationAudioSessionResources(hal: hal, context: context)
        do {
            let tap = try hal.createTap(processIDs: processIDs, outputDeviceUID: outputDeviceUID)
            pending.tap = tap
            var format = try hal.tapFormat(tap)
            guard STAudioDSPSupportsFormat(&format) else { throw CoreAudioApplicationAudioError.unsupportedFormat }
            let aggregate = try hal.createAggregate(tap: tap, outputDeviceUID: outputDeviceUID)
            pending.aggregate = aggregate
            try hal.validateAggregate(aggregate, tap: tap, outputDeviceUID: outputDeviceUID, tapFormat: format)
            let io = try hal.registerIO(aggregate, context: context)
            pending.io = io
            // Even a failed AudioDeviceStart can have partially started IO; always balance it.
            try hal.start(aggregate, io: io)
            resources = pending
        } catch {
            cleanupErrors = pending.release()
            if pending.hasOwnedHandles { resources = pending }
            if !cleanupErrors.isEmpty { onCleanupFailure?(cleanupErrors) }
            throw error
        }
    }

    func setGain(_ gain: Float) {
        guard let context = resources?.context else { return }
        STAudioDSPSetGain(context, gain)
    }

    func stop() {
        guard let current = resources else { return }
        cleanupErrors = current.release()
        if !current.hasOwnedHandles { resources = nil }
        if !cleanupErrors.isEmpty { onCleanupFailure?(cleanupErrors) }
    }
}

/// No Swift object is read on the realtime thread. This owner can be destroyed from a
/// nonisolated deinit; its only cross-thread field is the C context's lock-free gain.
@available(macOS 14.2, *)
private final class ApplicationAudioSessionResources: @unchecked Sendable {
    let hal: any ApplicationAudioSessionHAL
    private(set) var context: OpaquePointer?
    var tap: AudioObjectID?
    var aggregate: AudioObjectID?
    var io: AudioDeviceIOProcID?

    init(hal: any ApplicationAudioSessionHAL, context: OpaquePointer) {
        self.hal = hal
        self.context = context
    }

    deinit { _ = release() }

    var hasOwnedHandles: Bool { tap != nil || aggregate != nil || io != nil }

    @discardableResult
    func release() -> [OSStatus] {
        // Fixed, bounded best-effort cleanup. Preserve any failed handles for the next
        // explicit stop, rather than losing the ability to restore native playback.
        var errors = releaseOnce()
        if hasOwnedHandles { errors = releaseOnce() }
        return errors
    }

    private func releaseOnce() -> [OSStatus] {
        var errors: [OSStatus] = []
        // If HAL cannot stop immediately, suppress the intercepted copy while native
        // playback resumes; never leave two audible copies after a failed cleanup.
        if let context { STAudioDSPSetGain(context, 0) }
        var callbackRemoved = io == nil
        if let aggregate {
            if let io {
                let stopped = hal.stop(aggregate, io: io)
                if stopped != noErr { errors.append(stopped) }
                let unregistered = hal.unregisterIO(aggregate, io: io)
                callbackRemoved = unregistered == noErr
                if unregistered != noErr { errors.append(unregistered) } else { self.io = nil }
            }
            let destroyed = hal.destroyAggregate(aggregate)
            callbackRemoved = callbackRemoved || destroyed == noErr
            if destroyed != noErr { errors.append(destroyed) } else {
                self.aggregate = nil
                self.io = nil
            }
        }
        // Destruction of the tap restores the process's native route even when HAL
        // stop/unregistration reports an error. No default-device settings are changed.
        if let tap {
            let destroyed = hal.destroyTap(tap)
            if destroyed != noErr { errors.append(destroyed) } else { self.tap = nil }
        }
        if callbackRemoved, let context {
            STAudioDSPDestroy(context)
            self.context = nil
        }
        // In the exceptional case where BOTH callback and device destruction fail,
        // retain the small C allocation: freeing memory still used by HAL is unsafe.
        return errors
    }
}
