import XCTest
@testable import StatusTrioCore

final class AudioDeviceLevelTests: XCTestCase {
    func testNativeReadbackRevisionSurvivesStatusCopiesAndPublishesImmediately() {
        let status = VolumeStatus(scalar: 0.4, isMuted: false, deviceName: "Current",
                                  nativeDeviceLevelReadbackRevision: 7)
        let copy = status.replacingExternalVolumeTransitionGeneration(2, controlSource: .native)
        XCTAssertEqual(copy.nativeDeviceLevelReadbackRevision, 7)
        let next = VolumeStatus(scalar: 0.4, isMuted: false, deviceName: "Current",
                                nativeDeviceLevelReadbackRevision: 8)
        XCTAssertFalse(status.changesOnlyLevel(comparedTo: next), "Authoritative readback cannot be coalesced as scalar-only noise")
    }

    func testMasterMuteReadbackTakesPrecedenceOverChannels() {
        XCTAssertEqual(CoreAudioOutputController.muteState(master: 1, channels: [0, 0]), .muted)
        XCTAssertEqual(CoreAudioOutputController.muteState(master: 0, channels: [1, 1]), .unmuted)
        XCTAssertEqual(CoreAudioOutputController.muteState(master: nil, channels: [1, 1]), .muted)
        XCTAssertEqual(CoreAudioOutputController.muteState(master: nil, channels: [0, 0]), .unmuted)
        XCTAssertEqual(CoreAudioOutputController.muteState(master: nil, channels: [1, 0]), .partial)
        XCTAssertEqual(CoreAudioOutputController.muteState(master: nil, channels: []), .unknown)
    }

    func testOutputReplacementKeepsCapabilitiesAndMute() {
        let level = AudioDeviceLevel(scalar: 0.4, canAdjust: true, muteState: .muted, canMute: true)
        let device = AudioOutputDevice(id: 42, name: "Other", uid: "other", isCurrent: false, level: level)
        XCTAssertEqual(device.volume, 0.4)
        let replaced = device.replacingVolume(0.7)
        XCTAssertEqual(replaced.level, AudioDeviceLevel(scalar: 0.7, canAdjust: true, muteState: .muted, canMute: true))
        XCTAssertNil(AudioDeviceLevel.unavailable.scalar)
        XCTAssertFalse(AudioDeviceLevel.unavailable.canAdjust)
        XCTAssertNil(AudioOutputDevice(id: 42, name: nil, isCurrent: false, volume: 0.9, level: .unavailable).volume)
    }
}

@MainActor
final class PerDeviceAudioOutputTests: XCTestCase {
    func testTargetedMasterMuteReadbackSupportsMuteUnmuteCycle() {
        let hardware = OutputMasterMuteFixture()
        let controller = CoreAudioOutputController(commandAccess: hardware.access)
        XCTAssertTrue(controller.toggleMute(forDeviceID: 22, expectedUID: "other"))
        XCTAssertEqual(hardware.master, 1)
        XCTAssertEqual(hardware.channels, [0, 0])
        XCTAssertTrue(controller.toggleMute(forDeviceID: 22, expectedUID: "other"))
        XCTAssertEqual(hardware.master, 0)
        XCTAssertEqual(hardware.writes, [true, false])
    }

    func testNonCurrentWriteAndMuteStayBoundToIdentity() {
        let hardware = OutputCommandFixture()
        let controller = CoreAudioOutputController(commandAccess: hardware.access)
        XCTAssertFalse(controller.isCurrentOutputDevice(22, expectedUID: "other"))
        XCTAssertTrue(controller.setVolume(0.8, forDeviceID: 22, expectedUID: "other"))
        XCTAssertEqual(hardware.volumeWrites.map(\.0), [22])
        XCTAssertEqual(hardware.volumeWrites.first?.1, 0.8)
        XCTAssertTrue(hardware.muteWrites.isEmpty, "Slider preserves explicit mute")
        XCTAssertTrue(controller.toggleMute(forDeviceID: 22, expectedUID: "other"))
        XCTAssertEqual(hardware.muteWrites.map(\.0), [22])
        XCTAssertEqual(hardware.muteWrites.first?.1, false)
    }

    func testHardwareWriteFailureIsReportedWithoutFallback() {
        let hardware = OutputCommandFixture()
        hardware.writesSucceed = false
        let controller = CoreAudioOutputController(commandAccess: hardware.access)
        XCTAssertFalse(controller.setVolume(0.8, forDeviceID: 22, expectedUID: "other"))
        XCTAssertFalse(controller.toggleMute(forDeviceID: 22, expectedUID: "other"))
        XCTAssertEqual(hardware.volumeWrites.count, 1)
        XCTAssertEqual(hardware.muteWrites.count, 1)
    }

    func testStaleUIDUnknownIdentityAndUnavailableCapabilitiesNeverWrite() {
        let hardware = OutputCommandFixture()
        let controller = CoreAudioOutputController(commandAccess: hardware.access)
        XCTAssertFalse(controller.setVolume(0.2, forDeviceID: 22, expectedUID: "replaced"))
        XCTAssertFalse(controller.toggleMute(forDeviceID: 22, expectedUID: nil))
        XCTAssertFalse(controller.toggleMute(forDeviceID: 22, expectedUID: ""))
        XCTAssertFalse(controller.setVolume(0.2, forDeviceID: 22, expectedUID: ""))
        XCTAssertFalse(controller.setVolume(.nan, forDeviceID: 22, expectedUID: "other"))
        XCTAssertFalse(controller.setVolume(0.2, forDeviceID: 99, expectedUID: "disconnected"))
        XCTAssertFalse(controller.toggleMute(forDeviceID: 99, expectedUID: "disconnected"))
        hardware.snapshot = .unavailable
        XCTAssertFalse(controller.setVolume(0.2, forDeviceID: 22, expectedUID: "other"))
        XCTAssertFalse(controller.toggleMute(forDeviceID: 22, expectedUID: "other"))
        XCTAssertTrue(hardware.volumeWrites.isEmpty)
        XCTAssertTrue(hardware.muteWrites.isEmpty)
    }
}

@MainActor
private final class OutputCommandFixture {
    var snapshot = AudioDeviceLevel(scalar: 0.4, canAdjust: true, muteState: .muted, canMute: true)
    var writesSucceed = true
    var volumeWrites: [(UInt32, Float32)] = []
    var muteWrites: [(UInt32, Bool)] = []
    var access: AudioOutputCommandAccess {
        AudioOutputCommandAccess(
            currentDeviceID: { 11 },
            uid: { $0 == 22 ? "other" : nil },
            level: { [self] _ in snapshot },
            writeVolume: { [self] id, value in volumeWrites.append((id, value)); return writesSucceed },
            writeMute: { [self] id, value in muteWrites.append((id, value)); return writesSucceed }
        )
    }
}

@MainActor
private final class OutputMasterMuteFixture {
    var master: UInt32 = 0
    let channels: [UInt32] = [0, 0]
    var writes: [Bool] = []
    var access: AudioOutputCommandAccess {
        AudioOutputCommandAccess(
            currentDeviceID: { 11 },
            uid: { $0 == 22 ? "other" : nil },
            level: { [self] _ in
                AudioDeviceLevel(scalar: 0.4, canAdjust: true,
                                 muteState: CoreAudioOutputController.muteState(master: master, channels: channels),
                                 canMute: true)
            },
            writeVolume: { _, _ in false },
            writeMute: { [self] _, muted in master = muted ? 1 : 0; writes.append(muted); return true }
        )
    }
}
