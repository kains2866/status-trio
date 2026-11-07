import XCTest
@testable import StatusTrioCore

@MainActor
final class PerDeviceAudioSettingsTests: XCTestCase {
    func testNewSettingsUseThreeDevicesForBothAudioSections() throws {
        let suite = "PerDeviceAudioSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.visibleOutputDeviceLimit, 3)
        XCTAssertEqual(settings.visibleInputDeviceLimit, 3)
    }

    func testExistingExplicitLimitsAndShowAllPreferencesAreRetained() throws {
        let suite = "PerDeviceAudioSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(7, forKey: SettingsStore.maxVisibleOutputDevicesDefaultsKey)
        defaults.set(2, forKey: SettingsStore.maxVisibleInputDevicesDefaultsKey)
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.visibleOutputDeviceLimit, 7)
        XCTAssertEqual(settings.visibleInputDeviceLimit, 2)
        settings.alwaysShowsAllOutputDevices = true
        settings.alwaysShowsAllInputDevices = true
        XCTAssertNil(settings.visibleOutputDeviceLimit)
        XCTAssertNil(settings.visibleInputDeviceLimit)
    }
}
