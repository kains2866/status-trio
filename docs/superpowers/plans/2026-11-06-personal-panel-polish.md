# Personal panel polish implementation plan

> **For agentic workers:** Use subagent-driven-development or executing-plans for focused tasks.

**Goal:** Adopt battery/input-source improvements and polish personal panel without changing #269 interactions.
**Architecture:** Selective source changes from frozen upstream; keep cascading root and NativePanelLevelSlider. Input source resolves one descriptor for all surfaces.
**Tech Stack:** Swift, SwiftUI, AppKit, Swift Testing/XCTest; macOS 13+.
**Spec:** docs/superpowers/specs/2026-11-06-personal-panel-polish-design.md

## Global constraints
- No display backend, VPN or charging-write behavior changes. No global UI automation.
- Preserve original checkout's uncommitted preview files, settings and native click toggle.
- One final full verification; baseline image failures reported distinctly.

## Review focus
- Simplified/traditional labels must win over generic system image only for recognized Pinyin.
- ABC modifiers must not overwrite Pinyin or other layouts.
- Flow overlap must not leak into card interiors or alter budget proportions.
- Unknown health/power values remain unknown; no extra idle polling.
- Slider material must not lose keyboard/edit-flush behavior or revert thin design.

## Task 1: Input-source updates
- [ ] Add failing mapper tests for existing icon + 简/繁, integrate upstream modifier tests.
- [ ] Selectively adapt InputSourceDescriptor/Controller/State and modifier observer; fix shared drawing resolution.
- [ ] Run InputSource and IconPresentation tests including surface parity.

## Task 2: Battery details and flow seams
- [ ] Inspect upstream BatteryHealth, BatteryDetailsReader, PanelDetailMapper, BatteryPowerFlowView and geometry.
- [ ] Import focused upstream tests first; verify missing behavior.
- [ ] Integrate read-only battery fields with necessary localization; retain cascading details header.
- [ ] Integrate wide-ribbon overlap fix with geometry/render tests, preserving proportion and no-connection corners.
- [ ] Run focused battery and localization tests.

## Task 3: Slider material
- [ ] Confirm installed build and actual native drawing configuration.
- [ ] Add appearance regression, remove forced text-color fill and use supported native appearance/material without changing dimensions.
- [ ] Run NativePanelLevelSlider and AudioLevel/BrightnessControls tests.

## Delivery
- [ ] Review all changes and fix actionable findings.
- [ ] Run final full profile; report failures and unrun steps exactly.
- [ ] Build Debug from reviewed source; install with existing dev identity and verify commit provenance.
