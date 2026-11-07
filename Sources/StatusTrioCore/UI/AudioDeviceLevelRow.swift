import SwiftUI

struct AudioDeviceLevelRow: View {
    @EnvironmentObject private var localization: Localization
    let state: PanelAudioDeviceRow
    let isInput: Bool
    let sliderLabel: String
    let hasError: Bool
    let scrollTargets: PopoverScrollTargets?
    let onSelect: () -> Void
    let onSetLevel: (Double, PanelAudioDeviceID, UUID) -> Void
    let onFinishLevel: (PanelAudioDeviceID) -> Void
    let onToggleMute: (PanelAudioDeviceID) -> Void

    @State private var draft: AudioDeviceLevelDraft
    @State private var gestureControlIdentity: VolumeControlInteractionIdentity?
    @State private var gestureKey: PanelAudioDeviceID?

    init(state: PanelAudioDeviceRow, isInput: Bool, sliderLabel: String, hasError: Bool = false, scrollTargets: PopoverScrollTargets? = nil,
         onSelect: @escaping () -> Void,
         onSetLevel: @escaping (Double, PanelAudioDeviceID, UUID) -> Void,
         onFinishLevel: @escaping (PanelAudioDeviceID) -> Void = { _ in },
         onToggleMute: @escaping (PanelAudioDeviceID) -> Void) {
        self.state = state
        self.isInput = isInput
        self.sliderLabel = sliderLabel
        self.hasError = hasError
        self.scrollTargets = scrollTargets
        self.onSelect = onSelect
        self.onSetLevel = onSetLevel
        self.onFinishLevel = onFinishLevel
        self.onToggleMute = onToggleMute
        var initialDraft = AudioDeviceLevelDraft(waitsForAcknowledgement: isInput)
        let level = state.level ?? .unavailable
        initialDraft.receive(key: state.key, scalar: level.scalar, canAdjust: state.key.hasStableUID && state.enabled && level.canAdjust,
                             completedRequestID: state.completedLevelRequestID, hasError: hasError,
                             controlIdentity: state.interactionIdentity,
                      nativeDeviceLevelReadbackRevision: state.nativeDeviceLevelReadbackRevision)
        _draft = State(initialValue: initialDraft)
    }

    private var level: AudioDeviceLevel {
        let snapshot = state.level ?? .unavailable
        return AudioDeviceLevel(scalar: snapshot.scalar,
                                canAdjust: state.key.hasStableUID && snapshot.canAdjust,
                                muteState: snapshot.muteState,
                                canMute: state.key.hasStableUID && snapshot.canMute)
    }
    private var percentage: String {
        guard level.scalar != nil else { return "—" }
        return draft.value.formatted(.percent.precision(.fractionLength(0)).locale(localization.resolvedLanguage.locale))
    }
    private var muteHelp: String {
        if isInput {
            return localization.string(level.canMute ? (level.muteState == .muted ? .audioInputUnmute : .audioInputMute) : .audioInputMuteUnavailable)
        }
        return localization.string(level.canMute ? (level.muteState == .muted ? .volumeUnmuted : .volumeMuted) : .volumeMuteUnavailable)
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                guard !state.selected, !state.isPreview else { return }
                onSelect()
            } label: {
                ZStack {
                    Circle().fill(state.selected ? Color.accentColor : Color.secondary.opacity(0.14))
                    AudioOutputDeviceIconView(source: state.symbol)
                        .foregroundStyle(state.selected ? Color.white : Color.secondary)
                }
                .frame(width: 24, height: 24)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!state.enabled || state.isPreview)
            .help(state.helpText)
            .accessibilityLabel(state.accessibilityLabel)
            .accessibilityValue(state.selected ? localization.string(isInput ? .audioInputCurrent : .volumeOutputCurrent) : "")

            Text(state.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 72, alignment: .leading)
                .help(state.name)

            Button {
                guard !state.isPreview, state.key.hasStableUID else { return }
                onToggleMute(state.key)
            } label: {
                Image(systemName: isInput
                      ? (level.muteState == .muted ? "mic.slash.fill" : "mic.fill")
                      : (level.muteState == .muted ? "speaker.slash.fill" : "speaker.wave.2.fill"))
                    .font(.system(size: 12))
                    .foregroundStyle(level.muteState == .muted ? Color.red : Color.secondary)
                    .frame(width: 18, height: 24)
                    .overlay(alignment: .topTrailing) {
                        if level.muteState == .partial {
                            Image(systemName: "minus.circle.fill").font(.system(size: 7))
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!state.enabled || !level.canMute || level.muteState == .unknown || state.isPreview)
            .help(muteHelp)
            .accessibilityLabel(localization.format(.commonLabelValue, state.name, muteHelp))
            .accessibilityValue(level.muteState == .partial ? localization.string(.audioInputPartial) : "")

            NativePanelLevelSlider(
                value: Binding(get: { level.scalar == nil ? 0.5 : draft.value }, set: { scalar in
                    guard !state.isPreview, let key = gestureKey,
                          let submission = draft.change(scalar, key: key) else { return }
                    onSetLevel(submission.scalar, submission.key, submission.requestID)
                }),
                isEnabled: state.enabled && level.canAdjust && !state.isPreview,
                accessibilityLabel: localization.format(.commonLabelValue, state.name, sliderLabel),
                accessibilityValue: percentage,
                accessibilityHint: level.canAdjust ? "" : localization.string(isInput ? .audioInputVolumeUnavailable : .volumeTitleUnavailable),
                onEditingChanged: { editing in
                    if editing {
                        gestureKey = state.key
                        gestureControlIdentity = state.interactionIdentity
                    }
                    if let key = gestureKey {
                        draft.setEditing(editing, key: key)
                        if !editing && state.key.hasStableUID && !state.isPreview && gestureControlIdentity == state.interactionIdentity {
                            onFinishLevel(key)
                        }
                    }
                    if !editing { gestureKey = nil }
                }
            )
            .frame(maxWidth: .infinity)
            .background {
                if state.selected, state.key.hasStableUID, !state.isPreview, let scrollTargets {
                    LevelSliderScrollTarget(targets: scrollTargets, target: isInput ? .audioInput : .volume)
                }
            }
            Text(percentage)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 3)
        .onAppear { synchronize() }
        .onChange(of: state) { _ in synchronize() }
        .onChange(of: hasError) { _ in synchronize() }
    }

    private func synchronize() {
        draft.receive(key: state.key, scalar: level.scalar, canAdjust: state.key.hasStableUID && state.enabled && level.canAdjust,
                      completedRequestID: state.completedLevelRequestID, hasError: hasError,
                      controlIdentity: state.interactionIdentity,
                      nativeDeviceLevelReadbackRevision: state.nativeDeviceLevelReadbackRevision)
    }
}
