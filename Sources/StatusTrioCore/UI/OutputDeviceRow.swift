import SwiftUI

struct OutputDeviceRow: View {
    @EnvironmentObject private var localization: Localization
    let state: PanelAudioDeviceRow
    let onSelect: () -> Void
    let onSelectListeningMode: (BluetoothListeningMode) -> Void
    var scrollTargets: PopoverScrollTargets? = nil
    var onSetLevel: (Double, PanelAudioDeviceID, UUID) -> Void = { _, _, _ in }
    var onFinishLevel: (PanelAudioDeviceID) -> Void = { _ in }
    var onToggleMute: (PanelAudioDeviceID) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            AudioDeviceLevelRow(state: state, isInput: false,
                                sliderLabel: localization.string(.volumeAccessibilityLabel), scrollTargets: scrollTargets,
                                onSelect: onSelect, onSetLevel: onSetLevel,
                                onFinishLevel: onFinishLevel, onToggleMute: onToggleMute)

            if let listeningMode = state.listeningMode, listeningMode.isControllable {
                BluetoothListeningModeControl(
                    presentation: listeningMode,
                    onSelect: onSelectListeningMode
                )
                .padding(.leading, Self.modeLeadingInset)
            }
        }
    }

    private static let modeLeadingInset: CGFloat =
        BluetoothPanelMetrics.iconColumnWidth + BluetoothPanelMetrics.iconTextSpacing
}
