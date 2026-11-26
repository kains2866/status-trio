import Combine
import SwiftUI

struct HardwareSamplingSectionView: View {
    let store: SystemStatusStore
    @ObservedObject var settings: SettingsStore
    @StateObject private var service = HardwareMetricsService()

    var body: some View {
        HardwareSamplingReadings(observable: service.observable)
            .onReceive(store.$isPopoverVisible.removeDuplicates()
                .combineLatest(store.$isDisplayAsleep.removeDuplicates())) { visible, asleep in
                updateSampling(visible: visible, asleep: asleep)
            }
            .onChange(of: settings.hardwareRefreshIntervals) { _ in
                service.forceRefresh()
            }
            .onDisappear {
                service.end(.panel)
            }
    }

    private func updateSampling(visible: Bool, asleep: Bool) {
        if asleep {
            service.sleep()
        }
        guard visible, !asleep else {
            service.end(.panel)
            return
        }
        if service.isAsleep {
            service.wake()
        }
        service.panelCadenceProvider = { [weak settings] group in
            TimeInterval(settings?.hardwareRefreshSeconds(for: group) ?? group.defaultSeconds)
        }
        service.begin(.panel, metrics: HardwareMetricsService.hardwareSummaryMetricIDs)
    }
}

private struct HardwareSamplingReadings: View {
    @ObservedObject var observable: HardwareMonitorObservable
    @EnvironmentObject private var localization: Localization

    var body: some View {
        let snapshot = observable.summarySnapshot
        VStack(alignment: .leading, spacing: 7) {
            Label(localization.string(.hardwareMonitorTitle), systemImage: PopupSection.hardware.systemImage)
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            reading(.hardwareMonitorCPU, snapshot.cpuUsage)
            reading(.hardwareMonitorGPU, snapshot.gpuUsage)
            reading(.hardwareMonitorMemory, snapshot.memoryUsage)
            reading(.hardwareMonitorTemperature, snapshot.cpuTemperature)
            reading(.hardwareMonitorGPUTemperature, snapshot.gpuTemperature)
            reading(.hardwareMonitorFanAverage, snapshot.averageFanSample)
            reading(.hardwareMonitorDownload, snapshot.networkDownload)
            reading(.hardwareMonitorUpload, snapshot.networkUpload)
            reading(.hardwareMonitorDiskRead, snapshot.diskRead)
            reading(.hardwareMonitorDiskWrite, snapshot.diskWrite)
        }
    }

    private func reading(_ title: LocalizationKey, _ sample: HardwareMetricSample) -> some View {
        LabeledContent(localization.string(title)) {
            Text(value(for: sample))
                .monospacedDigit()
                .foregroundStyle(sample.availability == .stale ? .tertiary : .secondary)
        }
        .font(.caption)
        .accessibilityLabel(localization.string(title))
        .accessibilityValue(
            sample.availability == .stale && sample.value != nil
                ? "\(value(for: sample)), \(localization.string(.hardwareMonitorStale))"
                : value(for: sample)
        )
    }

    private func value(for sample: HardwareMetricSample) -> String {
        guard let value = sample.value, value.isFinite else {
            return localization.string(availabilityKey(for: sample))
        }
        switch sample.unit {
        case .percent:
            return (value / 100).formatted(.percent.precision(.fractionLength(0)))
        case .celsius:
            return Measurement(value: value, unit: UnitTemperature.celsius)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
        case .rpm:
            return localization.format(.hardwareMonitorRPM, value.formatted(.number.precision(.fractionLength(0))))
        case .bytesPerSecond:
            let bytes = Measurement(value: value, unit: UnitInformationStorage.bytes)
                .formatted(.measurement(width: .abbreviated))
            return "\(bytes)/s"
        case .none:
            return value.formatted()
        }
    }

    private func availabilityKey(for sample: HardwareMetricSample) -> LocalizationKey {
        switch sample.availability {
        case .collecting: .hardwareMonitorCollecting
        case .unsupported: sample.metadata.isFanless ? .hardwareMonitorFanless : .hardwareMonitorUnsupported
        case .stale: .hardwareMonitorStale
        case .temporarilyUnavailable, .measured: .hardwareMonitorUnavailable
        }
    }
}
