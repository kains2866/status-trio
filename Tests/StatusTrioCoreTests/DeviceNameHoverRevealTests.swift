import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class DeviceNameHoverRevealTests: XCTestCase {
    func testAnimatedMicrophoneRevealFinishesAtTheSameFullNameAsStaticRendering() throws {
        let localization = try makeLocalization(preferredLanguages: ["zh-Hans"])
        let state = AudioPanelMapper.input(AudioInputStatus(
            devices: [AudioInputDevice(id: 2, uid: "mic", name: "MacBook Pro Microphone")],
            defaultDeviceID: 2, deviceName: "MacBook Pro Microphone", scalar: 0.5,
            canSetVolume: true, muteState: .unmuted, canSetMute: true,
            isRefreshing: false, isBusy: false, error: nil
        ), localization: localization)
        func makeHost(disableAnimations: Bool) -> (NSView, NSWindow) {
            let host = NSHostingView(rootView: AudioInputControlsView(
                state: state, actions: StatusPanelActions(), scrollTargets: PopoverScrollTargets(), onOpenSoundSettings: {}
            ).padding(14).frame(width: 330)
                .background(Color(nsColor: .windowBackgroundColor))
                .environmentObject(localization)
                .environment(\.colorScheme, .light)
                .transaction { transaction in
                    if disableAnimations {
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
                })
            host.appearance = NSAppearance(named: .aqua)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = host.appearance
            window.contentView = host
            return (host, window)
        }
        let (reference, referenceWindow) = makeHost(disableAnimations: true)
        let (animated, animatedWindow) = makeHost(disableAnimations: false)
        defer {
            referenceWindow.contentView = nil; referenceWindow.close()
            animatedWindow.contentView = nil; animatedWindow.close()
        }
        settle(reference)
        settle(animated)
        let before = try capture(animated)
        let referenceTracking = try XCTUnwrap(descendants(DeviceNameHoverRegionView.self, in: reference).first)
        referenceTracking.mouseEntered(with: try event(.mouseEntered, window: referenceWindow))
        settle(reference)
        let fullName = try capture(reference)
        try export(fullName, name: "microphone-static-full.png")

        let tracking = try XCTUnwrap(descendants(DeviceNameHoverRegionView.self, in: animated).first)
        tracking.mouseEntered(with: try event(.mouseEntered, window: animatedWindow))
        for (index, delay) in [0.04, 0.2, 0.4].enumerated() {
            settle(animated, for: delay)
            try export(capture(animated), name: "microphone-animated-\(index).png")
        }
        let finalImage = try capture(animated)
        XCTAssertEqual(finalImage, fullName, "Completed animation must reveal the entire same name")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: finalImage))
        let scale = CGFloat(bitmap.pixelsWide) / animated.bounds.width
        let slider = try XCTUnwrap(descendants(NSSlider.self, in: animated).first)
        let nativeCenterY = slider.convert(slider.bounds, to: animated).midY
        let centerY = animated.isFlipped ? nativeCenterY : animated.bounds.height - nativeCenterY
        // The last "ne" of this fixed 11pt fixture occupies x182...191pt.
        // A native-slider occlusion at x173pt leaves this area without text.
        var suffixInk = 0
        for x in Int(182 * scale)..<Int(191 * scale) {
            for y in Int((centerY - 7) * scale)..<Int((centerY + 7) * scale) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if max(color.redComponent, color.greenComponent, color.blueComponent) < 0.35 {
                    suffixInk += 1
                }
            }
        }
        XCTAssertGreaterThan(suffixInk, 6, "The name's final letters must be drawn over the native slider")
        let paddingColor = try XCTUnwrap(bitmap.colorAt(x: Int(192 * scale), y: Int(centerY * scale))?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(paddingColor.redComponent, 0.85, "The popup must cover the underlying slider track")
        XCTAssertLessThan(paddingColor.redComponent, 0.995, "The popup background must extend past the name's last letter")
        tracking.mouseExited(with: try event(.mouseExited, window: animatedWindow))
        settle(animated, for: 0.3)
        XCTAssertEqual(try capture(animated), before)
    }

    func testRevealSurfaceExpandsOnlyTowardTheControlsAndReversesAlongTheSameEdge() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 40)
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            for (progress, width) in [(CGFloat(0), CGFloat(88)), (0.5, 144), (1, 200), (0.5, 144), (0, 88)] {
                let mask = DeviceNameRevealShape(progress: progress, collapsedWidth: 88,
                                                layoutDirection: direction).path(in: bounds).boundingRect
                XCTAssertEqual(mask.width, width, accuracy: 0.01)
                XCTAssertEqual(mask.height, 40, accuracy: 0.01)
                if direction == .leftToRight {
                    XCTAssertEqual(mask.minX, 0, accuracy: 0.01)
                } else {
                    XCTAssertEqual(mask.maxX, 200, accuracy: 0.01)
                }
            }
        }
    }

    func testAllDeviceRowsRevealImmediatelyWithoutMovingControlsAndRestoreOnExit() throws {
        let localization = try makeLocalization()
        let output = AudioOutputDevice(id: 1, name: "MacBook Pro Speakers", uid: "speakers", isCurrent: true)
        let outputState = AudioPanelMapper.volume(
            VolumeStatus(scalar: 0.5, isMuted: false, deviceName: output.name, outputDevices: [output]),
            controllerAvailable: true, localization: localization
        )
        let inputState = AudioPanelMapper.input(AudioInputStatus(
            devices: [AudioInputDevice(id: 2, uid: "mic", name: "MacBook Pro Microphone")],
            defaultDeviceID: 2, deviceName: "MacBook Pro Microphone", scalar: 0.5,
            canSetVolume: true, muteState: .unmuted, canSetMute: true,
            isRefreshing: false, isBusy: false, error: nil
        ), localization: localization)
        let brightness = BrightnessPanelState(rows: [BrightnessRowState(
            id: "display", name: "Built-in Retina Display", isBuiltin: false,
            scalar: 0.5, canAdjust: true, backend: .displayServices, source: .displayServices,
            percentageText: "50%", accessibilityLabel: "Display brightness", unavailableText: nil
        )])
        let views = [
            AnyView(VolumeControlsView(state: outputState, actions: StatusPanelActions(),
                                      scrollTargets: PopoverScrollTargets(), onOpenSoundSettings: {})),
            AnyView(AudioInputControlsView(state: inputState, actions: StatusPanelActions(),
                                          scrollTargets: PopoverScrollTargets(), onOpenSoundSettings: {})),
            AnyView(BrightnessControlsView(state: brightness, actions: StatusPanelActions(),
                                          scrollTargets: PopoverScrollTargets(), onOpenDisplaySettings: {}))
        ]

        for (index, view) in views.enumerated() {
            let host = NSHostingView(rootView: view.padding(14).frame(width: 330)
                .background(Color(nsColor: .windowBackgroundColor))
                .environmentObject(localization)
                .transaction { $0.animation = nil; $0.disablesAnimations = true })
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.contentView = nil; window.close() }
            settle(host)
            let tracking = try XCTUnwrap(descendants(DeviceNameHoverRegionView.self, in: host).first,
                                         "Device group \(index) must use the same immediate name reveal")
            let slider = try XCTUnwrap(descendants(NSSlider.self, in: host).first)
            let originalSize = host.fittingSize
            let originalSliderFrame = slider.convert(slider.bounds, to: host)
            let before = try capture(host)
            try export(before, name: "device-name-\(index)-collapsed.png")

            tracking.mouseEntered(with: try event(.mouseEntered, window: window))
            settle(host)
            let expanded = try capture(host)
            XCTAssertNotEqual(expanded, before, "The name must expand without waiting for an NSToolTip")
            XCTAssertEqual(host.fittingSize, originalSize, "Hover must not reflow the panel")
            XCTAssertEqual(slider.convert(slider.bounds, to: host), originalSliderFrame)
            XCTAssertNil(tracking.hitTest(NSPoint(x: tracking.bounds.midX, y: tracking.bounds.midY)))
            try export(expanded, name: "device-name-\(index)-expanded.png")

            tracking.mouseExited(with: try event(.mouseExited, window: window))
            settle(host)
            XCTAssertEqual(try capture(host), before, "Leaving the name restores the controls immediately")
        }
    }

    func testShortNamesStayCompactAndLongNamesStayInsideThePanelInBothDirections() throws {
        let localization = try makeLocalization()
        let longName = "Living room — Dell UltraSharp U2723QE via USB-C DisplayPort"
        let fixtures: [(String, LayoutDirection)] = [("USB", .leftToRight), (longName, .leftToRight), (longName, .rightToLeft)]
        for (index, fixture) in fixtures.enumerated() {
            let (name, direction) = fixture
            let device = AudioOutputDevice(id: 1, name: name, uid: "speakers", isCurrent: true)
            let state = AudioPanelMapper.volume(
                VolumeStatus(scalar: 0.5, isMuted: false, deviceName: name, outputDevices: [device]),
                controllerAvailable: true, localization: localization
            )
            let host = NSHostingView(rootView: VolumeControlsView(
                state: state, actions: StatusPanelActions(), scrollTargets: PopoverScrollTargets(), onOpenSoundSettings: {}
            ).padding(14).frame(width: 330)
                .background(Color(nsColor: .windowBackgroundColor))
                .environmentObject(localization)
                .environment(\.colorScheme, .dark)
                .environment(\.layoutDirection, direction)
                .transaction { $0.animation = nil; $0.disablesAnimations = true })
            host.appearance = NSAppearance(named: .darkAqua)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = host.appearance
            window.contentView = host
            defer { window.contentView = nil; window.close() }
            settle(host)
            let tracking = try XCTUnwrap(descendants(DeviceNameHoverRegionView.self, in: host).first)
            let trackingFrame = tracking.convert(tracking.bounds, to: host)
            XCTAssertGreaterThanOrEqual(trackingFrame.minX, 14)
            XCTAssertLessThanOrEqual(trackingFrame.maxX, 316)
            if direction == .rightToLeft {
                XCTAssertGreaterThan(trackingFrame.midX, host.bounds.midX, "Track the name beside the right-hand icon")
            } else {
                XCTAssertLessThan(trackingFrame.midX, host.bounds.midX)
            }
            let originalSize = host.fittingSize
            let before = try capture(host)
            tracking.mouseEntered(with: try event(.mouseEntered, window: window))
            settle(host)
            let expanded = try capture(host)
            if name == "USB" {
                XCTAssertEqual(expanded, before, "A name that fits should not cover any controls")
            } else {
                XCTAssertNotEqual(expanded, before)
                try export(expanded, name: "device-name-long-\(index)-dark.png")
            }
            XCTAssertEqual(host.fittingSize, originalSize)
            tracking.mouseExited(with: try event(.mouseExited, window: window))
            settle(host)
            XCTAssertEqual(try capture(host), before)
        }
    }

    private func settle(_ view: NSView, for duration: TimeInterval = 0.03) {
        view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: duration))
        view.layoutSubtreeIfNeeded()
    }

    private func event(_ type: NSEvent.EventType, window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
    }

    private func descendants<T: NSView>(_ type: T.Type, in root: NSView) -> [T] {
        (root as? T).map { [$0] } ?? root.subviews.flatMap { descendants(type, in: $0) }
    }

    private func capture(_ view: NSView) throws -> Data {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func export(_ data: Data, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["STATUS_TRIO_PR_SCREENSHOTS_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name))
    }

    private func makeLocalization(preferredLanguages: [String] = ["en"]) throws -> Localization {
        let suite = "DeviceNameHoverRevealTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { TestUserDefaults.removeSuite(named: suite) }
        return Localization(defaults: defaults, preferredLanguages: preferredLanguages)
    }
}
