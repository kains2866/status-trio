import AppKit
import SwiftUI

enum DeviceNameHoverMetrics {
    static let fontSize = NSFont.smallSystemFontSize
    static let textWidth: CGFloat = 72
    static let inset: CGFloat = 8
    static let cornerRadius: CGFloat = 8
}

struct DeviceNameRevealShape: Shape {
    var progress: CGFloat
    let collapsedWidth: CGFloat
    let layoutDirection: LayoutDirection

    func path(in rect: CGRect) -> Path {
        let initialWidth = min(rect.width, collapsedWidth)
        let width = initialWidth + (rect.width - initialWidth) * min(1, max(0, progress))
        let x = layoutDirection == .rightToLeft ? rect.maxX - width : rect.minX
        return RoundedRectangle(cornerRadius: DeviceNameHoverMetrics.cornerRadius, style: .continuous)
            .path(in: CGRect(x: x, y: rect.minY, width: width, height: rect.height))
    }
}

/// Animate the material's width, keeping the label out of any clipping mask.
private struct DeviceNameHoverBubble: View, Animatable {
    let name: String
    let width: CGFloat
    var progress: CGFloat
    let collapsedWidth: CGFloat
    let layoutDirection: LayoutDirection

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Text(name)
            .font(.system(size: DeviceNameHoverMetrics.fontSize))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DeviceNameHoverMetrics.inset)
            .padding(.vertical, 6)
            .frame(width: width, alignment: .leading)
            .background {
                if progress > 0 {
                    DeviceNameRevealShape(progress: progress, collapsedWidth: collapsedWidth,
                                          layoutDirection: layoutDirection)
                        .fill(.regularMaterial)
                }
            }
            .overlay {
                if progress > 0 {
                    DeviceNameRevealShape(progress: progress, collapsedWidth: collapsedWidth,
                                          layoutDirection: layoutDirection)
                        .stroke(.primary.opacity(0.08), lineWidth: 0.5)
                }
            }
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            .opacity(Double(progress))
    }
}

extension View {
    func deviceNameHoverReveal(_ name: String, leadingInset: CGFloat, trailingInset: CGFloat) -> some View {
        modifier(DeviceNameHoverReveal(name: name, leadingInset: leadingInset, trailingInset: trailingInset))
    }
}

/// Expands over the existing controls, so reading a name never resizes the row.
private struct DeviceNameHoverReveal: ViewModifier {
    let name: String
    let leadingInset: CGFloat
    let trailingInset: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var isHovered = false

    private var nameWidth: CGFloat { DeviceNameHoverMetrics.textWidth + DeviceNameHoverMetrics.inset }
    private var textWidth: CGFloat {
        (name as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: DeviceNameHoverMetrics.fontSize)
        ]).width
    }
    private var isTruncated: Bool { textWidth > DeviceNameHoverMetrics.textWidth }

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geometry in
                    DeviceNameHoverRegion { hovering in
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                            isHovered = hovering
                        }
                    }
                    .frame(width: nameWidth, height: geometry.size.height)
                    .offset(x: leadingInset)

                    if isTruncated {
                        let revealWidth = max(0, min(geometry.size.width - leadingInset - trailingInset,
                            max(nameWidth, ceil(textWidth) + DeviceNameHoverMetrics.inset * 2)))
                        // Layout positioning keeps text and material in the same coordinate space.
                        HStack(spacing: 0) {
                            Color.clear.frame(width: max(0, leadingInset - 4))
                            DeviceNameHoverBubble(name: name, width: revealWidth,
                                                  progress: isHovered ? 1 : 0, collapsedWidth: nameWidth,
                                                  layoutDirection: layoutDirection)
                                .padding(4)
                                .frame(width: revealWidth + 8,
                                       height: geometry.size.height, alignment: .leading)
                            Spacer(minLength: 0)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
            }
            .zIndex(isHovered && isTruncated ? 1 : 0)
            .onChange(of: name) { _ in isHovered = false }
            .onDisappear { isHovered = false }
    }
}

private struct DeviceNameHoverRegion: NSViewRepresentable {
    let onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> DeviceNameHoverRegionView {
        DeviceNameHoverRegionView()
    }

    func updateNSView(_ view: DeviceNameHoverRegionView, context: Context) {
        view.onHoverChanged = onHoverChanged
    }

    static func dismantleNSView(_ view: DeviceNameHoverRegionView, coordinator: ()) {
        view.onHoverChanged = nil
    }
}

/// Active tracking also works when the status panel hasn't activated the app.
final class DeviceNameHoverRegionView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private var hoverTracking: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking)
        hoverTracking = tracking
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }
}
