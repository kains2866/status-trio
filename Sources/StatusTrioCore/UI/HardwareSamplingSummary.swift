import Foundation

@MainActor
enum HardwareSamplingSummary {
    struct Card: Identifiable {
        enum ID: String {
            case cpu, gpu, ram, ssd
        }

        let id: ID
        let label: String
        let fraction: Double?
        let value: String
        let subtitle: String
        let accessibilityValue: String
        let isStale: Bool

        var title: String { id.rawValue.uppercased() }
    }

    struct Reading: Identifiable {
        let id: LocalizationKey
        let symbol: String
        let label: String
        let value: String
        let accessibilityValue: String
        let isStale: Bool
    }

    private static let dash = "—"

    static func cards(snapshot: HardwareMetricsSnapshot, capacity: DiskCapacityReading?,
                      localization: Localization) -> [Card] {
        let fraction = capacity.map { min(1, $0.usedFraction) }
        let percent = percentText(fraction, localization: localization)
        let total = capacity.map { capacityText($0.totalBytes) }
        return [
            usageCard(.cpu, label: .hardwareMonitorCPU, sample: snapshot.cpuUsage,
                      temperature: snapshot.cpuTemperature, localization: localization),
            usageCard(.gpu, label: .hardwareMonitorGPU, sample: snapshot.gpuUsage,
                      temperature: snapshot.gpuTemperature, localization: localization),
            usageCard(.ram, label: .hardwareMonitorMemory, sample: snapshot.memoryUsage,
                      temperature: nil, localization: localization),
            Card(id: .ssd, label: "SSD", fraction: fraction, value: percent, subtitle: total ?? dash,
                 accessibilityValue: total.map { "\(percent), \($0)" }
                    ?? localization.string(.hardwareMonitorUnavailable), isStale: false),
        ]
    }

    static func readings(snapshot: HardwareMetricsSnapshot, localization: Localization) -> [Reading] {
        let read = snapshot.diskRead
        let write = snapshot.diskWrite
        let diskRate = diskThroughput(read: read, write: write)
        let diskValue = rateText(diskRate)
        let diskIsStale = diskRate != nil && read.availability == .stale
        let diskStatus = diskRate == nil ? localization.string(availabilityKey(visibleValue(read) == nil ? read : write)) : diskValue
        let fan = snapshot.averageFanSample
        let fanText = visibleValue(fan).map {
            localization.format(.hardwareMonitorRPM, $0.formatted(.number.precision(.fractionLength(0))
                .locale(localization.resolvedLanguage.locale)))
        } ?? (fan.metadata.isFanless ? localization.string(.hardwareMonitorFanless) : dash)

        return [
            reading(.hardwareMonitorDownload, symbol: "arrow.down", sample: snapshot.networkDownload,
                    value: rateText(visibleValue(snapshot.networkDownload)), localization: localization),
            reading(.hardwareMonitorUpload, symbol: "arrow.up", sample: snapshot.networkUpload,
                    value: rateText(visibleValue(snapshot.networkUpload)), localization: localization),
            reading(.hardwareMonitorFanAverage, symbol: "fanblades", sample: fan,
                    value: fanText, localization: localization),
            Reading(id: .hardwareMonitorDisk, symbol: "internaldrive", label: localization.string(.hardwareMonitorDisk),
                    value: diskValue, accessibilityValue: withStaleStatus(diskStatus, isStale: diskIsStale,
                                                                        localization: localization),
                    isStale: diskIsStale),
        ]
    }

    static func diskThroughput(read: HardwareMetricSample, write: HardwareMetricSample) -> Double? {
        guard read.sampledAt == write.sampledAt, read.availability == write.availability,
              let readValue = visibleValue(read), let writeValue = visibleValue(write),
              (readValue + writeValue).isFinite else { return nil }
        return readValue + writeValue
    }

    static func rateText(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return dash }
        let bytes = UInt64(exactly: value.rounded(.down)) ?? .max
        return "\(capacityText(bytes))/s"
    }

    static func capacityText(_ bytes: UInt64) -> String {
        Int64(clamping: bytes).formatted(.byteCount(style: .decimal, spellsOutZero: false))
    }

    private static func usageCard(_ id: Card.ID, label: LocalizationKey, sample: HardwareMetricSample,
                                  temperature: HardwareMetricSample?, localization: Localization) -> Card {
        let fraction = visibleValue(sample).map { min(1, $0 / 100) }
        let value = percentText(fraction, localization: localization)
        let subtitle = temperature.flatMap { visibleValue($0) }.map {
            Measurement(value: $0, unit: UnitTemperature.celsius).formatted(
                .measurement(width: .narrow, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
                    .locale(localization.resolvedLanguage.locale)
            )
        }
        let usageText = accessibleText(value, sample: sample, localization: localization)
        let accessibilityValue = [usageText, subtitle].compactMap { $0 }.joined(separator: ", ")
        let localizedLabel = localization.string(label)
        return Card(id: id, label: localizedLabel, fraction: fraction, value: value,
                    subtitle: subtitle ?? (temperature == nil ? "" : dash),
                    accessibilityValue: accessibilityValue, isStale: sample.availability == .stale)
    }

    private static func percentText(_ fraction: Double?, localization: Localization) -> String {
        fraction?.formatted(.percent.precision(.fractionLength(0)).locale(localization.resolvedLanguage.locale)) ?? dash
    }

    private static func reading(_ key: LocalizationKey, symbol: String, sample: HardwareMetricSample,
                                value: String, localization: Localization) -> Reading {
        Reading(id: key, symbol: symbol, label: localization.string(key), value: value,
                accessibilityValue: accessibleText(value, sample: sample, localization: localization),
                isStale: sample.availability == .stale)
    }

    private static func accessibleText(_ value: String, sample: HardwareMetricSample, localization: Localization) -> String {
        guard visibleValue(sample) != nil else { return localization.string(availabilityKey(sample)) }
        return withStaleStatus(value, isStale: sample.availability == .stale, localization: localization)
    }

    private static func withStaleStatus(_ value: String, isStale: Bool, localization: Localization) -> String {
        isStale ? "\(value), \(localization.string(.hardwareMonitorStale))" : value
    }

    private static func visibleValue(_ sample: HardwareMetricSample) -> Double? {
        guard sample.availability == .measured || sample.availability == .stale,
              let value = sample.value, value.isFinite, value >= 0 || sample.unit == .celsius else { return nil }
        return value
    }

    private static func availabilityKey(_ sample: HardwareMetricSample) -> LocalizationKey {
        switch sample.availability {
        case .collecting: .hardwareMonitorCollecting
        case .unsupported: sample.metadata.isFanless ? .hardwareMonitorFanless : .hardwareMonitorUnsupported
        case .stale: .hardwareMonitorStale
        case .temporarilyUnavailable, .measured: .hardwareMonitorUnavailable
        }
    }
}
