import AppKit
import SwiftUI

private struct ApplicationAudioMixerEnvironmentKey: EnvironmentKey {
    static let defaultValue: ApplicationAudioMixerController? = nil
}

extension EnvironmentValues {
    var applicationAudioMixer: ApplicationAudioMixerController? {
        get { self[ApplicationAudioMixerEnvironmentKey.self] }
        set { self[ApplicationAudioMixerEnvironmentKey.self] = newValue }
    }
}

struct ApplicationAudioMixerHeader: View {
    @EnvironmentObject private var localization: Localization
    let title: String
    let isInput: Bool
    @ObservedObject var controller: ApplicationAudioMixerController
    let onOpenSettings: () -> Void
    @State private var isPresented = false
    @State private var surfaceID = UUID()

    private var needsDiscovery: Bool {
        controller.isEnabled && controller.presentation == .submenu && isPresented
    }

    var body: some View {
        HStack(spacing: 8) {
            if controller.isEnabled && controller.presentation == .submenu {
                Button { isPresented = true } label: {
                    HStack {
                        Text(title)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localization.string(isInput ? .appMixerInputTitle : .appMixerOutputTitle))
                .cascadingSubmenu(
                    isPresented: $isPresented,
                    hasContent: controller.hasSectionContent(isInput: isInput)
                ) {
                    ApplicationAudioMixerView(controller: controller, isInput: isInput)
                }
            } else {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !controller.isEnabled, controller.errorMessage != nil {
                    Button { controller.reset() } label: {
                        Image(systemName: "arrow.clockwise.circle")
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .help(localization.string(.appMixerFailed) + " " + localization.string(.appMixerReset))
                    .accessibilityLabel(localization.string(.appMixerFailed) + " " + localization.string(.appMixerReset))
                }
            }
            Button(action: onOpenSettings) {
                PanelActionGlyph(systemName: "gearshape").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localization.string(isInput ? .audioInputOpenSettings : .volumeActionOpenSettings))
        }
        .onChange(of: controller.isEnabled) { enabled in
            if !enabled { isPresented = false }
        }
        .onChange(of: controller.presentation) { _ in isPresented = false }
        .onReceive(controller.panelDidClose) { isPresented = false }
        .onAppear { controller.setSurfaceVisible(needsDiscovery, id: surfaceID) }
        .onChange(of: needsDiscovery) { visible in controller.setSurfaceVisible(visible, id: surfaceID) }
        .onDisappear {
            isPresented = false
            controller.setSurfaceVisible(false, id: surfaceID)
        }
    }
}

struct ApplicationAudioMixerView: View {
    @EnvironmentObject private var localization: Localization
    @ObservedObject var controller: ApplicationAudioMixerController
    let isInput: Bool
    private var rows: [ApplicationAudioMixerRow] { controller.rows.filter { $0.isInput == isInput } }

    var body: some View {
        if controller.hasSectionContent(isInput: isInput) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(localization.string(isInput ? .appMixerInputTitle : .appMixerOutputTitle))
                        .font(controller.presentation == .inline ? .caption : .headline)
                        .foregroundStyle(controller.presentation == .inline ? Color.secondary : Color.primary)
                    Spacer()
                    if !isInput, controller.isEnabled || controller.errorMessage != nil {
                        Button(localization.string(.appMixerReset)) { controller.reset() }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !controller.isSupported {
                    message(.appMixerUnsupported)
                } else {
                    let rows = rows
                    if !rows.isEmpty {
                        if controller.presentation == .inline {
                            ApplicationAudioMixerRowsViewport(rows: rows, controller: controller)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(rows) { row in
                                    ApplicationAudioMixerRowView(row: row, controller: controller)
                                }
                            }
                        }
                    }
                    if controller.errorMessage != nil {
                        message(.appMixerFailed)
                    }
                }
            }
        }
    }

    private func message(_ key: LocalizationKey) -> some View {
        Text(localization.string(key)).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private extension ApplicationAudioMixerController {
    func hasSectionContent(isInput: Bool) -> Bool {
        !isSupported || errorMessage != nil || rows.contains { $0.isInput == isInput }
    }
}

private struct ApplicationAudioMixerRowView: View {
    @EnvironmentObject private var localization: Localization
    let row: ApplicationAudioMixerRow
    @ObservedObject var controller: ApplicationAudioMixerController

    private var percentage: String {
        row.gain.formatted(.percent.precision(.fractionLength(0)).locale(localization.resolvedLanguage.locale))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ApplicationAudioMixerAppIcon(appURL: row.appURL)
                    .frame(width: 24, height: 24)
                Text(row.name)
                    .font(.system(size: DeviceNameHoverMetrics.fontSize))
                    .lineLimit(1).truncationMode(.middle)
                    .frame(width: DeviceNameHoverMetrics.textWidth, alignment: .leading)
                    .padding(.leading, DeviceNameHoverMetrics.inset)
                if row.isInput {
                    if let deviceName = row.outputDeviceName {
                        Text(deviceName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        Spacer(minLength: 0)
                    }
                } else {
                    Button { controller.toggleMute(for: row.id) } label: {
                        Image(systemName: row.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(row.isMuted ? Color.red : Color.secondary)
                            .frame(width: 18, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!controller.isEnabled || !row.canAdjust)
                    .accessibilityLabel(localization.format(.commonLabelValue, row.name,
                        localization.string(row.isMuted ? .appMixerUnmute : .appMixerMute)))
                    NativePanelLevelSlider(
                        value: Binding(get: { row.gain }, set: { controller.setGain($0, for: row.id) }),
                        isEnabled: controller.isEnabled && row.canAdjust,
                        accessibilityLabel: row.name,
                        accessibilityValue: percentage,
                        accessibilityHint: "",
                        onEditingChanged: { _ in }
                    )
                    .frame(maxWidth: .infinity)
                    Text(percentage).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
            .padding(.vertical, 3)
            .deviceNameHoverReveal(row.name, leadingInset: 32, trailingInset: 0)
            if let deviceName = row.outputDeviceName, !row.isInput && !row.canAdjust {
                Text(deviceName).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).padding(.leading, 40)
            }
            if !row.isInput, controller.isEnabled, !row.canAdjust {
                Text(localization.string(.appMixerRouteUnavailable))
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.leading, 40)
            }
        }
    }
}

private struct ApplicationAudioMixerAppIcon: View {
    let appURL: URL?
    @State private var icon: NSImage?
    var body: some View {
        Group {
        if let icon {
            Image(nsImage: icon).resizable().scaledToFit()
        } else {
            Image(systemName: "app.fill").resizable().scaledToFit().foregroundStyle(.secondary)
        }
        }
        .task(id: appURL) {
            icon = appURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
        }
    }
}

/// Observes both preferences through the controller without remounting device rows.
struct ApplicationAudioMixerInlineSection: View {
    @ObservedObject var controller: ApplicationAudioMixerController
    let isInput: Bool

    var body: some View {
        if controller.isEnabled, controller.presentation == .inline,
           controller.hasSectionContent(isInput: isInput) {
            Divider().padding(.vertical, 4)
            ApplicationAudioMixerView(controller: controller, isInput: isInput)
        }
    }
}

private struct ApplicationAudioMixerRowsViewport: View {
    let rows: [ApplicationAudioMixerRow]
    @ObservedObject var controller: ApplicationAudioMixerController
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(rows) { row in
                    ApplicationAudioMixerRowView(row: row, controller: controller)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: ApplicationAudioMixerRowsHeight.self, value: geometry.size.height)
            })
            .background(ApplicationAudioMixerScrollMarker())
        }
        // The outer status panel disables its own scroller while it fits the
        // screen. This independent capped viewport must remain scrollable.
        .environment(\.isScrollEnabled, true)
        .frame(height: min(240, max(32, contentHeight)))
        .onPreferenceChange(ApplicationAudioMixerRowsHeight.self) { contentHeight = $0 }
    }
}

private struct ApplicationAudioMixerRowsHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Prevent the panel-wide volume fallback from treating a short app list as a master-volume wheel.
private struct ApplicationAudioMixerScrollMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ view: Marker, context: Context) { view.attach() }
    final class Marker: NSView {
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); attach() }
        override func layout() { super.layout(); attach() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        func attach() { enclosingScrollView?.identifier = PanelScrollHitTesting.applicationMixerScrollIdentifier }
    }
}
