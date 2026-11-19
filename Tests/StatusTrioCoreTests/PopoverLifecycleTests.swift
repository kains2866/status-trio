import AppKit
import Foundation
import Testing
@testable import StatusTrioCore

struct PopoverToggleGateTests {
    @Test func acceptsTheFirstToggleImmediately() {
        var gate = PopoverToggleGate(lockout: 0.25)
        let start = Date()

        let accepted = gate.shouldAccept(at: start)
        #expect(accepted)
    }

    @Test func ignoresRepeatsInsideTheLockout() {
        var gate = PopoverToggleGate(lockout: 0.25)
        let start = Date()
        _ = gate.shouldAccept(at: start)

        let shortlyAfter = gate.shouldAccept(at: start.addingTimeInterval(0.1))
        let justInsideLockout = gate.shouldAccept(at: start.addingTimeInterval(0.24))
        #expect(shortlyAfter == false)
        #expect(justInsideLockout == false)
    }

    @Test func acceptsAgainAfterTheLockout() {
        var gate = PopoverToggleGate(lockout: 0.25)
        let start = Date()
        _ = gate.shouldAccept(at: start)

        let afterLockout = gate.shouldAccept(at: start.addingTimeInterval(0.25))
        #expect(afterLockout)
    }
}

@MainActor
struct PopoverContentRetentionTests {
    @Test func usesOneDeterministicFiveSecondReleaseContract() {
        #expect(StatusBarController.popoverContentReleaseDelay == 5)
    }
}

/// Issue #224: a single click on the status item must toggle the panel exactly
/// once. The outside-click monitor must leave a click inside the item's
/// rectangle to the item's own `togglePopover`; otherwise the mouse-down
/// closes the panel and the mouse-up reopens it.
struct PopoverDismissalPolicyTests {
    private let statusItemFrame = NSRect(x: 100, y: 900, width: 30, height: 24)

    @Test func ignoresMouseDownInsideTheStatusItem() {
        let policy = PopoverDismissalPolicy(statusItemFrame: statusItemFrame)
        let center = NSPoint(x: statusItemFrame.midX, y: statusItemFrame.midY)

        #expect(policy.shouldDismiss(at: center) == false)
    }

    @Test func ignoresMouseDownJustInsideTheStatusItemEdge() {
        let policy = PopoverDismissalPolicy(statusItemFrame: statusItemFrame)
        let topLeftInside = NSPoint(
            x: statusItemFrame.minX + 0.5,
            y: statusItemFrame.maxY - 0.5
        )

        #expect(policy.shouldDismiss(at: topLeftInside) == false)
    }

    @Test func dismissesMouseDownOutsideTheStatusItem() {
        let policy = PopoverDismissalPolicy(statusItemFrame: statusItemFrame)
        let elsewhere = NSPoint(x: statusItemFrame.maxX + 1, y: statusItemFrame.midY)

        #expect(policy.shouldDismiss(at: elsewhere))
    }

    @Test func dismissesWhenTheStatusItemIsNotVisible() {
        let policy = PopoverDismissalPolicy(statusItemFrame: nil)

        #expect(policy.shouldDismiss(at: NSPoint(x: 0, y: 0)))
    }

    /// Composes the two halves of one gesture: the global monitor's mouse-down
    /// decision followed by the status item's mouse-up toggle. A click on the
    /// item must leave the panel visible for the toggle, so the gesture closes
    /// it once instead of closing and reopening (the old #224 behaviour).
    @Test func singleStatusItemClickTogglesExactlyOnce() {
        let policy = PopoverDismissalPolicy(statusItemFrame: statusItemFrame)
        var panelVisible = true

        // Mouse-down: the outside-click monitor runs first.
        let click = NSPoint(x: statusItemFrame.midX, y: statusItemFrame.midY)
        if policy.shouldDismiss(at: click) {
            panelVisible = false
        }

        // Mouse-up: the status item's own toggle flips the panel.
        panelVisible.toggle()

        #expect(panelVisible == false)
    }
}


/// Issue #224 follow-up: `NSRect.contains` is half-open, so every edge of the
/// status item must be tested inclusively. A click on the topmost or rightmost
/// pixel used to be treated as an outside click, closing the panel on mouse-down
/// and reopening it on mouse-up.
struct PopoverDismissalPolicyEdgeTests {
    private let statusItemFrame = NSRect(x: 100, y: 900, width: 30, height: 24)

    @Test func everyEdgeAndCornerBelongsToTheStatusItem() {
        let policy = PopoverDismissalPolicy(statusItemFrame: statusItemFrame)
        let points = [
            NSPoint(x: statusItemFrame.minX, y: statusItemFrame.midY),
            NSPoint(x: statusItemFrame.maxX, y: statusItemFrame.midY),
            NSPoint(x: statusItemFrame.midX, y: statusItemFrame.minY),
            NSPoint(x: statusItemFrame.midX, y: statusItemFrame.maxY),
            NSPoint(x: statusItemFrame.minX, y: statusItemFrame.minY),
            NSPoint(x: statusItemFrame.maxX, y: statusItemFrame.minY),
            NSPoint(x: statusItemFrame.minX, y: statusItemFrame.maxY),
            NSPoint(x: statusItemFrame.maxX, y: statusItemFrame.maxY)
        ]

        for point in points {
            #expect(policy.shouldDismiss(at: point) == false)
        }
    }

    @Test func onePixelOutsideEveryEdgeStillDismisses() {
        let policy = PopoverDismissalPolicy(statusItemFrame: statusItemFrame)
        let points = [
            NSPoint(x: statusItemFrame.minX - 1, y: statusItemFrame.midY),
            NSPoint(x: statusItemFrame.maxX + 1, y: statusItemFrame.midY),
            NSPoint(x: statusItemFrame.midX, y: statusItemFrame.minY - 1),
            NSPoint(x: statusItemFrame.midX, y: statusItemFrame.maxY + 1)
        ]

        for point in points {
            #expect(policy.shouldDismiss(at: point))
        }
    }

    /// Pins the platform behaviour the inclusive helper exists for. If AppKit
    /// ever changes it, this test documents what the old code assumed.
    @Test func NSRectContainsExcludesTheMaximumEdges() {
        let centre = NSPoint(x: statusItemFrame.midX, y: statusItemFrame.midY)
        let rightEdge = NSPoint(x: statusItemFrame.maxX, y: statusItemFrame.midY)
        let topEdge = NSPoint(x: statusItemFrame.midX, y: statusItemFrame.maxY)

        #expect(statusItemFrame.contains(centre))
        #expect(statusItemFrame.contains(rightEdge) == false)
        #expect(statusItemFrame.contains(topEdge) == false)
        #expect(PopoverDismissalPolicy.containsInclusive(statusItemFrame, rightEdge))
        #expect(PopoverDismissalPolicy.containsInclusive(statusItemFrame, topEdge))
    }
}

/// Issue #224 follow-up: while the app is active (regular mode), a status-item
/// click makes the app resign active. The focus-loss close paths must leave that
/// click to the item's own mouse-up toggle instead of closing on mouse-down and
/// reopening on mouse-up.
struct PopoverFocusLossDismissalPolicyTests {
    private let statusItemFrame = NSRect(x: 100, y: 900, width: 30, height: 24)
    private var itemCentre: NSPoint {
        NSPoint(x: statusItemFrame.midX, y: statusItemFrame.midY)
    }

    @Test func defersFocusLossWhilePressingTheStatusItem() {
        let policy = PopoverDismissalPolicy(statusItemFrame: statusItemFrame)

        #expect(
            policy.shouldDismissOnFocusLoss(
                at: itemCentre,
                isMouseButtonDown: true
            ) == false
        )
    }

    @Test func dismissesFocusLossWhenPressingElsewhere() {
        let policy = PopoverDismissalPolicy(statusItemFrame: statusItemFrame)

        #expect(
            policy.shouldDismissOnFocusLoss(
                at: NSPoint(x: 10, y: 10),
                isMouseButtonDown: true
            )
        )
    }

    /// Cmd-Tab away with the pointer parked over the menu bar item must still
    /// dismiss (issue #183 keeps working): no button is pressed.
    @Test func dismissesFocusLossWithNoButtonPressedEvenOverTheItem() {
        let policy = PopoverDismissalPolicy(statusItemFrame: statusItemFrame)

        #expect(
            policy.shouldDismissOnFocusLoss(
                at: itemCentre,
                isMouseButtonDown: false
            )
        )
    }

    @Test func dismissesFocusLossWhenTheItemFrameIsUnknown() {
        let policy = PopoverDismissalPolicy(statusItemFrame: nil)

        #expect(
            policy.shouldDismissOnFocusLoss(
                at: itemCentre,
                isMouseButtonDown: true
            )
        )
    }

    /// Composes the active-app gesture: the focus-loss notification arrives on
    /// mouse-down and must defer, then the item's mouse-up toggle closes the
    /// panel exactly once instead of the panel closing then reopening.
    @Test func activeAppStatusItemClickClosesExactlyOnce() {
        let policy = PopoverDismissalPolicy(statusItemFrame: statusItemFrame)
        var panelVisible = true

        if policy.shouldDismissOnFocusLoss(at: itemCentre, isMouseButtonDown: true) {
            panelVisible = false
        }
        panelVisible.toggle()

        #expect(panelVisible == false)
    }
}

/// Issue #224 follow-up 2: a coordinate-free safety net for setups where the
/// status-item hit test misjudges the click. It matches the physical press, so
/// a new click immediately after an outside dismissal still opens.
struct PopoverReopenSuppressionTests {
    @Test func theClosingPressItselfIsSuppressed() {
        var suppression = PopoverReopenSuppression()

        suppression.recordClose(mouseDownAt: 10)
        let suppressed = suppression.shouldSuppressReopen(mouseDownAt: 10.001)

        #expect(suppressed)
    }

    @Test func aNewPressImmediatelyAfterDismissalStillOpens() {
        var suppression = PopoverReopenSuppression()

        suppression.recordClose(mouseDownAt: 10)
        let suppressed = suppression.shouldSuppressReopen(mouseDownAt: 10.3)

        #expect(suppressed == false)
    }

    @Test func missingPressTimesNeverSuppress() {
        var suppression = PopoverReopenSuppression()

        suppression.recordClose(mouseDownAt: nil)
        let suppressedAfterMissingRecord = suppression.shouldSuppressReopen(mouseDownAt: 10)
        #expect(suppressedAfterMissingRecord == false)

        suppression.recordClose(mouseDownAt: 10)
        let suppressedWithMissingQuery = suppression.shouldSuppressReopen(mouseDownAt: nil)
        #expect(suppressedWithMissingQuery == false)
    }

    @Test func nonFinitePressTimesNeverSuppress() {
        var suppression = PopoverReopenSuppression()

        suppression.recordClose(mouseDownAt: .infinity)
        let suppressed = suppression.shouldSuppressReopen(mouseDownAt: 10)

        #expect(suppressed == false)
    }

    @Test func consumingTheRecordAllowsTheNextToggle() {
        var suppression = PopoverReopenSuppression()

        suppression.recordClose(mouseDownAt: 10)
        _ = suppression.shouldSuppressReopen(mouseDownAt: 10)
        let suppressedAgain = suppression.shouldSuppressReopen(mouseDownAt: 10)

        #expect(suppressedAgain == false)
    }

    @Test func resetClearsThePendingPress() {
        var suppression = PopoverReopenSuppression()

        suppression.recordClose(mouseDownAt: 10)
        suppression.reset()
        let suppressed = suppression.shouldSuppressReopen(mouseDownAt: 10)

        #expect(suppressed == false)
    }

    /// The full edge-click gesture: mouse-down closes while the button is held,
    /// then the same click's mouse-up must not reopen the panel.
    @Test func edgeClickClosesWithoutReopening() {
        var suppression = PopoverReopenSuppression()
        var panelVisible = true

        // Outside-click monitor closes on mouse-down even though the geometry
        // check misjudged the item edge.
        suppression.recordClose(mouseDownAt: 10)
        panelVisible = false

        // The status item's mouse-up toggle belongs to the same press.
        if !suppression.shouldSuppressReopen(mouseDownAt: 10.001) {
            panelVisible.toggle()
        }

        #expect(panelVisible == false)
    }
}

struct DockClickReopenGuardTests {
    @Test func suppressesOnlyTheClosingPressAndThenAllowsNextClick() {
        var guardState = DockClickReopenGuard()
        guardState.recordClose(mouseDownAt: 10)
        let samePress = guardState.consumeIfSamePress(mouseDownAt: 10.001)
        let nextPress = guardState.consumeIfSamePress(mouseDownAt: 10.1)
        #expect(samePress)
        #expect(!nextPress)
    }

    @Test func aNewPressImmediatelyAfterOutsideDismissalCanOpen() {
        var guardState = DockClickReopenGuard()
        guardState.recordClose(mouseDownAt: 10)
        let suppressed = guardState.consumeIfSamePress(mouseDownAt: 10.1)
        #expect(!suppressed)
    }

    @Test func suppressingCloseClickAllowsImmediateNextToggle() {
        let start = Date(timeIntervalSince1970: 100)
        var gate = PopoverToggleGate(lockout: 0.25)
        let opened = gate.shouldAccept(at: start)
        var guardState = DockClickReopenGuard()
        guardState.recordClose(mouseDownAt: 10)
        let suppressClose = guardState.consumeIfSamePress(mouseDownAt: 10)
        if suppressClose { gate = PopoverToggleGate(lockout: 0.25) }
        let openedAgain = gate.shouldAccept(at: start.addingTimeInterval(0.15))
        #expect(opened && suppressClose && openedAgain)
    }

    @Test func differentPressAfterOutsideCloseAllowsImmediateToggle() {
        let start = Date(timeIntervalSince1970: 100)
        var gate = PopoverToggleGate(lockout: 0.25)
        let opened = gate.shouldAccept(at: start)
        var guardState = DockClickReopenGuard()
        guardState.recordClose(mouseDownAt: 10)
        let hadPendingClose = guardState.hasPendingClose
        let samePress = guardState.consumeIfSamePress(mouseDownAt: 10.1)
        if hadPendingClose { gate = PopoverToggleGate(lockout: 0.25) }
        let openedAgain = gate.shouldAccept(at: start.addingTimeInterval(0.15))
        #expect(opened && !samePress && openedAgain)
    }

    @Test func missingPressDoesNotSuppressOpening() {
        var guardState = DockClickReopenGuard()
        guardState.recordClose(mouseDownAt: nil)
        #expect(guardState.hasPendingClose)
        let suppressed = guardState.consumeIfSamePress(mouseDownAt: 10)
        #expect(!suppressed)
    }
}
