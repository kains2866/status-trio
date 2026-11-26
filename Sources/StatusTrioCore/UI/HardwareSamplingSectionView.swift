import Combine
import SwiftUI

struct HardwareSamplingSectionView: View {
    let store: SystemStatusStore
    @ObservedObject var settings: SettingsStore
    @StateObject private var service = HardwareMetricsService()
    @State private var isSampling = false
    @State private var showsDiskDetails = false
    @State private var capacity: DiskCapacityReading?

    var body: some View {
        HardwareSamplingReadings(observable: service.observable, capacity: capacity,
                                 showsDiskDetails: $showsDiskDetails, backgroundStyle: settings.panelBackgroundStyle)
            .onReceive(store.$isPopoverVisible.removeDuplicates()
                .combineLatest(store.$isDisplayAsleep.removeDuplicates())) { visible, asleep in
                updateSampling(visible: visible, asleep: asleep)
            }
            .onChange(of: showsDiskDetails) { showsDetails in
                let wantsDiskDetails = showsDetails && isSampling
                service.setDetailDemand(wantsDiskDetails ? .disk : nil)
                if wantsDiskDetails {
                    service.forceRefresh()
                }
            }
            .onChange(of: settings.hardwareRefreshIntervals) { _ in
                service.forceRefresh()
            }
            .task(id: isSampling) {
                guard isSampling else { return }
                let reading = await Task.detached(priority: .utility) {
                    DiskCapacityReader.read()
                }.value
                if !Task.isCancelled, isSampling {
                    capacity = reading
                }
            }
            .onDisappear { stopSampling() }
    }

    private func updateSampling(visible: Bool, asleep: Bool) {
        if asleep {
            service.sleep()
        }
        guard visible, !asleep else {
            stopSampling()
            return
        }
        isSampling = true
        if service.isAsleep {
            service.wake()
        }
        service.panelCadenceProvider = { [weak settings] group in
            TimeInterval(settings?.hardwareRefreshSeconds(for: group) ?? group.defaultSeconds)
        }
        service.begin(.panel, metrics: HardwareMetricsService.hardwareSummaryMetricIDs)
    }

    private func stopSampling() {
        isSampling = false
        showsDiskDetails = false
        capacity = nil
        service.setDetailDemand(nil)
        service.end(.panel)
    }
}
