import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class AudioInputLayoutTests: XCTestCase {
    func testBusyStateKeepsInputControlsAtTheSameSize() throws {
        for language in [AppLanguage.english, .simplifiedChinese, .german, .arabic] {
            let idle = try size(busy: false, language: language)
            let busy = try size(busy: true, language: language)
            XCTAssertEqual(idle.width, busy.width, accuracy: 0.1, language.rawValue)
            XCTAssertEqual(idle.height, busy.height, accuracy: 0.1, language.rawValue)
        }
    }

    func testMicrophoneUsageDoesNotAddABadgeOrChangeTheRowHeight() throws {
        for language in [AppLanguage.english, .simplifiedChinese, .german, .arabic] {
            let idle = try size(busy: false, language: language, inUse: false)
            let inUse = try size(busy: false, language: language, inUse: true)
            XCTAssertEqual(idle.width, inUse.width, accuracy: 0.1, language.rawValue)
            XCTAssertEqual(idle.height, inUse.height, accuracy: 0.1, language.rawValue)
        }
    }

    private func size(busy: Bool, language: AppLanguage, inUse: Bool? = nil) throws -> NSSize {
        let suite = "AudioInputLayoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: [language.rawValue])
        let device = AudioInputDevice(id: 11, uid: "layout-mic", name: "Studio AirPods Pro")
        let status = AudioInputStatus(
            devices: [device],
            defaultDeviceID: device.id,
            deviceName: device.name,
            scalar: 0.5,
            canSetVolume: true,
            muteState: .unmuted,
            canSetMute: true,
            isRefreshing: false,
            isBusy: busy,
            error: nil,
            isDefaultInputInUse: inUse
        )
        let host = NSHostingView(rootView:
            AudioInputControlsView(
                state: AudioPanelMapper.input(status, localization: localization),
                actions: StatusPanelActions(),
                scrollTargets: PopoverScrollTargets(),
                onOpenSoundSettings: {}
            )
            .padding(14)
            .frame(width: 330)
            .environmentObject(localization)
            .environment(\.layoutDirection, language == .arabic ? .rightToLeft : .leftToRight)
        )
        return host.fittingSize
    }
}
