import Foundation
import IOKit.ps
import XCTest
@testable import StatusTrioCore

final class BatteryHealthParserTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_555_974)
    private func state(connected: Bool = false, charging: Bool = false) -> BatteryPowerState {
        BatteryPowerState(BatteryStatus(rawPercentage: 80, isPresent: true,
                                       isCharging: charging, isLowPowerMode: false,
                                       isConnectedToPower: connected))
    }
    private var registry: [String: Any] {
        ["Voltage": 12_763, "Amperage": -1_705, "UpdateTime": now.timeIntervalSince1970,
         "ExternalConnected": false, "IsCharging": false, "CycleCount": 52]
    }

    // MARK: - Capacity pairing

    func testNestedBatteryDataCapacitiesWinAndUseTheSameDictionary() throws {
        let capacity = BatteryHealthParser.parseCapacity(registry: [
            "AppleRawMaxCapacity": 9_999, "DesignCapacity": 9_999,
            "BatteryData": [
                "AppleRawMaxCapacity": 8_413,
                "FullChargeCapacity": 8_413,
                "NominalChargeCapacity": 8_657,
                "DesignCapacity": 8_579,
                "MaxCapacity": 100
            ]
        ])
        XCTAssertEqual(capacity.designMAh, 8_579)
        XCTAssertEqual(capacity.maximumMAh, 8_413, "AppleRawMaxCapacity is the measured maximum")
        XCTAssertEqual(try XCTUnwrap(capacity.healthPercent), 8_413.0 / 8_579 * 100, accuracy: 0.000_001)
    }

    func testTopLevelCapacitiesAreTheFallbackWhenBatteryDataIsAbsent() {
        let capacity = BatteryHealthParser.parseCapacity(registry: [
            "AppleRawMaxCapacity": 8_413, "DesignCapacity": 8_579
        ])
        XCTAssertEqual(capacity.designMAh, 8_579)
        XCTAssertEqual(capacity.maximumMAh, 8_413)
        XCTAssertNotNil(capacity.healthPercent)
    }

    func testCapacityNeverMixesNestedAndTopLevelDictionaries() {
        // The nested dictionary has a design capacity but no maximum. Falling
        // back to the unrelated top-level maximum would fabricate a ratio.
        let capacity = BatteryHealthParser.parseCapacity(registry: [
            "BatteryData": ["DesignCapacity": 8_579],
            "AppleRawMaxCapacity": 9_000
        ])
        XCTAssertEqual(capacity.designMAh, 8_579)
        XCTAssertNil(capacity.maximumMAh)
        XCTAssertNil(capacity.healthPercent)
    }

    func testPercentageMaxCapacityIsNeverReadAsMilliampHours() {
        // MaxCapacity is a percentage on AppleSmartBattery; only explicit mAh
        // keys may feed the maximum capacity.
        let capacity = BatteryHealthParser.parseCapacity(registry: [
            "BatteryData": ["MaxCapacity": 100, "DesignCapacity": 8_579]
        ])
        XCTAssertEqual(capacity.designMAh, 8_579)
        XCTAssertNil(capacity.maximumMAh)
        XCTAssertNil(capacity.healthPercent)
    }

    func testFullChargeCapacityIsUsedWhenMeasuredMaximumIsMissing() throws {
        let capacity = BatteryHealthParser.parseCapacity(registry: [
            "BatteryData": ["FullChargeCapacity": 8_000, "DesignCapacity": 8_579]
        ])
        XCTAssertEqual(capacity.maximumMAh, 8_000)
        XCTAssertEqual(try XCTUnwrap(capacity.healthPercent), 8_000.0 / 8_579 * 100, accuracy: 0.000_001)
    }

    func testBooleanAndMalformedCapacityValuesAreRejected() {
        let booleans: [String: Any] = [
            "DesignCapacity": true,
            "BatteryData": ["DesignCapacity": true, "AppleRawMaxCapacity": NSNumber(value: true)]
        ]
        XCTAssertEqual(BatteryHealthParser.parseCapacity(registry: booleans),
                       BatteryHealthParser.Capacity())

        let malformed: [String: Any] = [
            "BatteryData": [
                "DesignCapacity": "8579",
                "AppleRawMaxCapacity": 8_413.5,
                "FullChargeCapacity": 0,
                "NominalChargeCapacity": -8_413,
                "MaxCapacity": 1_000_000
            ]
        ]
        XCTAssertEqual(BatteryHealthParser.parseCapacity(registry: malformed),
                       BatteryHealthParser.Capacity())
    }

    func testMissingFieldsAndEmptyRegistryReturnEmptyCapacity() {
        XCTAssertEqual(BatteryHealthParser.parseCapacity(registry: [:]), BatteryHealthParser.Capacity())
        XCTAssertEqual(BatteryHealthParser.parseCapacity(registry: ["CycleCount": 52]),
                       BatteryHealthParser.Capacity())
    }

    // MARK: - Health percentage

    func testHealthPercentageMatchesMeasuredCapacityRatio() throws {
        let percent = try XCTUnwrap(BatteryHealthParser.healthPercent(maximumMAh: 8_413, designMAh: 8_579))
        XCTAssertEqual(percent, 98.065_043, accuracy: 0.000_001)
    }

    func testHealthAboveOneHundredPercentIsKeptUnclampedWithinCredibleRange() throws {
        // A replaced battery can read above design capacity. The number is
        // telemetry, not a display target, so it is not silently clamped.
        let percent = try XCTUnwrap(BatteryHealthParser.healthPercent(maximumMAh: 8_700, designMAh: 8_579))
        XCTAssertEqual(percent, 101.410_421, accuracy: 0.000_001)
    }

    func testImplausibleHealthIsUnavailableWhileCapacitiesRemainValid() {
        XCTAssertNil(BatteryHealthParser.healthPercent(maximumMAh: 20_000, designMAh: 8_579))
        XCTAssertNil(BatteryHealthParser.healthPercent(maximumMAh: 1_500, designMAh: 10_000),
                     "A 15% ratio is more likely a different field than a real pack")
        XCTAssertNil(BatteryHealthParser.healthPercent(maximumMAh: 8_413, designMAh: 0))
        XCTAssertNil(BatteryHealthParser.healthPercent(maximumMAh: nil, designMAh: 8_579))
        let capacity = BatteryHealthParser.parseCapacity(registry: [
            "BatteryData": ["DesignCapacity": 8_579, "AppleRawMaxCapacity": 20_000]
        ])
        XCTAssertEqual(capacity.designMAh, 8_579)
        XCTAssertEqual(capacity.maximumMAh, 20_000)
        XCTAssertNil(capacity.healthPercent)
    }

    func testCapacityRejectsPercentageLikeAndSentinelNumbers() {
        for value in [1, 100, 499, 999, 20_001, 65_535, 100_001] {
            XCTAssertNil(BatteryHealthParser.milliampHours(NSNumber(value: value)), "\(value)")
        }
        XCTAssertNil(BatteryHealthParser.integerValue(NSNumber(value: true)))
        XCTAssertNil(BatteryHealthParser.boolValue(NSNumber(value: 2)))
        XCTAssertEqual(BatteryHealthParser.integerValue(NSNumber(value: 8_413)), 8_413)
    }

    func testExtremeTelemetryCannotOverflowIntegerConversion() {
        let values = [NSNumber(value: Double.greatestFiniteMagnitude), NSNumber(value: UInt64.max),
                      NSNumber(value: Double.nan), NSNumber(value: Double.infinity)]
        for value in values {
            XCTAssertNil(BatteryHealthParser.milliampHours(value))
            XCTAssertNil(BatteryHealthParser.integerValue(value))
        }
    }

    func testReportedMaximumCapacityReadsTheSystemPercentage() throws {
        let capacity = BatteryHealthParser.parseCapacity(registry: [
            "BatteryData": [
                "DesignCapacity": 8_579,
                "AppleRawMaxCapacity": 8_386,
                "MaxCapacity": 100
            ]
        ])
        XCTAssertEqual(capacity.maximumPercent, 100)
        XCTAssertEqual(try XCTUnwrap(capacity.healthPercent), 8_386.0 / 8_579 * 100, accuracy: 0.000_001)
    }

    func testBatteryConditionUsesOnlyExplicitSystemEvidence() {
        XCTAssertNil(BatteryHealthParser.condition(registry: [:]))
        XCTAssertNil(BatteryHealthParser.condition(registry: ["PermanentFailureStatus": "unknown"]))
        XCTAssertNil(BatteryHealthParser.condition(registry: ["PermanentFailureStatus": 0]))
        XCTAssertEqual(BatteryHealthParser.condition(registry: [
            "PermanentFailureStatus": 0, "BatteryHealth": "Poor"
        ]), .service)
        XCTAssertEqual(BatteryHealthParser.condition(registry: [
            "BatteryHealth": "Good", "BatteryData": ["BatteryHealthCondition": "Check Battery"]
        ]), .service)
        XCTAssertEqual(BatteryHealthParser.condition(registry: ["PermanentFailureStatus": 1]), .service)
        XCTAssertEqual(BatteryHealthParser.condition(registry: ["BatteryHealth": "Good"]), .normal)
        XCTAssertEqual(BatteryHealthParser.condition(registry: ["BatteryHealthCondition": "Check Battery"]), .service)
    }

}

extension BatteryHealthParserTests {
    func testHealthSurvivesUnavailablePowerAndIsAbsentWithoutBattery() {
        let values: [String: Any] = ["BatteryData": ["MaxCapacity": 97], "BatteryHealth": "Good"]
        let details = BatteryDetailsReader.parse(registry: values, adapterWatts: nil,
            remainingSeconds: -1, state: state(), now: now)
        XCTAssertEqual(details.health?.maximumCapacityPercent, 97)
        XCTAssertEqual(details.health?.condition, .normal)
        XCTAssertEqual(details.powerAvailability, .unavailable)
        let absent = BatteryPowerState(BatteryStatus(rawPercentage: nil, isPresent: false,
            isCharging: false, isLowPowerMode: false, isConnectedToPower: true))
        XCTAssertNil(BatteryDetailsReader.parse(registry: values, adapterWatts: nil,
            remainingSeconds: -1, state: absent, now: now).health)
    }
}
