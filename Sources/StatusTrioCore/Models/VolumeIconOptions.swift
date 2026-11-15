import Foundation

public enum VolumeDisplayStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case dots
    case arc

    public var id: String { rawValue }
}

public struct VolumeIconOptions: Equatable, Hashable, Sendable {
    public let displayStyle: VolumeDisplayStyle
    public let ringStrokeScale: Double
    public let showsRedWhenMuted: Bool
    public let showsRedWhenZero: Bool

    /// Kept in step with the stroke-style default so tuning the enum cannot
    /// silently desynchronise `.standard`, the previews, and the icon guide.
    public static let defaultRingStrokeScale: Double = RingStrokeStyle.regular.scale

    public static let standard = VolumeIconOptions(displayStyle: .dots, ringStrokeScale: defaultRingStrokeScale)

    /// Scale applied to the discrete dots' radius.
    ///
    /// The four dots sit at fixed positions on the volume arc, so their spacing
    /// cannot grow with the stroke setting. A full multiplier would close the
    /// gap between neighbouring dots (down to ~0.3 pt at 1.5x, i.e. under one
    /// pixel) and push the lowest dot against the canvas edge, so the radius
    /// follows the setting at half strength and keeps the dots readable as
    /// separate marks.
    public var dotRadiusScale: Double {
        1 + (ringStrokeScale - 1) * 0.5
    }

    public init(
        displayStyle: VolumeDisplayStyle = .dots,
        ringStrokeScale: Double = defaultRingStrokeScale,
        showsRedWhenMuted: Bool = false,
        showsRedWhenZero: Bool = false
    ) {
        self.displayStyle = displayStyle
        self.ringStrokeScale = ringStrokeScale.isFinite ? min(2.5, max(0.5, ringStrokeScale)) : Self.defaultRingStrokeScale
        self.showsRedWhenMuted = showsRedWhenMuted
        self.showsRedWhenZero = showsRedWhenZero
    }
}
