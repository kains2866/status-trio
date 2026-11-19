# Issue #224 — single click on the status item did not close the panel

Related: [#224](https://github.com/lingyired/status-trio/issues/224),
[#186](https://github.com/lingyired/status-trio/issues/186) (arrowless
`NSPanel` that introduced the hand-rolled dismissal),
[#183](https://github.com/lingyired/status-trio/issues/183) (activation gating).

## Symptom

After opening the status panel with a single click on the menu-bar item, a
second single click on the same item did not close the panel — it visibly
flashed and stayed open, so users needed a double click. Other app windows
flickered during the attempt.

## Root cause

The arrowless panel (`AnchoredStatusPanel`, issue #186) dismisses on outside
clicks through `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown,
.rightMouseDown])`. That monitor closed the panel on **every** mouse-down, with
no exception for the status item itself.

When the panel opens while the app is not active (the forced `activate` from a
status-item click can be ignored by the user-activation policy — see the comment
in `presentPopover`), a click on the status item is delivered by the system
menu-bar process and reaches the global monitor as an outside click:

1. `mouseDown` → monitor calls `performClose` → panel closes.
2. `mouseUp` → the button's action (`handleClick` → `togglePopover`) sees
   `popover.isShown == false` and presents the panel again.
3. So one click closed then reopened the panel: it looked like "does not
   close", and the repeated re-present re-ordered windows / re-requested
   activation, which flickered other windows.
4. A rapid second click was then swallowed by `PopoverToggleGate`
   (`popoverToggleLockoutInterval = 0.25`), so only the mouse-down close
   remained — a double click "closed" it.

## Fix

`PopoverDismissalPolicy` (new, pure) decides whether a global mouse-down is an
outside click. `StatusBarController.installPopoverDismissMonitor()` now builds
the status item button's screen rectangle and skips the dismissal when the click
lands inside it, leaving the click to the item's own `togglePopover`. Clicks
outside the item still dismiss; when the item is not visible there is nothing to
protect and every click dismisses (previous behaviour).

The fix does not add timers, polling, or repeated activation. A single
status-item click now produces exactly one state change (open → closed), so the
close–reopen activation churn that caused the flicker is gone.

## Verification

- Deterministic unit tests (`PopoverLifecycleTests.swift`,
  `PopoverDismissalPolicyTests`): click inside the item is not dismissed, click
  outside is dismissed, missing frame falls back to dismissing, and one
  status-item gesture toggles exactly once. A regression guard shows the old
  unconditional dismiss would reopen on the same click. **PASS** (10 tests).
- Full local profile (`bash scripts/verify-local.sh full`): see delivery record.
- Real-device click-driven check (single click open, single click close, double
  click does not thrash, other windows do not flicker) on macOS 13 and current
  macOS: **NOT RUN** — this harness has no permitted Computer Use provider for a
  status-item click (same limitation recorded for #186), so it requires an
  authorized foreground/manual pass.


## Follow-up: deactivation still reopened v1.9.2

On macOS 27.0.1, production logs showed app deactivation closing the panel
before the status item's mouse-up reopened it. The global-click exclusion
above does not cover this path. Menu-bar presentation now skips the legacy
`NSPopover` forced activation: the current nonactivating `NSPanel` becomes key
without it. A panel-scoped workspace observer preserves Cmd-Tab dismissal and
ignores Status Trio's own activation; existing close teardown removes it.

The activation and workspace-close tests failed before their respective fixes.
The focused visible run passed 16 XCTest and 8 Swift Testing cases. The user
confirmed repeated open/close/reopen, Settings-open behavior, Cmd-Tab, Escape,
and outside clicks. CUA could inspect windows but could not click the status item.
Full local verification is recorded in the PR; macOS 13 runtime is NOT RUN.
Shortcut activation is unchanged; shortcut-open → status-click is unvalidated.


## Follow-up 2: edge pixels and regular-mode focus loss (fork issue #6)

Related fork tracking: [#6](https://github.com/kains2866/status-trio/issues/6).
The three upstream follow-ups (`c5474fb9`, `07b2882a`, `79b479b2`) were not in
this fork's `main`, so v1.9.4 / v1.9.7 still showed the original behaviour.

### Root cause

- `NSRect.contains(_:)` is half-open: `maxX` / `maxY` are outside. The
  status-item hit test in `PopoverDismissalPolicy.shouldDismiss` used it, so a
  click on the item's topmost or rightmost pixel was an "outside click" —
  mouse-down closed the panel and mouse-up reopened it (the "it refreshed
  instead of closing" report).
- In regular mode (Settings open, or the Dock icon shown), the status-item click
  also makes the app resign active. `AnchoredStatusPanel`'s `didResignActive`
  and `NSWorkspace.didActivateApplication` observers closed the panel on
  mouse-down for the same close/reopen result.
- No coordinate-free fallback existed for menu-bar geometry that the hit test
  misjudges (multi-display, notch, a different macOS build).

### Fix

- `PopoverDismissalPolicy.containsInclusive(_:_:)` compares all four edges
  inclusively. `shouldDismiss` and the new `shouldDismissOnFocusLoss` use it;
  one pixel outside an edge still dismisses.
- `PopoverReopenSuppression` records the mouse-down timestamp of the press that
  closed the panel. The following status-item mouse-up toggle is ignored only
  when it belongs to that same press (20 ms tolerance, matching
  `DockClickReopenGuard`). A new click immediately after an outside dismissal
  still opens. This is coordinate-free.
- `AnchoredStatusPanel.shouldDeferDismissalOnFocusLoss` lets the controller keep
  a status-item press alive; genuine focus loss without a pressed button still
  dismisses (#183 behaviour preserved). The app-window focus guard (#267) uses
  the same deferral.
- `AnchoredStatusPanel.containsScreenPoint` uses the inclusive test, so a click
  on the panel's own outer edge is not an outside click.
- `revealAfterSettling` re-asserts `orderFrontRegardless` so a window brought
  forward during the settling turn cannot end up above the first-level panel.

### Verification

- `PopoverLifecycleTests`: 4 edge/corner points inside, 1 px outside each edge,
  the half-open `NSRect.contains` contract, focus-loss deferral, the full
  same-press close-without-reopen gesture, and suppression window/reset cases.
  **PASS**.
- `CascadingSubmenuEdgeHitTests` asserts the window-level edge hit for an
authorized visible/isolated session. It is a `VisibleUITestCase` (skipped by
default): creating an extra panel in the shared XCTest process perturbs the
pre-existing symbol-raster fingerprint test when both run in the same full
suite. The pure `PopoverDismissalPolicyEdgeTests` covers the inclusive
semantics in the normal suite.
- `StatusPanelContentTests.testPanelCanBecomeKeyWithoutBecomingMain` pins the
  default `level == .statusBar` and `isFloatingPanel`. It does not exercise the
  background-testing `.normal` switch/restore, which is covered by that route's
  own policy.
- `bash scripts/verify-local.sh quick 'Popover'`: **PASS**.
- `bash scripts/verify-local.sh full` on the first branch commit `f8952900`:
  **PASS** — 2858 XCTest (88 skipped) and 1001 Swift Testing, Release build and
  native contracts. That commit contains the same menu-bar fix; the later
  amendment only changes the suppression to press identity and adds tests/docs.
- Moving the window-level edge assertion to the visible boundary avoids the
  interaction with the **known pre-existing**
  `ChargingEffectRenderingTests.nilPhaseKeepsThePreEffectStaticPixelFingerprint`
  failure (`db42f0d...`, see `docs/application-audio-mixer.zh-Hans.md`). The
  fingerprint test itself was not relaxed or skipped.
- Real pointer clicks on each icon edge and in regular mode: **NOT RUN** — no
  permitted Computer Use provider for a status-item click in this session. It
  still needs an authorized foreground/manual pass. The focus-loss wiring has a
  `VisibleUITestCase` ready for that authorized run; the reveal re-order has no
  automated test.
- macOS 13 runtime: **NOT RUN**.
