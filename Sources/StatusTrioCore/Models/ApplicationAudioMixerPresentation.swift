import Foundation

enum ApplicationAudioMixerPresentation: String, CaseIterable, Identifiable {
    case submenu
    case inline
    var id: String { rawValue }
}
