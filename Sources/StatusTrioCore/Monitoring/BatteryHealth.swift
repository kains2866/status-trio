import Foundation

/// Best-effort, read-only battery health telemetry taken from the same
/// on-demand snapshot the details page already reads. Every field is optional:
/// a missing or unverifiable value stays `nil` instead of
/// being filled in with a fabricated zero. No new permission, helper, daemon,
/// or sampling loop is involved.
struct BatteryHealthSnapshot: Equatable, Sendable {
    enum Condition: Equatable, Sendable {
        case normal
        case service
    }

    var designCapacityMAh: Int?
    var maximumCapacityMAh: Int?
    /// The percentage macOS reports as Maximum Capacity (`MaxCapacity`), which
    /// is normalised differently from the raw capacity ratio below.
    var maximumCapacityPercent: Double?
    /// Estimated from measured capacities, not the value macOS shows under
    /// Battery Health. Kept as a fallback when the system percentage is absent.
    var healthPercent: Double?
    /// `nil` means the system exposed no explicit condition evidence.
    var condition: Condition?

    init(
        designCapacityMAh: Int? = nil,
        maximumCapacityMAh: Int? = nil,
        maximumCapacityPercent: Double? = nil,
        healthPercent: Double? = nil,
        condition: Condition? = nil
    ) {
        self.designCapacityMAh = designCapacityMAh
        self.maximumCapacityMAh = maximumCapacityMAh
        self.maximumCapacityPercent = maximumCapacityPercent
        self.healthPercent = healthPercent
        self.condition = condition
    }
}

/// Pure parsing for the health snapshot so each source and unit rule can be
/// tested without an IORegistry or SMC read.
enum BatteryHealthParser {
    struct Capacity: Equatable, Sendable {
        var designMAh: Int? = nil
        var maximumMAh: Int? = nil
        var maximumPercent: Double? = nil
        var healthPercent: Double? = nil
    }

    /// Capacities are paired inside one dictionary only. A nested telemetry
    /// value is never divided by an unrelated top-level value, and the
    /// percentage-valued `MaxCapacity` key is never read as milliamp hours.
    static func parseCapacity(registry: [String: Any]) -> Capacity {
        if let batteryData = registry["BatteryData"] as? [String: Any],
           let capacity = capacities(in: batteryData) {
            return capacity
        }
        return capacities(in: registry) ?? Capacity()
    }

    /// Maximum-capacity keys are tried in measured-then-reported order. The
    /// design capacity must come from the same dictionary as the maximum.
    private static func capacities(in values: [String: Any]) -> Capacity? {
        let design = milliampHours(values["DesignCapacity"])
        let maximum = ["AppleRawMaxCapacity", "FullChargeCapacity", "NominalChargeCapacity"]
            .compactMap { milliampHours(values[$0]) }
            .first
        let maximumPercent = integerValue(values["MaxCapacity"])
            .flatMap { (1...100).contains($0) ? Double($0) : nil }
        guard design != nil || maximum != nil || maximumPercent != nil else { return nil }
        return Capacity(
            designMAh: design,
            maximumMAh: maximum,
            maximumPercent: maximumPercent,
            healthPercent: healthPercent(maximumMAh: maximum, designMAh: design)
        )
    }

    /// A missing health value or a zero failure bitmask does not prove the
    /// battery is healthy. Service evidence wins over a simultaneous Good value.
    static func condition(registry: [String: Any]) -> BatteryHealthSnapshot.Condition? {
        var sources = [registry]
        if let batteryData = registry["BatteryData"] as? [String: Any] {
            sources.append(batteryData)
        }
        let conditions = sources.flatMap { source in
            [source["BatteryHealth"] as? String, source["BatteryHealthCondition"] as? String]
                .compactMap { $0 }
        }
        if sources.contains(where: {
            (integerValue($0["PermanentFailureStatus"]) ?? 0) > 0
        }) || conditions.contains(where: { ["Fair", "Poor", "Check Battery"].contains($0) }) {
            return .service
        }
        return conditions.contains("Good") ? .normal : nil
    }

    /// A capacity pair is only credible inside these bounds. An implausible
    /// ratio leaves health unknown while the raw capacities stay visible.
    static func healthPercent(maximumMAh: Int?, designMAh: Int?) -> Double? {
        guard let maximumMAh, let designMAh, designMAh > 0, maximumMAh > 0 else { return nil }
        let percent = Double(maximumMAh) / Double(designMAh) * 100
        // Below ~20% a "capacity" is almost certainly a different field
        // wearing the same name; above 150% it is not the same battery.
        guard percent.isFinite, (20...150).contains(percent) else { return nil }
        return percent
    }

    /// Battery capacities are whole milliamp hours. Booleans, fractional
    /// telemetry, and out-of-range values are rejected rather than truncated.
    static func milliampHours(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let raw = number.doubleValue
        // Apple's shipped Mac battery packs all fall inside this range; smaller
        // values are percentages or counters, and the Smart Battery 0xffff
        // unknown sentinel (65,535) is rejected by the upper bound. Bound the
        // Double before converting so hostile NSNumber values cannot trap.
        guard raw.isFinite, raw == raw.rounded(), (1_000...20_000).contains(raw) else { return nil }
        return Int(exactly: raw)
    }

    static func boolValue(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber else { return nil }
        switch number.doubleValue {
        case 0: return false
        case 1: return true
        default: return nil
        }
    }

    static func integerValue(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return Int(exactly: number.doubleValue)
    }
}
