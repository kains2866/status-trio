import XCTest
@testable import StatusTrioCore

@MainActor
final class ApplicationAudioAppIdentityTests: XCTestCase {
    private let browser = URL(fileURLWithPath: "/Applications/Google Chrome.app")
    private let helper = URL(fileURLWithPath: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/157.0.8103.52/Helpers/Google Chrome Helper (Aperitif).app/Contents/MacOS/Google Chrome Helper (Aperitif)")

    func testNestedHelperUsesVerifiedOutermostRunningAppAndDistinctProcessIdentity() {
        let identity = ApplicationAudioAppIdentity.resolve(
            process: .init(pid: 20, executableURL: helper, instanceID: "20:second"),
            owners: [.init(pid: 10, bundleURL: browser, bundleID: "com.google.Chrome", name: "Google Chrome")],
            evidence: { _ in .init(pid: 10, executableURL: self.browser.appendingPathComponent("Contents/MacOS/Google Chrome"), instanceID: "10:first") },
            bundleID: { $0 == self.browser ? "com.google.Chrome" : nil }
        )
        XCTAssertEqual(identity?.name, "Google Chrome")
        XCTAssertEqual(identity?.bundleID, "com.google.Chrome")
        XCTAssertEqual(identity?.appURL, browser)
        XCTAssertEqual(identity?.instanceID, "20:second")
        XCTAssertEqual(identity?.ownerInstanceID, "10:first")
    }

    func testBundleIDAloneCannotClaimAnUnrelatedRunningOwner() {
        let identity = ApplicationAudioAppIdentity.resolve(
            process: .init(pid: 20, executableURL: helper, instanceID: "20:second"),
            owners: [.init(pid: 10, bundleURL: URL(fileURLWithPath: "/tmp/Google Chrome.app"), bundleID: "com.google.Chrome", name: "Google Chrome")],
            evidence: { _ in nil }, bundleID: { _ in "com.google.Chrome" }
        )
        XCTAssertNil(identity)
    }

    func testAmbiguousMultipleOwnersAndMissingProcessEvidenceRemainReadOnly() {
        let owners = [10, 11].map {
            ApplicationAudioRunningAppEvidence(pid: Int32($0), bundleURL: browser, bundleID: "com.google.Chrome", name: "Google Chrome")
        }
        let identity = ApplicationAudioAppIdentity.resolve(
            process: .init(pid: 20, executableURL: helper, instanceID: "20:second"), owners: owners,
            evidence: { _ in nil }, bundleID: { _ in "com.google.Chrome" }
        )
        XCTAssertNil(identity)
    }

    func testExecutableOutsideAnApplicationBundleDoesNotAcquireABundleIdentity() {
        let identity = ApplicationAudioAppIdentity.resolve(
            process: .init(pid: 20, executableURL: URL(fileURLWithPath: "/usr/bin/tool"), instanceID: "20:second"), owners: [],
            evidence: { _ in nil }, bundleID: { _ in "com.google.Chrome" }
        )
        XCTAssertNil(identity)
    }
}
