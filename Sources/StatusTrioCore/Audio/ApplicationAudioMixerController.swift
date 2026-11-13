import Combine
import CoreAudio
import Foundation

/// Demand owns discovery; only explicit gain/mute actions create a capture session.
@MainActor
final class ApplicationAudioMixerController: ObservableObject {
    @Published private(set) var rows: [ApplicationAudioMixerRow] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isEnabled = false
    let isSupported: Bool

    private struct ActiveSession {
        let engine: any ApplicationAudioSessionControlling
        let fingerprint: [String]
        let deviceUID: String
    }
    private struct SavedAdjustment {
        let gain: Double
        let muted: Bool
        let ownerInstanceID: String
        let routeFingerprint: [String]
    }
    private let discovery: any ApplicationAudioProcessDiscovering
    private let resolveIdentity: (Int32) -> ApplicationAudioAppIdentity?
    private let makeSession: () -> any ApplicationAudioSessionControlling
    private let isOwnerAlive: (String) -> Bool
    private var sessions: [String: ActiveSession] = [:]
    // One failed owner per app row; that row cannot start again until explicit cleanup succeeds.
    private var retiredSessions: [String: any ApplicationAudioSessionControlling] = [:]
    private var adjustments: [String: SavedAdjustment] = [:]
    private var snapshots: [ApplicationAudioProcessSnapshot] = []
    private var isPanelVisible = false
    private var isDiscovering = false
    private var observationGeneration = UUID()

    convenience init() {
        let supported: Bool
        if #available(macOS 14.2, *) { supported = true } else { supported = false }
        self.init(discovery: CoreAudioApplicationProcessDiscovery(), isSupported: supported,
                  resolveIdentity: { ApplicationAudioAppIdentity.resolve(pid: $0) },
                  isOwnerAlive: { ApplicationAudioProcessIdentityEvidence.isAlive(instanceID: $0) }, makeSession: {
            if #available(macOS 14.2, *) { return CoreAudioApplicationAudioSession() }
            return UnavailableApplicationAudioSession()
        })
    }

    init(discovery: any ApplicationAudioProcessDiscovering, isSupported: Bool,
         resolveIdentity: @escaping (Int32) -> ApplicationAudioAppIdentity?,
         isOwnerAlive: @escaping (String) -> Bool = { _ in false },
         makeSession: @escaping () -> any ApplicationAudioSessionControlling) {
        self.discovery = discovery
        self.isSupported = isSupported
        self.resolveIdentity = resolveIdentity
        self.makeSession = makeSession
        self.isOwnerAlive = isOwnerAlive
    }

    func setPanelVisible(_ visible: Bool) {
        isPanelVisible = visible
        updateDiscoveryDemand()
    }

    func enable() {
        guard isSupported else { return }
        // This explicit feature opt-in opens no tap. macOS authorization occurs on actual adjustment.
        isEnabled = true
        if retiredSessions.isEmpty { errorMessage = nil }
        reconcileRows()
    }

    func setGain(_ scalar: Double, for rowID: String) {
        guard scalar.isFinite, (0...1).contains(scalar),
              let row = rows.first(where: { $0.id == rowID }), row.canAdjust else { return }
        apply(gain: scalar, muted: row.isMuted, to: row)
    }

    func toggleMute(for rowID: String) {
        guard let row = rows.first(where: { $0.id == rowID }), row.canAdjust else { return }
        apply(gain: row.gain, muted: !row.isMuted, to: row)
    }

    func reset() {
        errorMessage = nil
        adjustments = [:]
        isEnabled = false
        // Retry only owners already retired before this explicit action, not newly failed stops.
        let previouslyRetired = retiredSessions
        stopSessions()
        for (id, engine) in previouslyRetired { stopEngine(engine, for: id) }
        reconcileRows()
        updateDiscoveryDemand()
    }

    func stop() {
        isPanelVisible = false
        reset()
        snapshots = []
        rows = []
    }

    private func apply(gain: Double, muted: Bool, to row: ApplicationAudioMixerRow) {
        guard !row.isInput, isEnabled, row.canAdjust, retiredSessions[row.id] == nil,
              let uid = row.outputDeviceUID, let owner = row.ownerInstanceID else { return }
        if gain == 1 && !muted {
            adjustments.removeValue(forKey: row.id)
            stopSession(for: row.id)
        } else if let active = sessions[row.id] {
            active.engine.setGain(muted ? 0 : Float(gain))
        } else {
            let engine = makeSession()
            do {
                try engine.start(processIDs: row.processIDs, outputDeviceUID: uid, gain: muted ? 0 : Float(gain))
                sessions[row.id] = ActiveSession(engine: engine, fingerprint: row.instanceFingerprint, deviceUID: uid)
            } catch {
                errorMessage = error.localizedDescription
                stopEngine(engine, for: row.id)
                adjustments.removeValue(forKey: row.id)
                // Other applications already have independent, healthy sessions.
                if sessions.isEmpty && adjustments.isEmpty { isEnabled = false }
                reconcileRows()
                updateDiscoveryDemand()
                return
            }
        }
        if gain != 1 || muted {
            adjustments[row.id] = SavedAdjustment(gain: gain, muted: muted, ownerInstanceID: owner,
                                                   routeFingerprint: row.routeFingerprint)
        }
        rows = rows.map { $0.id == row.id
            ? $0.with(gain: gain, isMuted: muted, canAdjust: $0.canAdjust && retiredSessions[row.id] == nil) : $0 }
        updateDiscoveryDemand()
    }

    private func reconcileRows() {
        // Resolve once per snapshot, including inactive clients: pause differs from process exit.
        var identities: [Int32: ApplicationAudioAppIdentity] = [:]
        for process in snapshots { identities[process.pid] = resolveIdentity(process.pid) }
        let liveOwners = Set(identities.values.map(\.ownerInstanceID))
        adjustments = adjustments.filter { _, saved in
            liveOwners.contains(saved.ownerInstanceID) || isOwnerAlive(saved.ownerInstanceID)
        }
        let fresh = ApplicationAudioMixerRows.make(snapshots, enabled: isEnabled, resolve: { identities[$0] })
        for row in fresh {
            if let saved = adjustments[row.id],
               row.ownerInstanceID != saved.ownerInstanceID || row.routeFingerprint != saved.routeFingerprint {
                // Explicit adjustments never move silently to another app instance, route or format.
                adjustments.removeValue(forKey: row.id)
            }
        }
        let validIDs = Set(fresh.filter { row in
            guard let session = sessions[row.id] else { return false }
            return row.canAdjust && adjustments[row.id] != nil
                && row.instanceFingerprint == session.fingerprint && row.outputDeviceUID == session.deviceUID
        }.map(\.id))
        for id in Array(sessions.keys) where !validIDs.contains(id) { stopSession(for: id) }
        rows = fresh.map { row in
            let saved = adjustments[row.id]
            return row.with(gain: saved?.gain ?? 1, isMuted: saved?.muted ?? false,
                            canAdjust: row.canAdjust && retiredSessions[row.id] == nil)
        }
        // Helpers may join/leave while the verified owner app and route remain the same.
        // Rebuild interception with the saved gain, so helper changes cannot cause a loud reset.
        for row in rows where row.canAdjust && adjustments[row.id] != nil && sessions[row.id] == nil {
            apply(gain: row.gain, muted: row.isMuted, to: row)
        }
    }

    private func updateDiscoveryDemand() {
        let needed = isSupported && (isPanelVisible || !sessions.isEmpty || !adjustments.isEmpty)
        guard needed != isDiscovering else { return }
        isDiscovering = needed
        observationGeneration = UUID()
        if needed {
            let generation = observationGeneration
            discovery.start { [weak self] result in
                guard let self, self.isDiscovering, self.observationGeneration == generation else { return }
                switch result {
                case .success(let processes):
                    self.snapshots = processes
                    self.reconcileRows()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.stopSessions()
                    self.adjustments = [:]
                    self.snapshots = []
                    self.rows = []
                    self.isEnabled = false
                }
                self.updateDiscoveryDemand()
            }
        } else {
            discovery.stop()
        }
    }

    private func stopSession(for id: String) {
        guard let session = sessions[id] else { return }
        stopEngine(session.engine, for: id)
        sessions.removeValue(forKey: id)
    }

    private func stopEngine(_ engine: any ApplicationAudioSessionControlling, for id: String) {
        engine.stop()
        if !engine.cleanupErrors.isEmpty {
            let details = engine.cleanupErrors.map { String($0) }.joined(separator: ", ")
            errorMessage = "CoreAudio cleanup (\(details))"
        }
        if engine.hasUnreleasedResources {
            // Retain before dropping the active owner. Native playback restoration is unconfirmed.
            retiredSessions[id] = engine
        } else {
            retiredSessions.removeValue(forKey: id)
        }
    }

    private func stopSessions() {
        for id in Array(sessions.keys) { stopSession(for: id) }
    }
}

@available(macOS 14.2, *)
extension CoreAudioApplicationAudioSession: ApplicationAudioSessionControlling {}

@MainActor
private final class UnavailableApplicationAudioSession: ApplicationAudioSessionControlling {
    func start(processIDs: [AudioObjectID], outputDeviceUID: String, gain: Float) throws {
        throw CocoaError(.featureUnsupported)
    }
    func setGain(_ gain: Float) {}
    func stop() {}
}
