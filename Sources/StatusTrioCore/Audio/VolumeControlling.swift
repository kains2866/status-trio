import CoreAudio

@MainActor
protocol VolumeControlling: AnyObject {
    func setVolume(_ scalar: Double)
    func toggleMute()
    func setVolume(_ scalar: Double, forDeviceID deviceID: AudioDeviceID, expectedUID: String?)
    func toggleMute(forDeviceID deviceID: AudioDeviceID, expectedUID: String?)
    func flushPendingVolume(forDeviceID deviceID: AudioDeviceID, expectedUID: String?)
    func selectOutputDevice(_ deviceID: AudioDeviceID)
    func flushPendingVolume()
}

extension VolumeControlling {
    func flushPendingVolume() {}
}
