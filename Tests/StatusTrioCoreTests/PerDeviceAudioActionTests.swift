import XCTest
@testable import StatusTrioCore

@MainActor
final class PerDeviceAudioActionTests: XCTestCase {
    func testCommandsRejectMissingOrBlankCapturedUIDEvenWhenNumericIDWasReused() {
        let output = AudioOutputDevice(id: 9, name: "Replacement", uid: "replacement", isCurrent: false)
        let input = AudioInputDevice(id: 11, uid: "replacement-mic", name: "Replacement mic")
        var dispatchedCommands = 0
        let actions = StatusPanelActions(
            outputDevices: { [output] }, inputDevices: { [input] },
            setOutputLevel: { _, _ in dispatchedCommands += 1 },
            finishOutputLevelAdjustment: { _ in dispatchedCommands += 1 },
            toggleOutputMute: { _ in dispatchedCommands += 1 },
            setInputLevel: { _, _, _ in dispatchedCommands += 1 },
            toggleInputDeviceMute: { _ in dispatchedCommands += 1 }
        )

        for uid: String? in [nil, "", " \n\t"] {
            let outputKey = PanelAudioDeviceID(id: 9, uid: uid)
            let inputKey = PanelAudioDeviceID(id: 11, uid: uid)
            actions.setOutputLevel(0.4, for: outputKey)
            actions.toggleOutputMute(for: outputKey)
            actions.finishOutputLevelAdjustment(for: outputKey)
            actions.setInputLevel(0.4, for: inputKey)
            actions.toggleInputMute(for: inputKey)
        }
        XCTAssertEqual(dispatchedCommands, 0)
    }

    func testOutputCommandsKeepExplicitDeviceAndNeverSelectOrUseGlobalControls() {
        var devices = [AudioOutputDevice(id: 7, name: "Current", uid: "a", isCurrent: true),
                       AudioOutputDevice(id: 9, name: "Other", uid: "b", isCurrent: false)]
        var writes: [(Double, String?)] = []
        var mutes: [String?] = []
        var flushes: [String?] = []
        var globalCalls = 0
        let actions = StatusPanelActions(
            outputDevices: { devices }, selectOutput: { _ in globalCalls += 1 },
            setVolume: { _ in globalCalls += 1 }, toggleMute: { globalCalls += 1 },
            setOutputLevel: { scalar, device in writes.append((scalar, device.uid)) },
            finishOutputLevelAdjustment: { device in flushes.append(device.uid) },
            toggleOutputMute: { device in mutes.append(device.uid) }
        )
        let key = PanelAudioDeviceID(id: 9, uid: "b")
        actions.setOutputLevel(2, for: key)
        actions.setOutputLevel(.nan, for: key)
        actions.toggleOutputMute(for: key)
        actions.finishOutputLevelAdjustment(for: key)
        devices = [AudioOutputDevice(id: 9, name: "Replacement", uid: "c", isCurrent: false)]
        actions.setOutputLevel(0.2, for: key)
        actions.toggleOutputMute(for: key)
        actions.finishOutputLevelAdjustment(for: key)
        XCTAssertEqual(writes.map(\.0), [1])
        XCTAssertEqual(writes.map(\.1), ["b"])
        XCTAssertEqual(mutes, ["b"])
        XCTAssertEqual(flushes, ["b"])
        XCTAssertEqual(globalCalls, 0)
    }

    func testInputCommandsKeepRequestAndDeviceIdentityWithoutChangingDefault() {
        var devices = [AudioInputDevice(id: 11, uid: "mic-b", name: "Other mic")]
        let request = UUID()
        var writes: [(Double, String?, UUID)] = []
        var mutes: [String?] = []
        var globalCalls = 0
        let actions = StatusPanelActions(
            inputDevices: { devices }, selectInput: { _ in globalCalls += 1 },
            setInputScalar: { _, _ in globalCalls += 1 }, toggleInputMute: { globalCalls += 1 },
            setInputLevel: { scalar, device, requestID in writes.append((scalar, device.uid, requestID)) },
            toggleInputDeviceMute: { device in mutes.append(device.uid) }
        )
        let key = PanelAudioDeviceID(id: 11, uid: "mic-b")
        actions.setInputLevel(-1, for: key, requestID: request)
        actions.setInputLevel(.infinity, for: key)
        actions.toggleInputMute(for: key)
        devices = []
        actions.setInputLevel(0.3, for: key)
        actions.toggleInputMute(for: key)
        XCTAssertEqual(writes.map(\.0), [0])
        XCTAssertEqual(writes.map(\.1), ["mic-b"])
        XCTAssertEqual(writes.map(\.2), [request])
        XCTAssertEqual(mutes, ["mic-b"])
        XCTAssertEqual(globalCalls, 0)
    }
}
