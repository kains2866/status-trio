import AudioToolbox
import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Equatable, Sendable {
  let id: AudioDeviceID
  let uid: String?
  let name: String?
  let level: AudioDeviceLevel?

  init(id: AudioDeviceID, uid: String?, name: String?, level: AudioDeviceLevel? = nil) {
    self.id = id
    self.uid = uid
    self.name = name
    self.level = level
  }
}

enum AudioInputMuteState: Equatable, Sendable {
  case unmuted
  case muted
  case partial
}

enum AudioInputError: Equatable, Sendable {
  case refreshFailed
  case switchFailed
  case volumeFailed
  case muteFailed
  case timedOut
}

enum AudioInputHardwareError: Error, Equatable, Sendable {
  case unsupported
  case unavailable
  case invalidValue
  case osStatus(OSStatus)
}

struct AudioInputVolumeReadback: Equatable, Sendable {
  let scalar: Double?
  let canSet: Bool

  static let unsupported = Self(scalar: nil, canSet: false)
}

struct AudioInputMuteReadback: Equatable, Sendable {
  let state: AudioInputMuteState?
  let canSet: Bool

  static let unsupported = Self(state: nil, canSet: false)
}

struct AudioInputReading: Equatable, Sendable {
  let devices: [AudioInputDevice]?
  let defaultDeviceID: AudioDeviceID?
  let deviceName: String?
  let scalar: Double?
  let canSetVolume: Bool
  let muteState: AudioInputMuteState?
  let canSetMute: Bool
  var isDefaultInputInUse: Bool? = nil
}

struct AudioInputProcessDeviceUsage: Equatable, Sendable {
  let activeInputDeviceIDs: Set<AudioDeviceID>
  let isComplete: Bool

  func isInUse(_ deviceID: AudioDeviceID) -> Bool? {
    if activeInputDeviceIDs.contains(deviceID) { return true }
    return isComplete ? false : nil
  }
}

struct AudioInputUsageReading: Equatable, Sendable {
  let defaultDeviceID: AudioDeviceID?
  let isDefaultInputInUse: Bool?
}

struct AudioInputDeviceScalarCompletion: Equatable, Sendable {
  let uid: String?
  let requestID: UUID
}

struct AudioInputStatus: Equatable, Sendable {
  var devices: [AudioInputDevice]
  var defaultDeviceID: AudioDeviceID?
  var deviceName: String?
  var scalar: Double?
  var canSetVolume: Bool
  var muteState: AudioInputMuteState?
  var canSetMute: Bool
  var isRefreshing: Bool
  var isBusy: Bool
  var error: AudioInputError?
  var isDefaultInputInUse: Bool? = nil
  /// Last scalar request whose readback (or terminal failure) has been resolved.
  var completedScalarRequestID: UUID? = nil
  /// Scalar writes are serialized and can accept further input without dimming controls.
  var isAdjustingScalar = false
  /// Explicit-device acknowledgements never resolve the default-route draft.
  var completedDeviceScalarRequestID: UUID? = nil
  var completedDeviceScalarDeviceID: AudioDeviceID? = nil
  var completedDeviceScalarDeviceUID: String? = nil
  var completedDeviceScalarRequests: [AudioDeviceID: AudioInputDeviceScalarCompletion] = [:]

  static let empty = Self(
    devices: [],
    defaultDeviceID: nil,
    deviceName: nil,
    scalar: nil,
    canSetVolume: false,
    muteState: nil,
    canSetMute: false,
    isRefreshing: false,
    isBusy: false,
    error: nil,
    isDefaultInputInUse: nil
  )
}
