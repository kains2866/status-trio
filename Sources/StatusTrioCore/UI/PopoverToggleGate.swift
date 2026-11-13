import Foundation

/// Allows the first toggle through immediately and ignores repeats that arrive
/// within `lockout`, so rapid clicking cannot thrash the popover.
struct PopoverToggleGate {
    let lockout: TimeInterval
    private var lastAccepted: Date?

    init(lockout: TimeInterval) {
        self.lockout = lockout
    }

    mutating func shouldAccept(at now: Date) -> Bool {
        if let lastAccepted, now.timeIntervalSince(lastAccepted) < lockout {
            return false
        }
        lastAccepted = now
        return true
    }
}

/// Matches a Dock reopen to the physical mouse-down that dismissed the panel.
struct DockClickReopenGuard {
    private var closingMouseDownAt: TimeInterval?
    private(set) var hasPendingClose = false

    mutating func recordClose(mouseDownAt: TimeInterval?) {
        hasPendingClose = true
        closingMouseDownAt = mouseDownAt.flatMap { $0.isFinite ? $0 : nil }
    }

    mutating func consumeIfSamePress(mouseDownAt: TimeInterval?) -> Bool {
        defer { reset() }
        guard let closingMouseDownAt, let mouseDownAt, mouseDownAt.isFinite else { return false }
        return abs(closingMouseDownAt - mouseDownAt) < 0.02
    }

    mutating func reset() {
        closingMouseDownAt = nil
        hasPendingClose = false
    }
}
