import XCTest
@testable import StatusTrioCore

@MainActor
final class HighPowerModeReadOnlyMonitorTests: XCTestCase {
    func testReadOnlyRefreshKeepsLastValueWhenReadFails() async {
        let source = HighPowerReadSource()
        let observer = HighPowerTestObserver()
        let monitor = HighPowerModeReadOnlyMonitor(reader: { source.read() }, observer: observer, platformSupported: true)
        monitor.start()
        await waitUntil { monitor.isHighPowerMode }
        XCTAssertTrue(monitor.isHighPowerMode)

        source.set(nil)
        observer.fire()
        await waitUntil { source.count >= 2 }
        // Let the completion return to the main actor.
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(monitor.isHighPowerMode)

        source.set(HighPowerModeSystemStatus(supported: true, enabled: false))
        observer.fire()
        await waitUntil { !monitor.isHighPowerMode }
        XCTAssertFalse(monitor.isHighPowerMode)
        monitor.stop()
        XCTAssertTrue(observer.cancelled)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class HighPowerReadSource: @unchecked Sendable {
    private let lock = NSLock()
    private var value: HighPowerModeSystemStatus? = .init(supported: true, enabled: true)
    private var reads = 0
    var count: Int { lock.withLock { reads } }
    func set(_ value: HighPowerModeSystemStatus?) { lock.withLock { self.value = value } }
    func read() -> HighPowerModeSystemStatus? { lock.withLock { reads += 1; return value } }
}

private final class HighPowerTestObserver: @unchecked Sendable, NetworkChangeObserving {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private var didCancel = false
    var cancelled: Bool { lock.withLock { didCancel } }
    func start(queue: DispatchQueue, handler: @escaping @Sendable () -> Void) {
        lock.withLock { self.handler = handler }
    }
    func cancel() { lock.withLock { didCancel = true; handler = nil } }
    func fire() { lock.withLock { handler }?() }
}
