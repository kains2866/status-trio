import SwiftUI

struct HardwareSamplingDiskDetails: View {
    @ObservedObject var observable: HardwareMonitorObservable
    let capacity: DiskCapacityReading?
    let onBack: () -> Void
    @EnvironmentObject private var localization: Localization

    var body: some View {
        let snapshot = observable.summarySnapshot
        let detail = snapshot.diskDetail
        let title = localization.string(.hardwareDetailTitleDisk)
        VStack(alignment: .leading, spacing: 12) {
            NavigationBackRow(accessibilityLabel: localization.string(.commonBack),
                              title: title, action: onBack)

            VStack(alignment: .leading, spacing: 4) {
                Text(localization.string(.hardwareMonitorDisk))
                    .font(.caption.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                rates(read: snapshot.diskRead.value, write: snapshot.diskWrite.value)
            }

            if let detail, !detail.volumes.isEmpty {
                ForEach(detail.volumes) { volume in
                    let speed = detail.volumeSpeeds[volume.mountPath]
                    volumeCard(name: volume.name, total: volume.totalBytes, used: volume.usedBytes,
                               free: volume.freeBytes, fraction: volume.usedFraction, speed: speed)
                }
            } else if let capacity = detail?.capacity ?? capacity {
                volumeCard(name: nil, total: capacity.totalBytes, used: capacity.usedBytes, free: capacity.freeBytes,
                           fraction: capacity.usedFraction, speed: nil)
            } else {
                Text(localization.string(detail == nil ? .hardwareMonitorCollecting : .hardwareMonitorUnavailable))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func volumeCard(name: String?, total: UInt64, used: UInt64, free: UInt64, fraction: Double,
                            speed: DiskThroughputReading?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "internaldrive")
                    .accessibilityHidden(true)
                if let name {
                    Text(name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                }
                Text(HardwareSamplingSummary.capacityText(total))
                    .monospacedDigit()
            }
            .font(.callout.weight(.medium))

            ProgressView(value: min(1, fraction))
                .tint(.orange)
                .accessibilityHidden(true)

            HStack(spacing: 8) {
                metric(.hardwareDetailUsedSpace, value: HardwareSamplingSummary.capacityText(used))
                metric(.hardwareDetailFreeSpace, value: HardwareSamplingSummary.capacityText(free))
            }
            if name != nil {
                rates(read: speed?.readBytesPerSecond, write: speed?.writeBytesPerSecond)
            }
        }
        .padding(9)
        .background(.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    private func rates(read: Double?, write: Double?) -> some View {
        HStack(spacing: 8) {
            metric(.hardwareMonitorDiskRead, value: HardwareSamplingSummary.rateText(read))
            metric(.hardwareMonitorDiskWrite, value: HardwareSamplingSummary.rateText(write))
        }
    }

    private func metric(_ key: LocalizationKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(localization.string(key))
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localization.string(key))
        .accessibilityValue(value)
    }
}
