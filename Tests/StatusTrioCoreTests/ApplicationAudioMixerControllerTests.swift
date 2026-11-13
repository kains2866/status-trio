import CoreAudio
import XCTest
@testable import StatusTrioCore

@MainActor
final class ApplicationAudioMixerControllerTests: XCTestCase {
    func testHoverAndEnableNeverStartCaptureAndIdleCloseStopsDiscovery() {
        let discovery = MixerDiscoveryFake()
        let session = MixerSessionFake()
        let controller = makeController(discovery, session)
        controller.setPanelVisible(true)
        discovery.send([process(1)])
        XCTAssertEqual(controller.rows.count, 1)
        XCTAssertFalse(controller.rows[0].canAdjust)
        controller.enable()
        XCTAssertTrue(controller.rows[0].canAdjust)
        XCTAssertEqual(session.starts.count, 0)
        controller.setPanelVisible(false)
        XCTAssertFalse(discovery.isRunning)
        XCTAssertEqual(session.starts.count, 0)
    }

    func testAdjustedGainContinuesWhenClosedAndRestoringUnityTearsDown() {
        let discovery = MixerDiscoveryFake()
        let session = MixerSessionFake()
        let controller = makeController(discovery, session)
        controller.setPanelVisible(true)
        discovery.send([process(1)])
        controller.enable()
        let id = controller.rows[0].id
        controller.setGain(0.4, for: id)
        controller.setPanelVisible(false)
        XCTAssertTrue(discovery.isRunning)
        XCTAssertEqual(session.starts.first?.processIDs, [1])
        XCTAssertEqual(session.starts.first?.uid, "speaker")
        XCTAssertEqual(session.starts.first?.gain, 0.4)
        XCTAssertEqual(controller.rows.first?.gain, 0.4)
        controller.setGain(1, for: id)
        XCTAssertEqual(session.stopCount, 1)
        XCTAssertFalse(discovery.isRunning)
    }

    func testMutePreservesGainAndUnmuteRestoresItWithoutRestartingSession() {
        let discovery = MixerDiscoveryFake()
        let session = MixerSessionFake()
        let controller = makeController(discovery, session)
        controller.setPanelVisible(true)
        discovery.send([process(1)])
        controller.enable()
        let id = controller.rows[0].id
        controller.setGain(0.5, for: id)
        controller.toggleMute(for: id)
        XCTAssertTrue(controller.rows[0].isMuted)
        XCTAssertEqual(controller.rows[0].gain, 0.5)
        XCTAssertEqual(session.gains.last, 0)
        controller.toggleMute(for: id)
        XCTAssertEqual(session.gains.last, 0.5)
        XCTAssertEqual(session.starts.count, 1)
        controller.stop()
    }

    func testRouteChangeProcessReplacementAndDisappearanceReleaseInterception() {
        for replacement in [
            [process(1, pid: 20)],
            [process(1, uid: "headphones")],
            [process(2, pid: 20)],
            []
        ] {
            let discovery = MixerDiscoveryFake()
            let session = MixerSessionFake()
            let controller = makeController(discovery, session)
            controller.setPanelVisible(true)
            discovery.send([process(1)])
            controller.enable()
            controller.setGain(0.2, for: controller.rows[0].id)
            discovery.send(replacement)
            XCTAssertEqual(session.stopCount, 1)
            XCTAssertTrue(controller.rows.allSatisfy { $0.gain == 1 && !$0.isMuted })
            controller.stop()
        }
    }

    func testPIDReuseOfSameAudioObjectWithDifferentLaunchIdentityReleasesSession() {
        let discovery = MixerDiscoveryFake()
        let session = MixerSessionFake()
        var launch = "first"
        let controller = ApplicationAudioMixerController(
            discovery: discovery, isSupported: true,
            resolveIdentity: { pid in
                ApplicationAudioAppIdentity(name: "Browser", bundleID: "browser", appURL: URL(fileURLWithPath: "/Applications/Browser.app"), instanceID: "\(pid):\(launch)")
            }, makeSession: { session }
        )
        controller.setPanelVisible(true)
        discovery.send([process(1)])
        controller.enable()
        controller.setGain(0.4, for: controller.rows[0].id)
        launch = "second"
        discovery.send([process(1)])
        XCTAssertEqual(session.stopCount, 1)
        XCTAssertEqual(controller.rows[0].gain, 1)
        controller.stop()
    }

    func testGroupedHelpersUseAllOutputProcessesButNeverInputOnlyProcesses() {
        let discovery = MixerDiscoveryFake()
        let session = MixerSessionFake()
        let controller = makeController(discovery, session)
        controller.setPanelVisible(true)
        discovery.send([process(8, input: true, output: false), process(3), process(1)])
        controller.enable()
        XCTAssertEqual(controller.rows.count, 2)
        let output = controller.rows.first { !$0.isInput }!
        let input = controller.rows.first { $0.isInput }!
        XCTAssertEqual(output.processIDs, [1, 3])
        XCTAssertEqual(input.processIDs, [8])
        XCTAssertFalse(input.canAdjust)
        controller.setGain(0.2, for: input.id)
        controller.toggleMute(for: input.id)
        XCTAssertTrue(session.starts.isEmpty)
        controller.setGain(0.3, for: output.id)
        XCTAssertEqual(session.starts.first?.processIDs, [1, 3])
        controller.stop()
    }

    func testAmbiguousAndMissingRoutesCannotCreateCaptureSessions() {
        let discovery = MixerDiscoveryFake()
        let session = MixerSessionFake()
        let controller = makeController(discovery, session)
        controller.setPanelVisible(true)
        discovery.send([process(1), process(2, uid: "other")])
        controller.enable()
        XCTAssertFalse(controller.rows[0].canAdjust)
        XCTAssertNil(controller.rows[0].outputDeviceUID)
        controller.setGain(0.3, for: controller.rows[0].id)
        XCTAssertTrue(session.starts.isEmpty)
        discovery.send([process(1, uid: nil)])
        XCTAssertFalse(controller.rows[0].canAdjust)
        controller.stop()
    }

    func testCaptureFailureRestoresNativePlaybackAndRequiresExplicitReenable() {
        let discovery = MixerDiscoveryFake()
        let session = MixerSessionFake()
        session.shouldFail = true
        let controller = makeController(discovery, session)
        controller.setPanelVisible(true)
        discovery.send([process(1)])
        controller.enable()
        controller.setGain(0.4, for: controller.rows[0].id)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertEqual(session.stopCount, 1)
        XCTAssertEqual(controller.rows[0].gain, 1)
        XCTAssertFalse(controller.rows[0].canAdjust)
        controller.stop()
    }

    func testDiscoveryFailureStopsAllSessionsAndResetClearsOptIn() {
        let discovery = MixerDiscoveryFake()
        let session = MixerSessionFake()
        let controller = makeController(discovery, session)
        controller.setPanelVisible(true)
        discovery.send([process(1)])
        controller.enable()
        controller.setGain(0.4, for: controller.rows[0].id)
        discovery.fail()
        XCTAssertEqual(session.stopCount, 1)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertTrue(controller.rows.isEmpty)
        controller.reset()
        XCTAssertFalse(controller.isEnabled)
        XCTAssertNil(controller.errorMessage)
        controller.stop()
    }

    func testUnsupportedSystemDoesNotDiscoverOrEnable() {
        let discovery = MixerDiscoveryFake()
        let session = MixerSessionFake()
        let controller = ApplicationAudioMixerController(discovery: discovery, isSupported: false, resolveIdentity: { _ in nil }, makeSession: { session })
        controller.setPanelVisible(true)
        controller.enable()
        XCTAssertFalse(discovery.isRunning)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertTrue(controller.rows.isEmpty)
    }

    func testPauseStopsInterceptionButResumeRestoresGainForSameProcessInstance() {
        let discovery = MixerDiscoveryFake()
        let session = MixerSessionFake()
        let controller = makeController(discovery, session)
        controller.setPanelVisible(true)
        discovery.send([process(1)])
        controller.enable()
        controller.setGain(0.25, for: controller.rows[0].id)
        controller.setPanelVisible(false)
        discovery.send([process(1, output: false)])
        XCTAssertTrue(controller.rows.isEmpty)
        XCTAssertEqual(session.stopCount, 1)
        XCTAssertTrue(discovery.isRunning)
        discovery.send([process(1)])
        XCTAssertEqual(controller.rows.first?.gain, 0.25)
        XCTAssertEqual(session.starts.count, 2)
        XCTAssertEqual(session.starts.last?.gain, 0.25)
        controller.stop()
    }

    func testRouteFormatChangeResetsPreferenceAndStopsSession() {
        let discovery = MixerDiscoveryFake()
        let session = MixerSessionFake()
        let controller = makeController(discovery, session)
        controller.setPanelVisible(true)
        discovery.send([process(1)])
        controller.enable()
        controller.setGain(0.25, for: controller.rows[0].id)
        discovery.send([ApplicationAudioProcessSnapshot(objectID: 1, pid: 10, bundleID: "browser", isRunningInput: false, isRunningOutput: true, inputDevices: [], outputDevices: [.init(id: 100, uid: "speaker", name: "Speaker", routeFingerprint: "96000:stereo")], outputRouteIsComplete: true)])
        XCTAssertEqual(session.stopCount, 1)
        XCTAssertEqual(controller.rows.first?.gain, 1)
        controller.stop()
    }

    func testFailureStartingAnotherAppPreservesHealthyAppGain() {
        let discovery = MixerDiscoveryFake()
        let healthy = MixerSessionFake()
        let failing = MixerSessionFake()
        failing.shouldFail = true
        var made = 0
        let controller = ApplicationAudioMixerController(discovery: discovery, isSupported: true, resolveIdentity: { pid in
            ApplicationAudioAppIdentity(name: "App \(pid)", bundleID: "app.\(pid)", appURL: URL(fileURLWithPath: "/Applications/App\(pid).app"), instanceID: "\(pid):launch")
        }, makeSession: { made += 1; return made == 1 ? healthy : failing })
        controller.setPanelVisible(true)
        discovery.send([process(1, pid: 10), process(2, pid: 20)])
        controller.enable()
        let first = controller.rows.first { $0.name == "App 10" }!.id
        let second = controller.rows.first { $0.name == "App 20" }!.id
        controller.setGain(0.4, for: first)
        controller.setGain(0.3, for: second)
        XCTAssertTrue(controller.isEnabled)
        XCTAssertEqual(healthy.stopCount, 0)
        XCTAssertEqual(controller.rows.first { $0.id == first }?.gain, 0.4)
        XCTAssertEqual(failing.stopCount, 1)
        XCTAssertNotNil(controller.errorMessage)
        controller.stop()
    }

    func testHelperMembershipChangeRestartsCaptureWithSavedAppGain() {
        let discovery = MixerDiscoveryFake()
        let sessions = [MixerSessionFake(), MixerSessionFake()]
        var made = 0
        let controller = ApplicationAudioMixerController(discovery: discovery, isSupported: true, resolveIdentity: { pid in
            ApplicationAudioAppIdentity(name: "Browser", bundleID: "browser", appURL: URL(fileURLWithPath: "/Applications/Browser.app"), instanceID: "helper:\(pid)", ownerInstanceID: "browser-main:launch")
        }, makeSession: { let session = sessions[made]; made += 1; return session })
        controller.setPanelVisible(true)
        discovery.send([process(1, pid: 10), process(2, pid: 20)])
        controller.enable()
        controller.setGain(0.25, for: controller.rows[0].id)
        discovery.send([process(1, pid: 10, output: false), process(2, pid: 20)])
        XCTAssertEqual(sessions[0].stopCount, 1)
        XCTAssertEqual(sessions[1].starts.first?.processIDs, [2])
        XCTAssertEqual(sessions[1].starts.first?.gain, 0.25)
        XCTAssertEqual(controller.rows.first?.gain, 0.25)
        controller.stop()
    }

    func testFailedCleanupRetainsEngineAndBlocksNewCaptureUntilExplicitResetSucceeds() {
        let discovery = MixerDiscoveryFake()
        let session = MixerSessionFake()
        let controller = makeController(discovery, session)
        controller.setPanelVisible(true)
        discovery.send([process(1)])
        controller.enable()
        let id = controller.rows[0].id
        controller.setGain(0.25, for: id)
        session.cleanupErrors = [-1]
        controller.setGain(1, for: id)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertFalse(controller.rows[0].canAdjust)
        controller.setGain(0.5, for: id)
        XCTAssertEqual(session.starts.count, 1)
        controller.reset()
        XCTAssertNotNil(controller.errorMessage)
        session.cleanupErrors = []
        controller.reset()
        XCTAssertNil(controller.errorMessage)
        controller.enable()
        XCTAssertTrue(controller.rows[0].canAdjust)
        controller.setGain(0.5, for: id)
        XCTAssertEqual(session.starts.count, 2)
        controller.stop()
    }

    func testDisconnectedHALClientPreservesGainWhileOwnerLivesAndResumesNewProcessObject() {
        let discovery = MixerDiscoveryFake()
        let session = MixerSessionFake()
        var ownerAlive = true
        let controller = ApplicationAudioMixerController(
            discovery: discovery, isSupported: true,
            resolveIdentity: { pid in
                ApplicationAudioAppIdentity(name: "Browser", bundleID: "browser", appURL: URL(fileURLWithPath: "/Applications/Browser.app"), instanceID: "\(pid):launch", ownerInstanceID: "10:main-launch")
            }, isOwnerAlive: { $0 == "10:main-launch" && ownerAlive }, makeSession: { session }
        )
        controller.setPanelVisible(true)
        discovery.send([process(1)])
        controller.enable()
        controller.setGain(0.25, for: controller.rows[0].id)
        controller.setPanelVisible(false)
        discovery.send([])
        XCTAssertTrue(controller.rows.isEmpty)
        XCTAssertEqual(session.stopCount, 1)
        XCTAssertTrue(discovery.isRunning)
        discovery.send([process(2, pid: 20)])
        XCTAssertEqual(controller.rows.first?.gain, 0.25)
        XCTAssertEqual(session.starts.last?.processIDs, [2])
        XCTAssertEqual(session.starts.last?.gain, 0.25)
        ownerAlive = false
        discovery.send([])
        XCTAssertFalse(discovery.isRunning)
        XCTAssertEqual(session.stopCount, 2)
        controller.stop()
    }

    private func makeController(_ discovery: MixerDiscoveryFake, _ session: MixerSessionFake) -> ApplicationAudioMixerController {
        ApplicationAudioMixerController(discovery: discovery, isSupported: true, resolveIdentity: { pid in
            ApplicationAudioAppIdentity(name: "Browser", bundleID: "browser", appURL: URL(fileURLWithPath: "/Applications/Browser.app"), instanceID: "\(pid):launch")
        }, makeSession: { session })
    }

    private func process(_ id: AudioObjectID, pid: Int32 = 10, uid: String? = "speaker", input: Bool = false, output: Bool = true) -> ApplicationAudioProcessSnapshot {
        Self.process(id, pid: pid, uid: uid, input: input, output: output)
    }

    private static func process(_ id: AudioObjectID, pid: Int32 = 10, uid: String? = "speaker", input: Bool = false, output: Bool = true) -> ApplicationAudioProcessSnapshot {
        ApplicationAudioProcessSnapshot(objectID: id, pid: pid, bundleID: "browser", isRunningInput: input, isRunningOutput: output, inputDevices: input ? [.init(id: 90, uid: "mic", name: "Microphone")] : [], outputDevices: uid.map { [.init(id: 100, uid: $0, name: "Speaker")] } ?? [], outputRouteIsComplete: uid != nil)
    }
}

@MainActor
private final class MixerDiscoveryFake: ApplicationAudioProcessDiscovering {
    var isRunning = false
    var receive: (@MainActor @Sendable (Result<[ApplicationAudioProcessSnapshot], Error>) -> Void)?
    func start(_ receive: @escaping @MainActor @Sendable (Result<[ApplicationAudioProcessSnapshot], Error>) -> Void) {
        self.receive = receive
        isRunning = true
    }
    func stop() { isRunning = false; receive = nil }
    func send(_ snapshots: [ApplicationAudioProcessSnapshot]) { receive?(.success(snapshots)) }
    func fail() { receive?(.failure(NSError(domain: "Discovery", code: 1))) }
}

@MainActor
private final class MixerSessionFake: ApplicationAudioSessionControlling {
    struct Start { let processIDs: [AudioObjectID]; let uid: String; let gain: Float }
    var starts: [Start] = []
    var gains: [Float] = []
    var stopCount = 0
    var shouldFail = false
    var cleanupErrors: [OSStatus] = []
    var hasUnreleasedResources: Bool { !cleanupErrors.isEmpty }
    func start(processIDs: [AudioObjectID], outputDeviceUID: String, gain: Float) throws {
        starts.append(Start(processIDs: processIDs, uid: outputDeviceUID, gain: gain))
        if shouldFail { throw NSError(domain: "Permission", code: 1) }
    }
    func setGain(_ gain: Float) { gains.append(gain) }
    func stop() { stopCount += 1 }
}
