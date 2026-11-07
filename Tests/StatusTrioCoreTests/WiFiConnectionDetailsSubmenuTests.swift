import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class WiFiConnectionDetailsSubmenuTests: XCTestCase {
    func testConnectionParametersNeverExpandInsideTheWiFiNetworkList() {
        let compact = measure(detailRowCount: 0, showsConnectionDetails: true, showsDetails: false)
        let withParameters = measure(detailRowCount: 20, showsConnectionDetails: true, showsDetails: false)
        let rememberedRoute = measure(detailRowCount: 20, showsConnectionDetails: true, showsDetails: true)
        XCTAssertEqual(withParameters.height, compact.height, accuracy: 1,
                       "the Wi-Fi child must show an entry instead of all connection parameters")
        XCTAssertEqual(rememberedRoute.height, compact.height, accuracy: 1,
                       "a remembered details route opens a side panel without growing the list")
    }

    func testUnavailableConnectionDetailsDoNotExposeAThirdLevelEntry() {
        let withoutDetails = measure(detailRowCount: 0, showsConnectionDetails: false, showsDetails: false)
        let restricted = measure(detailRowCount: 20, showsConnectionDetails: false, showsDetails: true)
        XCTAssertEqual(restricted.height, withoutDetails.height, accuracy: 1,
                       "permission-gated details must remain unavailable even for a remembered route")
    }

    private func measure(detailRowCount: Int, showsConnectionDetails: Bool, showsDetails: Bool) -> NSSize {
        let state = WiFiPanelState(
            detail: PanelDetailState(title: "Wi-Fi", rows: (0..<detailRowCount).map { index in
                PanelDetailRow(id: "parameter-\(index)", label: "Parameter \(index)", value: "Value \(index)",
                               accessibilityValue: "Value \(index)", tint: .primary)
            }, isLoading: false, errorText: nil, explanation: nil),
            knownRows: [], otherRows: [], powerIsOn: true, canSetPower: true, canRefresh: true,
            isScanning: false, message: nil, messageIntent: .none, showsConnectionDetails: showsConnectionDetails
        )
        let view = WiFiNetworkListView(
            state: state, onBack: {}, onRequestNameAccess: {}, onOpenWiFiSettings: {},
            onOpenLocationSettings: {}, onSetPower: { _ in }, onRefresh: {}, onOpenSharingSettings: {},
            onCopyValue: { _ in }, showsDetails: showsDetails, showsMore: true,
            onSetShowsDetails: { _ in }, onSetShowsMore: { _ in }
        )
        .environmentObject(Localization())
        .environment(\.isCascadingSubmenu, true)
        .environment(\.statusPanelManagesScrolling, true)
        .frame(width: 302)
        let host = NSHostingController(rootView: view)
        return host.sizeThatFits(in: NSSize(width: 302, height: CGFloat.greatestFiniteMagnitude))
    }
}
