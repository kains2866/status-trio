import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class PanelActionAlignmentTests: XCTestCase {
    func testFallbackVolumeControlsCenterMuteAndSettingsWithTheSliderRow() throws {
        let state = try makeVolumeState()
        let probe = try render(
            VolumeControlsView(
                state: state,
                actions: StatusPanelActions(),
                scrollTargets: PopoverScrollTargets(),
                onOpenSoundSettings: {}
            )
        )
        let actions = probe.trailingGlyphRects(count: 2, minimumX: 200)
        XCTAssertEqual(actions.count, 2, "volume mute and Settings glyphs must render")
        guard actions.count == 2 else { return }

        let rowCenter = try XCTUnwrap(
            probe.subviewCenterY(where: { $0 is NSSlider }),
            "the volume row must render an AppKit slider to align its glyphs against"
        )
        for (name, rect) in zip(["mute", "settings"], actions) {
            let center = try XCTUnwrap(probe.glyphCenterY(in: rect))
            XCTAssertEqual(
                center,
                rowCenter,
                accuracy: 1,
                "\(name) center must match the volume slider's rendered center"
            )
        }
    }

    func testBrightnessRowCentersPercentageAndGearWithTheSlider() throws {
        let state = BrightnessPanelState(rows: [
            BrightnessRowState(
                id: "display",
                name: "Studio Display",
                isBuiltin: false,
                scalar: 0.5,
                canAdjust: true,
                backend: .directDDC,
                source: .directDDC,
                percentageText: "50%",
                accessibilityLabel: "Studio Display brightness",
                unavailableText: nil
            )
        ])
        let probe = try render(
            BrightnessControlsView(
                state: state,
                actions: StatusPanelActions(),
                scrollTargets: PopoverScrollTargets(),
                onOpenDisplaySettings: {}
            )
        )
        let slider = try XCTUnwrap(probe.subviewFrame(where: { $0 is NSSlider }))
        let percentage = try XCTUnwrap(probe.trailingGlyphRects(count: 1, minimumX: 275).first)
        let gear = CGRect(x: slider.minX - 26, y: slider.midY - 12, width: 18, height: 24)
        for (name, rect) in [("percentage", percentage), ("gear", gear)] {
            let center = try XCTUnwrap(probe.glyphCenterY(in: rect))
            XCTAssertEqual(
                center,
                slider.midY,
                accuracy: 1,
                "\(name) center must match the brightness row's rendered center"
            )
        }
    }

    func testAudioInputControlsCenterMuteAndSettingsWithTheSliderRow() throws {
        let state = try makeAudioInputState(showsDeviceList: false)
        let probe = try render(
            AudioInputControlsView(
                state: state,
                actions: StatusPanelActions(),
                scrollTargets: PopoverScrollTargets(),
                onOpenSoundSettings: {}
            )
        )
        let actions = probe.trailingGlyphRects(count: 2, minimumX: 200, maxX: 340)
        XCTAssertEqual(actions.count, 2, "input mute and Settings glyphs must render")
        guard actions.count == 2 else { return }

        let rowCenter = probe.controlRowCenterY(excluding: actions)
        for (name, rect) in zip(["mute", "settings"], actions) {
            let center = try XCTUnwrap(probe.glyphCenterY(in: rect))
            XCTAssertEqual(
                center,
                try XCTUnwrap(rowCenter),
                accuracy: 0.5,
                "\(name) center must match the input slider row's rendered center"
            )
        }
    }

    func testNetworkRowsCenterChevronAndSettingsWithTheSummaryContent() throws {
        for intent in [PanelSummaryIntent.wifiDetails, .wiredDetails] {
            let state = PanelSummaryState(
                title: intent == .wiredDetails ? "USB Ethernet" : "Example Network",
                subtitle: "192.168.1.20 · 5 GHz",
                measurements: nil,
                symbol: .symbol(
                    name: intent == .wiredDetails ? "cable.connector" : "wifi",
                    variableValue: nil,
                    fallback: nil
                ),
                tint: .secondary,
                accessibilityLabel: "Network",
                accessibilityValue: "Connected",
                showsSettings: true,
                intent: intent
            )
            let probe = try render(
                NetworkStatusView(
                    state: state,
                    onOpenWiFiDetails: { _ in },
                    onOpenWiredDetails: {},
                    onRequestNameAccess: {},
                    onOpenWiFiSettings: {},
                    onOpenNetworkSettings: {},
                    onOpenLocationSettings: {}
                )
            )
            let actions = probe.trailingGlyphRects(count: 2, minimumX: 200)
            XCTAssertEqual(actions.count, 2, "\(intent) must render chevron and Settings")
            guard actions.count == 2 else { continue }

            let contentCenter = try XCTUnwrap(
                probe.glyphCenterY(
                    from: 14 + PanelSummaryActionMetrics.hitTarget + 10,
                    to: actions[0].minX - 10
                )
            )
            for (name, rect) in zip(["chevron", "settings"], actions) {
                let center = try XCTUnwrap(probe.glyphCenterY(in: rect))
                XCTAssertEqual(
                    center,
                    contentCenter,
                    accuracy: 0.5,
                    "\(intent) \(name) center \(center) must match \(contentCenter)"
                )
            }
        }
    }

    func testInputSourceRowCentersChevronAndSettingsWithTheSummaryContent() throws {
        let state = InputSourcePanelState(
            title: "输入法",
            currentName: "微信输入法",
            rows: [],
            emptyMessage: nil,
            failureText: nil,
            openSettingsLabel: "打开键盘设置"
        )
        let probe = try render(
            InputSourceStatusView(
                state: state,
                onOpen: {},
                onOpenKeyboardSettings: {}
            )
        )
        let actions = probe.trailingGlyphRects(count: 2, minimumX: 200)
        XCTAssertEqual(actions.count, 2, "input source must render chevron and Settings")
        guard actions.count == 2 else { return }

        let contentCenter = try XCTUnwrap(
            probe.glyphCenterY(
                from: 14 + PanelSummaryActionMetrics.hitTarget + 10,
                to: actions[0].minX - 10
            )
        )
        for (name, rect) in zip(["chevron", "settings"], actions) {
            let center = try XCTUnwrap(probe.glyphCenterY(in: rect))
            XCTAssertEqual(
                center,
                contentCenter,
                accuracy: 0.5,
                "\(name) center \(center) must match the two-line content center \(contentCenter)"
            )
        }
    }

    func testFallbackAudioSlidersAlignAndBrightnessReservesNameColumn() throws {
        let volumeProbe = try render(
            VolumeControlsView(
                state: try makeVolumeState(),
                actions: StatusPanelActions(),
                scrollTargets: PopoverScrollTargets(),
                onOpenSoundSettings: {}
            )
        )
        let micProbe = try render(
            AudioInputControlsView(
                state: try makeAudioInputState(showsDeviceList: false),
                actions: StatusPanelActions(),
                scrollTargets: PopoverScrollTargets(),
                onOpenSoundSettings: {}
            )
        )
        let brightnessProbe = try render(
            BrightnessControlsView(
                state: BrightnessPanelState(rows: [
                    BrightnessRowState(
                        id: "display",
                        name: "Studio Display",
                        isBuiltin: false,
                        scalar: 0.5,
                        canAdjust: true,
                        backend: .directDDC,
                        source: .directDDC,
                        percentageText: "50%",
                        accessibilityLabel: "Studio Display brightness",
                        unavailableText: nil
                    )
                ]),
                actions: StatusPanelActions(),
                scrollTargets: PopoverScrollTargets(),
                onOpenDisplaySettings: {}
            )
        )

        let volumeX = try XCTUnwrap(volumeProbe.subviewFrame(where: { $0 is NSSlider })?.minX)
        let micX = try XCTUnwrap(micProbe.subviewFrame(where: { $0 is NSSlider })?.minX)
        let brightnessX = try XCTUnwrap(brightnessProbe.subviewFrame(where: { $0 is NSSlider })?.minX)
        XCTAssertEqual(micX, volumeX, accuracy: 0.5, "audio sliders must share their leading slot")
        XCTAssertEqual(brightnessX - volumeX, 112, accuracy: 1,
                       "brightness reserves the same name and action columns as per-device audio")
    }

    func testPerDeviceAudioSlidersShareTheExternalNameAndMuteColumns() throws {
        let volumeProbe = try render(VolumeControlsView(
            state: try makeVolumeState(showsDeviceList: true), actions: StatusPanelActions(),
            scrollTargets: PopoverScrollTargets(), onOpenSoundSettings: {}))
        let inputProbe = try render(AudioInputControlsView(
            state: try makeAudioInputState(showsDeviceList: true), actions: StatusPanelActions(),
            scrollTargets: PopoverScrollTargets(), onOpenSoundSettings: {}))
        let outputFrame = try XCTUnwrap(volumeProbe.subviewFrame(where: { $0 is NSSlider }))
        let inputFrame = try XCTUnwrap(inputProbe.subviewFrame(where: { $0 is NSSlider }))
        let displayProbe = try render(BrightnessControlsView(
            state: BrightnessPanelState(rows: [BrightnessRowState(
                id: "display", name: "Studio Display", isBuiltin: false, scalar: 0.5,
                canAdjust: true, backend: .displayServices, source: .displayServices,
                percentageText: "50%", accessibilityLabel: "Display brightness", unavailableText: nil
            )]), actions: StatusPanelActions(), scrollTargets: PopoverScrollTargets(), onOpenDisplaySettings: {}))
        let displayFrame = try XCTUnwrap(displayProbe.subviewFrame(where: { $0 is NSSlider }))
        XCTAssertEqual(outputFrame.minX, inputFrame.minX, accuracy: 0.5)
        XCTAssertEqual(outputFrame.width, inputFrame.width, accuracy: 0.5)
        XCTAssertEqual(displayFrame.minX, outputFrame.minX, accuracy: 0.5,
                       "display settings must occupy the audio mute column")
        XCTAssertEqual(displayFrame.width, outputFrame.width, accuracy: 0.5,
                       "all three device sliders must end at the same percentage column")
        XCTAssertGreaterThan(outputFrame.minX, 120, "selection icon, external name, and independent mute precede the slider")
        XCTAssertGreaterThan(outputFrame.width, 100)
        XCTAssertEqual(outputFrame.height, 30, accuracy: 0.5)
    }

    private func render<V: View>(_ view: V) throws -> SummaryActionAlignmentProbe {
        let suite = "StatusTrioCoreTests.PanelActionAlignment.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])

        let hosting = NSHostingView(
            rootView: view
                .padding(14)
                .frame(width: 330)
                .background(Color(white: 0.96))
                .environmentObject(localization)
                .environment(\.colorScheme, .light)
        )
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        return try XCTUnwrap(SummaryActionAlignmentProbe(hosting))
    }

    private func makeVolumeState(showsDeviceList: Bool = false) throws -> VolumePanelState {
        let suite = "StatusTrioCoreTests.VolumeActionAlignment.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        return AudioPanelMapper.volume(
            VolumeStatus(
                scalar: 0.4,
                isMuted: false,
                deviceName: "MacBook Pro Speakers",
                outputDevices: showsDeviceList ? [
                    AudioOutputDevice(
                        id: 1,
                        name: "MacBook Pro Speakers",
                        isCurrent: true
                    )
                ] : []
            ),
            controllerAvailable: true,
            deviceList: AudioOutputListPreferences(visibleLimit: nil),
            localization: localization
        )
    }

    private func makeAudioInputState(showsDeviceList: Bool) throws -> AudioInputPanelState {
        let suite = "StatusTrioCoreTests.AudioInputActionAlignment.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let device = AudioInputDevice(id: 11, uid: "layout-mic", name: "Studio Mic")
        return AudioPanelMapper.input(
            AudioInputStatus(
                devices: showsDeviceList ? [device] : [],
                defaultDeviceID: showsDeviceList ? device.id : nil,
                deviceName: device.name,
                scalar: 0.5,
                canSetVolume: true,
                muteState: .unmuted,
                canSetMute: true,
                isRefreshing: false,
                isBusy: false,
                error: nil
            ),
            localization: localization
        )
    }
}
