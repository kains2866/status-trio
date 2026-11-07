import Foundation

/// An edit belongs to a complete device identity, never to the selected route.
struct AudioDeviceLevelDraft {
    struct Submission {
        let key: PanelAudioDeviceID
        let scalar: Double
        let requestID: UUID
    }

    private(set) var value = 0.0
    private(set) var isEditing = false
    private let waitsForAcknowledgement: Bool
    private var identity: PanelAudioDeviceID?
    private var editingIdentity: PanelAudioDeviceID?
    private var systemScalar: Double?
    private var controlIdentity: VolumeControlInteractionIdentity?
    private var canAdjust = false
    private var pendingRequestID: UUID?
    private var nativeDeviceLevelReadbackRevision: UInt64 = 0
    private var pendingOutputReadback: (revision: UInt64, scalar: Double?)?

    init(waitsForAcknowledgement: Bool = false) {
        self.waitsForAcknowledgement = waitsForAcknowledgement
    }

    mutating func receive(key: PanelAudioDeviceID, scalar: Double?, canAdjust: Bool,
                          completedRequestID: UUID? = nil, hasError: Bool = false,
                          controlIdentity: VolumeControlInteractionIdentity? = nil,
                          nativeDeviceLevelReadbackRevision: UInt64 = 0) {
        let readable = scalar.flatMap { $0.isFinite && (0...1).contains($0) ? $0 : nil }
        let reset = identity != key || self.controlIdentity != controlIdentity || !canAdjust || readable == nil || hasError
        let resolvedOutputReadback = pendingOutputReadback.map {
            $0.revision != nativeDeviceLevelReadbackRevision || $0.scalar != readable
        } ?? false
        self.nativeDeviceLevelReadbackRevision = nativeDeviceLevelReadbackRevision
        self.controlIdentity = controlIdentity
        identity = key
        systemScalar = readable
        self.canAdjust = canAdjust && readable != nil
        if reset {
            isEditing = false
            editingIdentity = nil
            pendingRequestID = nil
            pendingOutputReadback = nil
        } else if pendingRequestID == completedRequestID {
            pendingRequestID = nil
        }
        if resolvedOutputReadback { pendingOutputReadback = nil }
        if !isEditing && pendingRequestID == nil && pendingOutputReadback == nil {
            value = readable ?? 0.5
        }
    }

    mutating func setEditing(_ editing: Bool, key: PanelAudioDeviceID) {
        if editing {
            guard identity == key, canAdjust else { return }
            isEditing = true
            editingIdentity = key
        } else {
            isEditing = false
            editingIdentity = nil
            if !waitsForAcknowledgement { pendingRequestID = nil }
            if pendingRequestID == nil && pendingOutputReadback == nil { value = systemScalar ?? 0.5 }
        }
    }

    mutating func change(_ scalar: Double, key: PanelAudioDeviceID) -> Submission? {
        guard isEditing, editingIdentity == key, identity == key, canAdjust, scalar.isFinite else { return nil }
        let clamped = min(1, max(0, scalar))
        guard abs(clamped - value) >= 0.0005 else { return nil }
        value = clamped
        let requestID = UUID()
        if waitsForAcknowledgement {
            pendingRequestID = requestID
        } else {
            // Mouseup can precede the monitor's debounced read. Keep this value
            // until a fresh native inventory or external scalar resolves it.
            pendingOutputReadback = (nativeDeviceLevelReadbackRevision, systemScalar)
        }
        return Submission(key: key, scalar: clamped, requestID: requestID)
    }
}
