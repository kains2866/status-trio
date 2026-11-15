import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class RedVolumeFooterTests: XCTestCase {
    func testMutedOptionFillsEntireFooterRedRegardlessOfHiddenScalar() {
        for style in VolumeDisplayStyle.allCases {
            let options = VolumeIconOptions(displayStyle: style, ringStrokeScale: 1.5,
                                            showsRedWhenMuted: true)
            for scalar: Double? in [nil, .nan, .infinity, -1, 0, 0.4, 1] {
                let scene = scene(scalar: scalar, muted: true, options: options)
                XCTAssertEqual(scene.footer, fullRedFooter(style: style, strokeScale: 1.5))
                XCTAssertTrue(scene.chromaticRegions.contains(.footerFill))
            }
        }
    }

    func testZeroOptionRequiresAnExactlyZeroFiniteUnmutedScalar() {
        for style in VolumeDisplayStyle.allCases {
            let options = VolumeIconOptions(displayStyle: style, showsRedWhenZero: true)
            for scalar in [0.0, -0.0] {
                XCTAssertEqual(scene(scalar: scalar, options: options).footer,
                               fullRedFooter(style: style))
            }
            for scalar: Double? in [nil, .nan, .infinity, -.infinity, -1, 0.00001, 0.4, 1] {
                XCTAssertNotEqual(scene(scalar: scalar, options: options).footer?.colorRole, .volumeAlert,
                                  "scalar=\(String(describing: scalar))")
            }
            XCTAssertNotEqual(scene(scalar: 0, muted: true, options: options).footer?.colorRole, .volumeAlert)
        }
    }

    func testOptionsRemainIndependentAndDisabledByDefault() {
        for style in VolumeDisplayStyle.allCases {
            let defaultOptions = VolumeIconOptions(displayStyle: style)
            XCTAssertNotEqual(scene(scalar: 0, options: defaultOptions).footer?.colorRole, .volumeAlert)
            XCTAssertNotEqual(scene(scalar: 0.5, muted: true, options: defaultOptions).footer?.colorRole, .volumeAlert)
            let muteOnly = VolumeIconOptions(displayStyle: style, showsRedWhenMuted: true)
            XCTAssertNotEqual(scene(scalar: 0, options: muteOnly).footer?.colorRole, .volumeAlert)
            let both = VolumeIconOptions(displayStyle: style, showsRedWhenMuted: true, showsRedWhenZero: true)
            XCTAssertEqual(scene(scalar: 0, muted: true, options: both).footer, fullRedFooter(style: style))
            XCTAssertEqual(scene(scalar: 0, options: both).footer, fullRedFooter(style: style))
        }
    }

    func testRedOverridesBluetoothTintAndReturnsToNormalAfterUnmuting() {
        for style in VolumeDisplayStyle.allCases {
            let options = VolumeIconOptions(displayStyle: style, showsRedWhenMuted: true, showsRedWhenZero: true)
            XCTAssertEqual(scene(scalar: 0.5, muted: true, options: options, bluetooth: true).footer,
                           fullRedFooter(style: style))
            XCTAssertEqual(scene(scalar: 0, options: options, bluetooth: true).footer,
                           fullRedFooter(style: style))
            XCTAssertEqual(scene(scalar: 0.5, options: options, bluetooth: true).footer?.colorRole, .bluetooth)
            XCTAssertEqual(scene(scalar: 0.5, options: options).footer?.colorRole, .primary)
        }
    }

    func testRedFooterRendersOnBothSurfacesIndependentlyOfBatteryColors() throws {
        for style in VolumeDisplayStyle.allCases {
            let mapped = scene(scalar: 0.5, muted: true,
                               options: VolumeIconOptions(displayStyle: style, showsRedWhenMuted: true))
            let footerOnly = IconSceneState(footer: mapped.footer,
                statusColors: BatteryStatusColors(critical: .preset(.sky)))
            // The legacy critical role with an explicit red baseline verifies
            // the new role without depending on device RGB conversion.
            let referenceFooter: FooterState = switch style {
            case .dots: .dots(DotsState(count: 4, activeCount: 4, color: .critical,
                                       strokeScale: VolumeIconOptions.defaultRingStrokeScale))
            case .arc: .arc(ArcState(progress: 1, color: .critical,
                                    strokeScale: VolumeIconOptions.defaultRingStrokeScale))
            }
            let reference = IconSceneState(footer: referenceFooter)
            for dark in [false, true] {
                let environment = StatusIconRenderEnvironment(size: 64, scale: 2,
                    foreground: CGColor(gray: dark ? 1 : 0, alpha: 1),
                    criticalColor: CGColor(red: 1, green: 59.0 / 255, blue: 48.0 / 255, alpha: 1))
                let image = try XCTUnwrap(StatusIconRenderer.render(scene: footerOnly,
                    environment: environment))
                let expected = try XCTUnwrap(StatusIconRenderer.render(scene: reference, environment: environment))
                XCTAssertTrue(try PixelBuffer(image: image).bytes.elementsEqual(PixelBuffer(image: expected).bytes))
            }
            for background in DockIconBackgroundStyle.allCases {
                let image = try XCTUnwrap(DockIconRenderer.image(scene: footerOnly, backgroundStyle: background, pixelLength: 256))
                let raster = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
                // Dock supplies its own semantic palette. It must preserve the
                // same fixed red when the battery's critical color is changed.
                let expected = try XCTUnwrap(DockIconRenderer.image(scene: IconSceneState(footer: mapped.footer),
                    backgroundStyle: background, pixelLength: 256))
                let expectedRaster = try XCTUnwrap(expected.cgImage(forProposedRect: nil, context: nil, hints: nil))
                XCTAssertTrue(try PixelBuffer(image: raster).bytes.elementsEqual(PixelBuffer(image: expectedRaster).bytes))
            }
        }
    }

    func testSettingsImmediatelyDeliverSharedRedSceneAndInvalidateBothSurfaceKeys() throws {
        for muted in [false, true] {
            let harness = try AppIconControllerHarness(initialPlacement: .both,
                initialVolume: VolumeStatus(scalar: muted ? 0.5 : 0, isMuted: muted, deviceName: "Output"),
                snapshotScheduler: ManualIconPresentationScheduler())
            defer { harness.cleanUp() }
            harness.controller.start()
            harness.controller.flushPendingPresentationForTesting()
            let baseline = harness.iconPresentation.output.scene
            let oldDockKey = DockIconRenderKey(scene: baseline, backgroundStyle: .dark, pixelLength: 128)
            let oldMenuKey = StatusBarRenderKey(scene: baseline, iconSize: 28, backingScale: 2,
                                              appearanceName: "dark", phase: nil)
            if muted {
                harness.settings.showsRedVolumeWhenMuted = true
            } else {
                harness.settings.showsRedVolumeWhenZero = true
            }
            let redScene = harness.iconPresentation.output.scene
            XCTAssertEqual(redScene.footer, fullRedFooter(style: .dots))
            harness.controller.flushPendingPresentationForTesting()
            XCTAssertEqual(harness.log.lastScene, redScene)
            XCTAssertNotEqual(oldDockKey, DockIconRenderKey(scene: redScene, backgroundStyle: .dark, pixelLength: 128))
            XCTAssertNotEqual(oldMenuKey, StatusBarRenderKey(scene: redScene, iconSize: 28, backingScale: 2,
                                                           appearanceName: "dark", phase: nil))
        }
    }

    private func fullRedFooter(style: VolumeDisplayStyle, strokeScale: Double = VolumeIconOptions.defaultRingStrokeScale) -> FooterState {
        switch style {
        case .dots: .dots(DotsState(count: 4, activeCount: 4, color: .volumeAlert, strokeScale: strokeScale))
        case .arc: .arc(ArcState(progress: 1, color: .volumeAlert, strokeScale: strokeScale))
        }
    }

    private func scene(scalar: Double?, muted: Bool = false, options: VolumeIconOptions, bluetooth: Bool = false) -> IconSceneState {
        let snapshot = StatusSnapshot(battery: .placeholder, wifi: .placeholder,
            volume: VolumeStatus(scalar: scalar, isMuted: muted, deviceName: "Output",
                                 currentDevice: bluetooth ? PresentationFixtures.bluetoothDevice : nil))
        return IconPresentationMapper.scene(
            inputs: IconPresentationInputs(snapshot: snapshot, audioIcon: nil),
            configuration: IconPresentationConfiguration(battery: .standard, connection: .standard,
                volume: options, bluetooth: BluetoothAudioIconOptions(usesVolumeColor: true)))
    }
}
