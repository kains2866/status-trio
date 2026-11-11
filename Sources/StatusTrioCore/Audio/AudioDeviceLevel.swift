/// A read-only device snapshot. Missing values are unavailable, not silence.
struct AudioDeviceLevel: Equatable, Hashable, Sendable {
    let scalar: Double?
    let canAdjust: Bool
    let muteState: AudioDeviceMuteState
    let canMute: Bool

    static let unavailable = AudioDeviceLevel(
        scalar: nil, canAdjust: false, muteState: .unknown, canMute: false
    )
}

enum AudioDeviceMuteState: Equatable, Hashable, Sendable {
    case unknown, unmuted, muted, partial
}
