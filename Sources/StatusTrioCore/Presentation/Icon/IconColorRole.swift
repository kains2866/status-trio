enum IconColorRole: Equatable, Hashable, Sendable {
    case primary
    case inactive
    case critical
    case lowPower
    /// High Power Mode ring colour (#235).
    case highPower
    case powered
    case bluetooth
    /// Volume alerts stay red independently of the battery's custom palette.
    case volumeAlert
}
