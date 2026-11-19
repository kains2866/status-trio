import Foundation

/// Suppresses the status item's reopen toggle when the panel was already closed
/// by the mouse-down of the *same* physical press.
///
/// Issue #224 follow-up 2: the outside-click monitor closes the panel on a
/// mouse-down; the status item's action then fires on the following mouse-up and
/// `togglePopover` sees `popover.isShown == false` and presents the panel again —
/// a single click looks like it "refreshed" instead of closing. `PopoverDismissalPolicy`
/// avoids that by not dismissing when the click is inside the status item's
/// screen rectangle, but that hit test can misjudge the item on some setups
/// (multi-display / notch / menu-bar geometry, or a different macOS build), and
/// the panel still closes on mouse-down for those users.
///
/// This is the coordinate-free safety net. It matches the closing press by its
/// mouse-down timestamp, the same contract as `DockClickReopenGuard`, so a new
/// press immediately after an outside dismissal still opens the panel. A
/// missing or non-finite timestamp records/consumes nothing and leaves the
/// normal geometry and focus-loss paths in charge.
struct PopoverReopenSuppression {
    /// `event.timestamp` and `lastLeftMouseDownTime()` share the system-uptime
    /// clock; this tolerance absorbs the sub-millisecond difference between the
    /// monitor's event and the CoreGraphics query.
    static let pressMatchTolerance: TimeInterval = 0.02

    private var closingMouseDownAt: TimeInterval?

    /// Records the left mouse-down that dismissed the panel. A close that was
    /// not caused by a held button (Escape, a panel action, the item's own
    /// mouse-up toggle) passes `nil` and leaves any earlier record intact.
    mutating func recordClose(mouseDownAt: TimeInterval?) {
        guard let mouseDownAt, mouseDownAt.isFinite else { return }
        closingMouseDownAt = mouseDownAt
    }

    /// Whether the pending status-item toggle belongs to the same press that
    /// closed the panel. Consumes the record either way, so a later press can
    /// open normally even when this one did not match.
    mutating func shouldSuppressReopen(mouseDownAt: TimeInterval?) -> Bool {
        defer { closingMouseDownAt = nil }
        guard let closingMouseDownAt,
              let mouseDownAt,
              mouseDownAt.isFinite else { return false }
        return abs(closingMouseDownAt - mouseDownAt) < Self.pressMatchTolerance
    }

    mutating func reset() {
        closingMouseDownAt = nil
    }
}
