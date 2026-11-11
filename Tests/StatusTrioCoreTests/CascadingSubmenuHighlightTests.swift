import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class CascadingSubmenuHighlightTests: XCTestCase {
    func testHighlightAddsClearanceWithoutMovingContentOrChangingLayout() throws {
        for scale in [CGFloat(1), CGFloat(2)] {
            for dark in [false, true] {
                let snapshot = try capture(dark: dark, presented: true, scale: scale)
                let plain = try capture(dark: dark, presented: false, scale: scale)
                XCTAssertEqual(snapshot.bitmap.pixelsWide, Int(140 * scale))
                XCTAssertEqual(snapshot.bitmap.pixelsHigh, Int(80 * scale))
                XCTAssertEqual(snapshot.bitmap.size, NSSize(width: 140, height: 80))
                XCTAssertEqual(snapshot.size.width, 140, accuracy: 0.1)
                XCTAssertEqual(snapshot.size.height, 80, accuracy: 0.1)
                // Original content occupies x=20...120, y=20...60. Highlight must
                // extend beyond it; the existing summary alignment stays fixed.
                let edge = try color(snapshot.bitmap, x: 15, y: 40)
                let backdrop = dark ? 0.0 : 1.0
                XCTAssertGreaterThan(abs(edge.redComponent - backdrop), 0.03,
                                     "the highlight needs horizontal breathing room")
                let top = try color(snapshot.bitmap, x: 70, y: 16)
                XCTAssertGreaterThan(abs(top.redComponent - backdrop), 0.03,
                                     "the highlight needs vertical breathing room")
                // This entire 1x pixel is outside the 12pt arc; (14,18) straddles
                // it at 1x, even though its first 2x subpixel is fully clear.
                let corner = try color(snapshot.bitmap, x: 13, y: 18)
                XCTAssertEqual(corner.redComponent, backdrop, accuracy: 0.02,
                               "larger rounded corners must leave the outer corner clear (\(scale)x, dark=\(dark))")
                let nearCorner = try color(snapshot.bitmap, x: 16, y: 20)
                XCTAssertGreaterThan(abs(nearCorner.redComponent - backdrop), 0.03,
                                     "the rounded highlight must still fill near the corner")
                let content = try color(snapshot.bitmap, x: 22, y: 40)
                let original = try color(plain.bitmap, x: 22, y: 40)
                XCTAssertEqual(content.redComponent, original.redComponent, accuracy: 0.01)
                XCTAssertEqual(content.greenComponent, original.greenComponent, accuracy: 0.01)
                XCTAssertEqual(content.blueComponent, original.blueComponent, accuracy: 0.01)
            }
        }
    }

    func testClosedEntryHasNoHighlightInItsExtraClearance() throws {
        let snapshot = try capture(dark: false, presented: false)
        XCTAssertEqual(try color(snapshot.bitmap, x: 15, y: 40).redComponent, 1, accuracy: 0.01)
    }

    func testBatterySummaryPreservesPanelWidthAndTextLayoutWhenHighlighted() throws {
        let suite = "CascadingSubmenuHighlightTests.Battery.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["zh-Hans"])
        var state = PanelPresentationMapper.battery(
            BatteryStatus(rawPercentage: 72, isPresent: true, isCharging: false,
                          isLowPowerMode: true, isConnectedToPower: false), localization: localization)
        state.powerInfoBar = PowerInfoBarState(items: [
            PowerInfoBarItem(kind: .inputDisconnected, value: "未接电源"),
            PowerInfoBarItem(kind: .batteryDischarging, value: "9.8 W"),
            PowerInfoBarItem(kind: .system, value: "9.8 W")
        ])
        for dark in [false, true] {
            var sizes: [NSSize] = []
            for presented in [false, true] {
                let host = NSHostingView(rootView: BatteryStatusView(
                    state: state, onOpenBatteryDetails: {}, onOpenBatterySettings: {})
                    .cascadingSubmenu(isPresented: .constant(presented)) { Text("Details") }
                    .padding(14).frame(width: 330)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environmentObject(localization)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .transaction { $0.animation = nil; $0.disablesAnimations = true })
                host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                host.frame = NSRect(origin: .zero, size: host.fittingSize)
                let window = NSWindow(contentRect: host.frame, styleMask: .borderless,
                                      backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                defer { window.contentView = nil; window.close() }
                host.layoutSubtreeIfNeeded()
                sizes.append(host.bounds.size)
                XCTAssertEqual(host.bounds.width, 330, accuracy: 0.1)
                if presented, let output = ProcessInfo.processInfo.environment["STATUS_TRIO_HOVER_SNAPSHOTS"] {
                    let directory = URL(fileURLWithPath: output, isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    try png.write(to: directory.appendingPathComponent("battery-hover-\(dark ? "dark" : "light").png"))
                }
            }
            XCTAssertEqual(sizes[0], sizes[1], "hover must not move the summary text or neighboring sections")
        }
    }

    private func capture(dark: Bool, presented: Bool, scale: CGFloat? = nil) throws -> (bitmap: NSBitmapImageRep, size: NSSize) {
        let suite = "CascadingSubmenuHighlightTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let host = NSHostingView(rootView:
            Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1).frame(width: 100, height: 40)
                .cascadingSubmenu(isPresented: .constant(presented)) { Text("Details") }
                .padding(20)
                .background(dark ? Color.black : Color.white)
                .environmentObject(localization)
                .environment(\.colorScheme, dark ? .dark : .light)
                .transaction { $0.animation = nil; $0.disablesAnimations = true })
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        let bitmap: NSBitmapImageRep
        if let scale {
            bitmap = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(host.bounds.width * scale),
                pixelsHigh: Int(host.bounds.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = host.bounds.size
        } else {
            bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return (bitmap, host.bounds.size)
    }

    private func color(_ bitmap: NSBitmapImageRep, x: CGFloat, y: CGFloat) throws -> NSColor {
        let scaleX = CGFloat(bitmap.pixelsWide) / 140
        let scaleY = CGFloat(bitmap.pixelsHigh) / 80
        return try XCTUnwrap(bitmap.colorAt(x: Int(x * scaleX), y: Int(y * scaleY))?.usingColorSpace(.sRGB))
    }
}
