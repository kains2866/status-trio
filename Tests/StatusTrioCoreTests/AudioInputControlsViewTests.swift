import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class AudioInputControlsViewTests: XCTestCase {
    func testUnreadableGainKeepsDisabledNativeSliderAndUnavailableDraft() throws {
        let (host, slider) = try render(level: .unavailable)
        defer { _ = host }
        XCTAssertFalse(slider.isEnabled)
        XCTAssertEqual(slider.doubleValue, 0.5, accuracy: 0.001, "unavailable track is neutral, never fabricated silence")
        XCTAssertEqual(slider.accessibilityValue() as? String, "—")
    }

    func testReadableIndependentLevelUsesNativeSliderAndLocalizedPercentage() throws {
        let (host, slider) = try render(level: .init(scalar: 0.73, canAdjust: true, muteState: .unmuted, canMute: true))
        defer { _ = host }
        XCTAssertEqual(host.bounds.height, VolumeDeviceRowMetrics.singleLineHeight, accuracy: 0.1)
        XCTAssertTrue(slider.isEnabled)
        XCTAssertEqual(slider.doubleValue, 0.73, accuracy: 0.001)
        XCTAssertEqual(slider.accessibilityValue() as? String, "73%")
    }

    func testMissingOrBlankUIDDisablesPerDeviceNativeSliderWithoutHidingReadableLevel() throws {
        for uid: String? in [nil, "", "  \n\t"] {
            for isInput in [false, true] {
                let (host, slider) = try render(level: .init(scalar: 0.73, canAdjust: true, muteState: .unmuted, canMute: true), uid: uid, isInput: isInput)
                defer { _ = host }
                XCTAssertFalse(slider.isEnabled)
                XCTAssertEqual(slider.doubleValue, 0.73, accuracy: 0.001)
                XCTAssertEqual(slider.accessibilityValue() as? String, "73%")
            }
        }
    }

    private func render(level: AudioDeviceLevel, uid: String? = "usb", isInput: Bool = true) throws -> (NSView, NSSlider) {
        let suite = "AudioInputControlsViewTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { TestUserDefaults.removeSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let row = PanelAudioDeviceRow(key: .init(id: 12, uid: uid), name: "USB microphone",
                                     symbol: .symbol(name: "mic", variableValue: nil, fallback: nil),
                                     selected: false, enabled: true, accessibilityLabel: "USB microphone", level: level)
        let host = NSHostingView(rootView: AudioDeviceLevelRow(
            state: row, isInput: isInput, sliderLabel: "Input level", onSelect: {},
            onSetLevel: { _, _, _ in }, onToggleMute: { _ in }
        ).frame(width: 302).environmentObject(localization))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        func sliders(_ view: NSView) -> [NSSlider] {
            (view as? NSSlider).map { [$0] } ?? view.subviews.flatMap { sliders($0) }
        }
        return (host, try XCTUnwrap(sliders(host).first))
    }
}
