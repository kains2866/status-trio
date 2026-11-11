import CoreAudio

@MainActor
protocol AudioOutputControlling: AnyObject {
    func isCurrentOutputDevice(_ deviceID: AudioDeviceID, expectedUID: String?) -> Bool
    @discardableResult func setVolume(_ scalar: Double) -> Bool
    @discardableResult func toggleMute() -> Bool
    @discardableResult func setVolume(_ scalar: Double, forDeviceID deviceID: AudioDeviceID, expectedUID: String?) -> Bool
    @discardableResult func toggleMute(forDeviceID deviceID: AudioDeviceID, expectedUID: String?) -> Bool
    @discardableResult func selectOutputDevice(_ deviceID: AudioDeviceID) -> Bool
}
