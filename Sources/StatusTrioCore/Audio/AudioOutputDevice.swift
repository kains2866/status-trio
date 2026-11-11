import CoreAudio

struct AudioOutputDevice: Identifiable, Hashable, Sendable {
    let id: AudioDeviceID
    let name: String?
    let uid: String?
    let isCurrent: Bool
    let volume: Double?
    let level: AudioDeviceLevel?
    /// The hardware family of the device, read from
    /// `kAudioDevicePropertyTransportType`.
    let transport: AudioOutputTransport?
    /// The live output data source, read from `kAudioDevicePropertyDataSource`.
    let dataSource: AudioOutputDataSource?
    /// The icon the driver ships for the device, read from
    /// `kAudioDevicePropertyIcon`. Built-in hardware has no icon.
    let iconURL: URL?
    /// The device's model identifier, read from `kAudioDevicePropertyModelUID`.
    /// A Bluetooth device reports its product and vendor IDs here ("200f 4c"),
    /// which is what identifies an AirPods model even after a rename.
    let modelUID: String?

    init(
        id: AudioDeviceID,
        name: String?,
        uid: String? = nil,
        isCurrent: Bool,
        volume: Double? = nil,
        transport: AudioOutputTransport? = nil,
        dataSource: AudioOutputDataSource? = nil,
        iconURL: URL? = nil,
        modelUID: String? = nil,
        level: AudioDeviceLevel? = nil
    ) {
        self.id = id
        self.name = name
        self.uid = uid
        self.isCurrent = isCurrent
        self.volume = level == nil ? volume : level?.scalar
        self.level = level
        self.transport = transport
        self.dataSource = dataSource
        self.iconURL = iconURL
        self.modelUID = modelUID
    }

    var isBluetoothAudio: Bool {
        transport?.isBluetooth == true
    }

    func replacingVolume(_ volume: Double?) -> AudioOutputDevice {
        AudioOutputDevice(id: id, name: name, uid: uid, isCurrent: isCurrent, volume: volume,
                          transport: transport, dataSource: dataSource, iconURL: iconURL, modelUID: modelUID,
                          level: level.map { AudioDeviceLevel(scalar: volume, canAdjust: $0.canAdjust, muteState: $0.muteState, canMute: $0.canMute) })
    }
}
