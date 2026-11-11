import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class CascadingSubmenuNestedTests: XCTestCase {
    private final class VisibleFrameWindow: NSWindow {
        override var isVisible: Bool { true }
    }

    private final class SheetWindow: NSWindow {
        var simulatedSheetParent: NSWindow?
        override var sheetParent: NSWindow? { simulatedSheetParent }
    }

    func testDescendantWindowsBelongToEveryAncestorForLocalInput() {
        let root = AnchoredStatusPanel()
        let child = AnchoredStatusPanel()
        let detail = AnchoredStatusPanel()
        root.addChildWindow(child, ordered: .above)
        child.addChildWindow(detail, ordered: .above)
        defer { child.removeChildWindow(detail); root.removeChildWindow(child) }

        XCTAssertTrue(root.ownsEventWindow(detail), "clicking details must keep the root open")
        XCTAssertTrue(child.ownsEventWindow(detail))
        XCTAssertFalse(detail.ownsEventWindow(root), "an ancestor click can close only its nested child")
        XCTAssertFalse(root.ownsEventWindow(NSWindow()))
    }

    func testSheetAttachedToDetailsBelongsToTheEntireSubmenuGroup() {
        let root = AnchoredStatusPanel()
        let child = AnchoredStatusPanel()
        let detail = AnchoredStatusPanel()
        let sheet = SheetWindow()
        root.addChildWindow(child, ordered: .above)
        child.addChildWindow(detail, ordered: .above)
        defer { child.removeChildWindow(detail); root.removeChildWindow(child) }
        sheet.simulatedSheetParent = detail
        XCTAssertTrue(AnchoredStatusPanel.isSheet(sheet, attachedTo: root, child: child))
        sheet.simulatedSheetParent = NSWindow()
        XCTAssertFalse(AnchoredStatusPanel.isSheet(sheet, attachedTo: root, child: child))
    }

    func testThirdPanelContinuesAwayFromAncestorOnBothSides() {
        let screen = StatusPanelScreen(frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
                                       visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        for (rootX, childX, expectedEdge) in [(900.0, 564.0, NSRectEdge.minX),
                                             (100.0, 436.0, NSRectEdge.maxX)] {
            let root = AnchoredStatusPanel()
            let child = AnchoredStatusPanel()
            root.setFrame(NSRect(x: rootX, y: 300, width: 330, height: 300), display: false)
            child.setFrame(NSRect(x: childX, y: 300, width: 330, height: 300), display: false)
            root.addChildWindow(child, ordered: .above)
            defer { root.removeChildWindow(child) }
            XCTAssertEqual(child.preferredSubmenuEdge, expectedEdge)
            let detailsFrame = StatusPanelPlacement.frame(
                contentSize: NSSize(width: 330, height: 220),
                anchor: StatusPanelAnchor(screenRect: NSRect(x: childX, y: 540, width: 330, height: 32),
                                          preferredEdge: child.preferredSubmenuEdge, alignsTop: true),
                screens: [screen]
            )
            XCTAssertFalse(detailsFrame.intersects(root.frame), "a reversed cascade must not cover its ancestor")
            XCTAssertFalse(detailsFrame.intersects(child.frame))
            XCTAssertEqual(detailsFrame.maxY, 572)
            XCTAssertTrue(child.rootPanel === root)
        }
    }

    func testPointerInThirdPanelIsInsideRootEvenWhenMiddlePanelIsHidden() {
        let root = AnchoredStatusPanel()
        let child = AnchoredStatusPanel()
        let detail = VisibleFrameWindow(contentRect: NSRect(x: 50, y: 70, width: 100, height: 80),
                                        styleMask: .borderless, backing: .buffered, defer: false)
        detail.isReleasedWhenClosed = false
        root.addChildWindow(child, ordered: .above)
        child.addChildWindow(detail, ordered: .above)
        defer { child.removeChildWindow(detail); root.removeChildWindow(child) }

        XCTAssertTrue(root.containsScreenPoint(NSPoint(x: 80, y: 100)),
                      "ancestor hover dismissal must include the complete descendant tree")
        XCTAssertFalse(root.containsScreenPoint(NSPoint(x: 200, y: 100)))
    }

    func testHoverGraceDecisionUsesEntryAndDescendantBoundsInBothDirections() {
        let anchorWindow = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 100, height: 40),
                                    styleMask: .borderless, backing: .buffered, defer: false)
        anchorWindow.isReleasedWhenClosed = false
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        anchorWindow.contentView = anchor
        let child = AnchoredStatusPanel()
        let details = VisibleFrameWindow(contentRect: NSRect(x: 300, y: 70, width: 100, height: 80),
                                         styleMask: .borderless, backing: .buffered, defer: false)
        details.isReleasedWhenClosed = false
        child.addChildWindow(details, ordered: .above)
        defer { child.removeChildWindow(details) }
        let coordinator = CascadingSubmenuCoordinator()
        var pointer = NSPoint(x: 150, y: 120)
        coordinator.pointerLocation = { pointer }
        XCTAssertTrue(coordinator.containsPointer(anchor: anchor, child: child), "returning to the entry keeps its child")
        pointer = NSPoint(x: 350, y: 100)
        XCTAssertTrue(coordinator.containsPointer(anchor: anchor, child: child), "a descendant keeps every ancestor open")
        pointer = NSPoint(x: 260, y: 120)
        XCTAssertFalse(coordinator.containsPointer(anchor: anchor, child: child), "the gap alone does not retain a branch after grace")
        details.setFrameOrigin(NSPoint(x: -300, y: 70))
        pointer = NSPoint(x: -250, y: 100)
        XCTAssertTrue(coordinator.containsPointer(anchor: anchor, child: child), "reverse-side descendants have the same hover ownership")
        pointer = NSPoint(x: 500, y: 500)
        XCTAssertFalse(coordinator.containsPointer(anchor: anchor, child: child))
        XCTAssertFalse(coordinator.containsPointer(anchor: nil, child: nil))
    }

    func testEscapeAtAncestorClosesOnlyDeepestChildAndRootTeardownClosesAllLevels() {
        let root = AnchoredStatusPanel()
        let child = AnchoredStatusPanel()
        let detail = AnchoredStatusPanel()
        let rootCoordinator = CascadingSubmenuCoordinator()
        let childCoordinator = CascadingSubmenuCoordinator()
        root.submenuCoordinator = rootCoordinator
        child.submenuCoordinator = childCoordinator
        root.addChildWindow(child, ordered: .above)
        child.addChildWindow(detail, ordered: .above)
        defer { child.removeChildWindow(detail); root.removeChildWindow(child) }
        var childCloses = 0
        var detailCloses = 0
        rootCoordinator.activate(owner: UUID()) { childCloses += 1; child.close() }
        childCoordinator.activate(owner: UUID()) { detailCloses += 1; detail.close() }

        root.cancelOperation(nil)
        XCTAssertEqual(detailCloses, 1)
        XCTAssertEqual(childCloses, 0, "one Escape must return one level")
        XCTAssertTrue(rootCoordinator.hasOpenChild)
        XCTAssertFalse(childCoordinator.hasOpenChild)

        childCoordinator.activate(owner: UUID()) { detailCloses += 1; detail.close() }
        root.close()
        XCTAssertEqual(childCloses, 1)
        XCTAssertEqual(detailCloses, 2)
        XCTAssertFalse(rootCoordinator.hasOpenChild)
        XCTAssertFalse(childCoordinator.hasOpenChild)
    }

    func testNestedEntryKeepsItsNativeHoverTracking() throws {
        let host = NSHostingController(rootView: Text("Connection Details")
            .cascadingSubmenu(isPresented: .constant(false)) { Text("IP Address") }
            .environment(\.isCascadingSubmenu, true)
            .environmentObject(Localization()))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 330, height: 100),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host.view
        host.view.frame = NSRect(x: 0, y: 0, width: 330, height: 100)
        host.view.layoutSubtreeIfNeeded()
        let hoverViews = allViews(in: host.view).filter { view in
            view.updateTrackingAreas()
            return view.trackingAreas.contains { ($0.owner as? NSView) === view }
        }
        XCTAssertEqual(hoverViews.count, 1, "the details entry must retain hover behavior inside the Wi-Fi submenu")
        XCTAssertFalse(window.isVisible, "the fixture must never present windows")
    }

    private func allViews(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { allViews(in: $0) }
    }
}
