import Foundation
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class HardwareSamplingSummaryTests: XCTestCase {
    func testCardsShowUsageInOrderAndKeepUnknownValuesDistinctFromZero() {
        let snapshot = HardwareMetricsSnapshot(samples: [
            .cpuUsage: .init(value: 0, unit: .percent, source: .mach, availability: .measured),
            .gpuUsage: .init(value: 42, unit: .percent, source: .ioAccelerator, availability: .stale),
            .memoryUsage: .init(value: 53, unit: .percent, source: .mach, availability: .measured),
        ])
        let cards = HardwareSamplingSummary.cards(snapshot: snapshot, capacity: nil, localization: Localization())

        XCTAssertEqual(cards.map(\.id), [.cpu, .gpu, .ram, .ssd])
        XCTAssertEqual(cards.map(\.fraction), [0, 0.42, 0.53, nil])
        XCTAssertEqual(cards.map(\.isStale), [false, true, false, false])
        XCTAssertEqual(cards.last?.value, "—")
    }

    func testSSDCardReportsStartupVolumeUsageAndCapacity() throws {
        let capacity = DiskCapacityReading(totalBytes: 512_000_000_000, freeBytes: 128_000_000_000,
                                           usedBytes: 384_000_000_000, fileSystem: "APFS", sampledAt: .now)
        let cards = HardwareSamplingSummary.cards(snapshot: .empty, capacity: capacity, localization: Localization())
        let ssd = try XCTUnwrap(cards.last)

        XCTAssertEqual(ssd.fraction, 0.75)
        XCTAssertEqual(ssd.subtitle, HardwareSamplingSummary.capacityText(capacity.totalBytes))
    }

    func testDiskThroughputRequiresBothDirectionsFromTheSameSample() {
        let date = Date()
        let read = HardwareMetricSample(value: 100, unit: .bytesPerSecond, sampledAt: date,
                                        source: .ioStorage, availability: .measured)
        var write = HardwareMetricSample(value: 50, unit: .bytesPerSecond, sampledAt: date,
                                         source: .ioStorage, availability: .measured)
        XCTAssertEqual(HardwareSamplingSummary.diskThroughput(read: read, write: write), 150)
        write.availability = .stale
        XCTAssertNil(HardwareSamplingSummary.diskThroughput(read: read, write: write))
        write.availability = .measured
        write.sampledAt = date.addingTimeInterval(-1)
        XCTAssertNil(HardwareSamplingSummary.diskThroughput(read: read, write: write))
    }

    func testSummaryFitsThePanelWithoutGrowingWhenReadingsArrive() throws {
        let observable = HardwareMonitorObservable()
        let localization = Localization()

        func renderHeight(capacity: DiskCapacityReading?) throws -> CGFloat {
            let renderer = ImageRenderer(content: HardwareSamplingReadings(
                observable: observable, capacity: capacity, showsDiskDetails: .constant(false),
                backgroundStyle: .systemDefault
            )
            .environmentObject(localization)
            .frame(width: 302))
            return try XCTUnwrap(renderer.nsImage).size.height
        }

        let initialHeight = try renderHeight(capacity: nil)
        let sample = HardwareMetricSample(value: 100, unit: .percent, sampledAt: .now,
                                          source: .mach, availability: .measured)
        observable.update(.init(samples: [.cpuUsage: sample, .gpuUsage: sample, .memoryUsage: sample]))
        let capacity = DiskCapacityReading(totalBytes: 512_000_000_000, freeBytes: 128_000_000_000,
                                           usedBytes: 384_000_000_000, fileSystem: "APFS", sampledAt: .now)

        XCTAssertLessThan(initialHeight, 110)
        XCTAssertEqual(try renderHeight(capacity: capacity), initialHeight)
    }
}
