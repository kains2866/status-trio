# Wi-Fi detail and hover fix

Base: d394d188 personal version. User authorized fixing diagnosed detail auto-expansion and hover geometry, then local commit.

Design: Keep Wi-Fi list compact; a Connection Details entry opens a nested side panel on hover/click. Never inline all parameters solely because isCascadingSubmenu is true. Each parent owns its own child; moving into a descendant keeps ancestor menus open; Escape dismisses one level and root close tears down all descendants. Permission boundaries and settings routes unchanged.

Hover: retain neutral gray and existing text sizes; use 12pt corner radius with 8pt horizontal/6pt vertical content clearance. Background, anchor and hit area agree, panel stays 330pt wide, neighboring rows retain separation.

Alternatives: inline collapse would restore older disclosure but violates the chosen all-side-panel interaction; auto-expanded parameters rejected because too tall and hides network list.

## Plan
- [x] Add failing Wi-Fi list/detail and nested ownership/close regressions.
- [x] Adapt CascadingSubmenu and AnchoredStatusPanel for one child per level and descendant input ownership; preserve native toggling and focus behavior.
- [x] Wire connection detail submenu using existing localized labels/rows, reset its state on parent close.
- [x] Add offscreen hover clearance/shape tests; update neutral highlight geometry without font changes.
- [x] Run focused tests, independent code review, final full profile. Baseline artwork/fingerprint failures remain findings.
- [ ] Commit only requested changes locally; build and run reviewed Debug if permitted, preserve identity/settings.

Known unrelated source workspace has uncommitted preview edits; other managed checkout serves Pinyin PR. Neither is edited.

## Evidence
- RED: 8 tests / 15 expected assertions (inline-height, hierarchy, Escape, hover clearance).
- Focused: 48 XCTest, 4 visible-UI tests skipped, no failures; 28 Swift Testing passed. Log /tmp/status-trio-wifi-hover-focused.log.
- Full final tree: 2723 XCTest,87 skipped,2 known artwork assertions;935 Swift Testing,1 known charging fingerprint failure. No new failures. Log /tmp/status-trio-wifi-hover-full.log. Full profile stopped at tests, later full stages NOT RUN.
- Code and Swift reviews approved; followups cover descendant-key restoration and deterministic injected pointer in synthetic tests.
- Offscreen light/dark battery previews inspected. Real three-panel hover/keyboard routing and macOS13 runtime NOT RUN. No global input or real Wi-Fi state changed.
- origin/main fetched and compared:3e7574e0. Base d394d188 already includes personal controls/input/battery polish and is preserved. No push/merge to main.
