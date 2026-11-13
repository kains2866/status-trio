import CoreAudio
import ApplicationAudioDSP
import XCTest
@testable import StatusTrioCore

@available(macOS 14.2, *)
@MainActor
final class CoreAudioApplicationAudioSessionTests: XCTestCase {
    func testPartialSetupFailureDestroysTapBeforeReturning() {
        let hal = SessionHALFixture(failing: "aggregate")
        let session = CoreAudioApplicationAudioSession(hal: hal)
        XCTAssertThrowsError(try session.start(processIDs: [55], outputDeviceUID: "speakers", gain: 0.4))
        XCTAssertEqual(hal.events, ["validate", "tap", "tapFormat", "aggregate", "destroyTap"])
        session.stop()
        XCTAssertEqual(hal.events.last, "destroyTap")
    }

    func testFailedStartStopsUnregistersAndDestroysBeforeRestoringNativeOutput() {
        let hal = SessionHALFixture(failing: "start")
        let session = CoreAudioApplicationAudioSession(hal: hal)
        XCTAssertThrowsError(try session.start(processIDs: [55], outputDeviceUID: "speakers", gain: 0))
        XCTAssertEqual(Array(hal.events.suffix(4)), ["stop", "unregister", "destroyAggregate", "destroyTap"])
    }

    func testStopIsIdempotentAndStopsIOBeforeFreeingOwnedObjects() throws {
        let hal = SessionHALFixture()
        let session = CoreAudioApplicationAudioSession(hal: hal)
        try session.start(processIDs: [55], outputDeviceUID: "speakers", gain: 0.4)
        session.stop()
        let events = hal.events
        session.stop()
        XCTAssertEqual(hal.events, events)
        XCTAssertEqual(Array(events.suffix(4)), ["stop", "unregister", "destroyAggregate", "destroyTap"])
    }

    func testFailedCleanupRetainsHandlesAndReportsFailureUntilExplicitStopSucceeds() throws {
        let hal = SessionHALFixture()
        let session = CoreAudioApplicationAudioSession(hal: hal)
        try session.start(processIDs: [55], outputDeviceUID: "speakers", gain: 0.4)
        hal.cleanupFails = true
        var failures: [[OSStatus]] = []
        session.onCleanupFailure = { failures.append($0) }
        session.stop()
        XCTAssertFalse(session.cleanupErrors.isEmpty)
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(hal.events.filter { $0 == "destroyTap" }.count, 2)
        hal.cleanupFails = false
        session.stop()
        XCTAssertTrue(session.cleanupErrors.isEmpty)
        XCTAssertEqual(hal.events.last, "destroyTap")
        XCTAssertEqual(hal.events.filter { $0 == "destroyTap" }.count, 3)
    }

    func testNativeTopologyRejectsAnyPhysicalMicrophoneInput() {
        XCTAssertThrowsError(try NativeApplicationAudioSessionHAL.validateTopology(inputStreamCount: 1, outputStreamCount: 1))
        XCTAssertThrowsError(try NativeApplicationAudioSessionHAL.validateTopology(inputStreamCount: 0, outputStreamCount: 2))
        XCTAssertNoThrow(try NativeApplicationAudioSessionHAL.validateTopology(inputStreamCount: 0, outputStreamCount: 1))
    }

    func testTapMembershipRejectsMissingOrAdditionalTapSources() {
        XCTAssertThrowsError(try NativeApplicationAudioSessionHAL.validateTapMembership(expected: "owned", actual: [], activeCount: 1))
        XCTAssertThrowsError(try NativeApplicationAudioSessionHAL.validateTapMembership(expected: "owned", actual: ["other"], activeCount: 1))
        XCTAssertThrowsError(try NativeApplicationAudioSessionHAL.validateTapMembership(expected: "owned", actual: ["owned", "other"], activeCount: 2))
        XCTAssertThrowsError(try NativeApplicationAudioSessionHAL.validateTapMembership(expected: "owned", actual: ["owned"], activeCount: 0))
        XCTAssertNoThrow(try NativeApplicationAudioSessionHAL.validateTapMembership(expected: "owned", actual: ["owned"], activeCount: 1))
    }

    func testInvalidRouteDoesNotCreateAnInterception() {
        let hal = SessionHALFixture(failing: "validate")
        let session = CoreAudioApplicationAudioSession(hal: hal)
        XCTAssertThrowsError(try session.start(processIDs: [55], outputDeviceUID: "speakers", gain: 0.4))
        XCTAssertEqual(hal.events, ["validate"])
    }

    func testUnsupportedFormatNeverStartsTapReading() {
        let hal = SessionHALFixture(failing: "aggregateFormat")
        let session = CoreAudioApplicationAudioSession(hal: hal)
        XCTAssertThrowsError(try session.start(processIDs: [55], outputDeviceUID: "speakers", gain: 0.4))
        XCTAssertFalse(hal.events.contains("start"))
        XCTAssertEqual(Array(hal.events.suffix(2)), ["destroyAggregate", "destroyTap"])
    }
}

private final class SessionHALFixture: ApplicationAudioSessionHAL, @unchecked Sendable {
    var events: [String] = []
    var cleanupFails = false
    let failing: String?
    init(failing: String? = nil) { self.failing = failing }
    func record(_ event: String) throws {
        events.append(event)
        if failing == event { throw NSError(domain: "SessionHALFixture", code: 1) }
    }
    func validate(processIDs: [AudioObjectID], outputDeviceUID: String) throws { try record("validate") }
    func createTap(processIDs: [AudioObjectID], outputDeviceUID: String) throws -> AudioObjectID {
        try record("tap"); return 101
    }
    func tapFormat(_ tap: AudioObjectID) throws -> AudioStreamBasicDescription {
        try record("tapFormat")
        return AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
    }
    func createAggregate(tap: AudioObjectID, outputDeviceUID: String) throws -> AudioObjectID {
        try record("aggregate"); return 102
    }
    func validateAggregate(_ aggregate: AudioObjectID, tap: AudioObjectID, outputDeviceUID: String, tapFormat: AudioStreamBasicDescription) throws {
        try record("aggregateFormat")
    }
    func registerIO(_ aggregate: AudioObjectID, context: OpaquePointer) throws -> AudioDeviceIOProcID {
        try record("register"); return STAudioDSPIOProc
    }
    func start(_ aggregate: AudioObjectID, io: AudioDeviceIOProcID) throws { try record("start") }
    func stop(_ aggregate: AudioObjectID, io: AudioDeviceIOProcID) -> OSStatus { events.append("stop"); return cleanupFails ? -1 : noErr }
    func unregisterIO(_ aggregate: AudioObjectID, io: AudioDeviceIOProcID) -> OSStatus { events.append("unregister"); return cleanupFails ? -1 : noErr }
    func destroyAggregate(_ aggregate: AudioObjectID) -> OSStatus { events.append("destroyAggregate"); return cleanupFails ? -1 : noErr }
    func destroyTap(_ tap: AudioObjectID) -> OSStatus { events.append("destroyTap"); return cleanupFails ? -1 : noErr }
}
