import Foundation

/// Opaque selected-device identity used only to detect an input switch.
/// It intentionally excludes UID, name, and presentation metadata.
struct PanelAudioInputIdentity: Equatable, Hashable, Sendable {
    private let value: UInt32

    init(rawValue: UInt32) {
        value = rawValue
    }
}

struct AudioInputListPreferences: Equatable, Sendable {
    let order: [String]
    let hiddenUIDs: Set<String>
    let visibleLimit: Int?

    init(order: [String] = [], hiddenUIDs: Set<String> = [], visibleLimit: Int? = 3) {
        self.order = order
        self.hiddenUIDs = hiddenUIDs
        self.visibleLimit = visibleLimit.map { max(0, $0) }
    }

    static let `default` = Self()
}

struct AudioInputPanelState: Equatable, Sendable {
    let summary: PanelSummaryState
    let selectedDeviceIdentity: PanelAudioInputIdentity?
    let scalar: Double?
    let percentageText: String
    let muteSymbol: String
    let muteTint: PanelTint
    let muteHelp: String
    let muteState: AudioInputMuteState?
    let canAdjust: Bool
    let canMute: Bool
    /// A blocking command that should disable controls and show progress.
    let isBusy: Bool
    let errorText: String?
    let showsDeviceList: Bool
    /// Complete rows stay resolved in display order. The view owns only whether
    /// its local disclosure is expanded.
    let rows: [PanelAudioDeviceRow]
    let visibleLimit: Int?
    let expandLabel: String
    let collapseLabel: String
    let sliderLabel: String
    let usageText: String?
    let completedScalarRequestID: UUID?

    var hasHiddenRows: Bool {
        !overflowRows.isEmpty
    }

    var overflowRows: [PanelAudioDeviceRow] {
        Array(rows.dropFirst(visibleRows(expanded: false).count))
    }

    func visibleRows(expanded: Bool) -> [PanelAudioDeviceRow] {
        guard !expanded, let visibleLimit else { return rows }
        return Array(rows.prefix(max(0, visibleLimit)))
    }
}
