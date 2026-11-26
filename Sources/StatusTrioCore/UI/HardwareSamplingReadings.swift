import SwiftUI

struct HardwareSamplingReadings: View {
    @ObservedObject var observable: HardwareMonitorObservable
    let capacity: DiskCapacityReading?
    @Binding var showsDiskDetails: Bool
    let backgroundStyle: PanelBackgroundStyle
    @EnvironmentObject private var localization: Localization

    var body: some View {
        let snapshot = observable.summarySnapshot
        let cards = HardwareSamplingSummary.cards(snapshot: snapshot, capacity: capacity, localization: localization)
        let readings = HardwareSamplingSummary.readings(snapshot: snapshot, localization: localization)
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(cards) { card in
                    if card.id == .ssd {
                        Button { showsDiskDetails = true } label: {
                            HardwareSamplingRingCard(card: card)
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(card.label)
                        .accessibilityValue(card.accessibilityValue)
                        .cascadingSubmenu(isPresented: $showsDiskDetails, backgroundStyle: backgroundStyle) {
                            HardwareSamplingDiskDetails(observable: observable, capacity: capacity,
                                                        onBack: { showsDiskDetails = false })
                        }
                    } else {
                        HardwareSamplingRingCard(card: card)
                    }
                }
            }

            HStack(spacing: 0) {
                ForEach(readings) { reading in
                    if reading.id != readings.first?.id {
                        Rectangle()
                            .fill(.primary.opacity(0.10))
                            .frame(width: 1, height: 13)
                    }
                    readingCell(reading)
                }
            }
            .frame(height: 24)
            .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localization.string(.hardwareMonitorTitle))
    }

    private func readingCell(_ reading: HardwareSamplingSummary.Reading) -> some View {
        HStack(spacing: 3) {
            Image(systemName: reading.symbol)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(reading.value)
                .font(.caption2.monospacedDigit())
                .opacity(reading.isStale ? 0.55 : 1)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.label)
        .accessibilityValue(reading.accessibilityValue)
        .help("\(reading.label) · \(reading.accessibilityValue)")
    }
}

private struct HardwareSamplingRingCard: View {
    let card: HardwareSamplingSummary.Card
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var tint: Color {
        switch card.id {
        case .cpu: .blue
        case .gpu: .purple
        case .ram: .green
        case .ssd: .orange
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .ringStroke(.primary.opacity(0.13))
                if let fraction = card.fraction, fraction > 0 {
                    Circle()
                        .trim(from: 0, to: 0.75 * fraction)
                        .ringStroke(tint)
                }
                VStack(spacing: 1) {
                    Text(card.value)
                        .font(.caption.weight(.semibold).monospacedDigit())
                    if !card.subtitle.isEmpty {
                        Text(card.subtitle)
                            .font(.system(size: 8).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 6)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .frame(width: 48, height: 48)
            .opacity(card.isStale ? 0.55 : 1)

            Text(card.title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 70)
        .background(.primary.opacity(reduceTransparency ? 0.13 : 0.065), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.label)
        .accessibilityValue(card.accessibilityValue)
    }
}

private extension Shape {
    func ringStroke(_ style: some ShapeStyle) -> some View {
        stroke(style, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(135))
            .padding(2)
    }
}
