import Combine
import Foundation
import SystemConfiguration

/// Tracks the system's power mode without starting or contacting the Helper.
@MainActor
final class HighPowerModeReadOnlyMonitor: ObservableObject {
    @Published private(set) var isHighPowerMode = false

    private let reader: @Sendable () -> HighPowerModeSystemStatus?
    private let observer: any NetworkChangeObserving
    private let observerQueue = DispatchQueue(label: "StatusTrio.HighPowerMode.observer")
    private let readQueue = DispatchQueue(label: "StatusTrio.HighPowerMode.read", qos: .utility)
    private let platformSupported: Bool
    private var running = false
    private var inFlight = false
    private var pending = false
    private var generation: UInt64 = 0

    init(
        reader: @escaping @Sendable () -> HighPowerModeSystemStatus? = { HighPowerModeSystemReader.read() },
        observer: any NetworkChangeObserving = HighPowerModeChangeObserver(),
        platformSupported: Bool = HighPowerModeController.supportsCurrentPlatform
    ) {
        self.reader = reader
        self.observer = observer
        self.platformSupported = platformSupported
    }

    func start() {
        guard !running, platformSupported else { return }
        running = true
        observer.start(queue: observerQueue) { [weak self] in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        guard running else { return }
        guard !inFlight else { pending = true; return }
        inFlight = true
        let requestGeneration = generation
        let reader = reader
        readQueue.async { [weak self] in
            let result = reader()
            Task { @MainActor [weak self] in
                guard let self, self.running, self.generation == requestGeneration else { return }
                self.inFlight = false
                if let result {
                    if !result.supported { self.isHighPowerMode = false }
                    else if let enabled = result.enabled { self.isHighPowerMode = enabled }
                }
                if self.pending {
                    self.pending = false
                    self.refresh()
                }
            }
        }
    }

    /// The Helper has confirmed a write; invalidate older reads before publishing it.
    func acceptWriteResult(_ enabled: Bool) {
        guard running else { return }
        generation &+= 1
        inFlight = false
        pending = false
        isHighPowerMode = enabled
        refresh()
    }

    func stop() {
        guard running else { return }
        running = false
        generation &+= 1
        inFlight = false
        pending = false
        observer.cancel()
    }
}

private final class HighPowerModeChangeObserver: @unchecked Sendable, NetworkChangeObserving {
    private let lock = NSLock()
    private var store: SCDynamicStore?
    private var handler: (@Sendable () -> Void)?

    func start(queue: DispatchQueue, handler: @escaping @Sendable () -> Void) {
        cancel()
        var context = SCDynamicStoreContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                            retain: nil, release: nil, copyDescription: nil)
        guard let store = SCDynamicStoreCreate(nil, "StatusTrio.HighPowerMode" as CFString,
                                              highPowerModeChanged, &context),
              SCDynamicStoreSetNotificationKeys(store, ["State:/IOKit/PowerManagement/CurrentSettings"] as CFArray, nil)
        else { return }
        lock.withLock { self.store = store; self.handler = handler }
        _ = SCDynamicStoreSetDispatchQueue(store, queue)
    }

    func cancel() {
        let store = lock.withLock { () -> SCDynamicStore? in
            let current = self.store
            self.store = nil
            self.handler = nil
            return current
        }
        if let store { _ = SCDynamicStoreSetDispatchQueue(store, nil) }
    }

    fileprivate func changed() { lock.withLock { handler }?() }
    deinit { cancel() }
}

private let highPowerModeChanged: SCDynamicStoreCallBack = { _, _, info in
    guard let info else { return }
    Unmanaged<HighPowerModeChangeObserver>.fromOpaque(info).takeUnretainedValue().changed()
}
