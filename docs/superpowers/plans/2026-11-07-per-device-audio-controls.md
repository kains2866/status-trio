# Per-device audio implementation plan

> **For agentic workers:** Use subagent-driven-development for the two independent hardware domains; parent integrates presentation and runs final delivery checks. No worker commits.

**Goal:** Per-device output and microphone rows with independent sliders, independent mute and explicit current-route selection.
**Architecture:** Explicit ID/UID writes through existing controllers and bounded monitor lifetimes; one shared read-only level value; existing default-route commands retained for shortcuts. Parent owns common actions/store and SwiftUI integration.
**Tech Stack:** Swift 6, AppKit, SwiftUI, CoreAudio, XCTest/Swift Testing; macOS13+.
**Spec:** docs/superpowers/specs/2026-11-07-per-device-audio-design.md
**Base:** f3efaf44 (personal branch); frozen upstream reference cf24f1da; no upstream display backend merge.

## Global constraints
- Preserve personal thin sliders, outside labels, cascading overflow, neutral hover and native toggle behavior.
- No extra idle sampling, permission requests, recording/capture, automatic route switch on drag, or implicit multi-device mixing.
- Per-device writes validate live identity/capabilities; nil/unknown states never appear as 0%.
- Preserve current-route DDC/BetterDisplay paths; targeted non-current external writes require a native supported path.
- Test via scripts/test.sh; serialize SwiftPM runs. Visible UI tests disabled. Run full once on final tree and separate known image failures from regressions.

## Shared interface contract

Output task creates `Audio/AudioDeviceLevel.swift`:
`AudioDeviceLevel: Equatable, Hashable, Sendable` with `scalar: Double?`, `canAdjust: Bool`, `muteState: AudioDeviceMuteState`, `canMute: Bool`; enum cases `unknown`, `unmuted`, `muted`, `partial`; static `unavailable`.
Both `AudioOutputDevice` and `AudioInputDevice` gain an optional `level: AudioDeviceLevel? = nil` initializer argument; old constructors remain valid. Output's legacy volume stays consistent when replacing its level.

Output monitoring/control protocols add `setVolume(_:forDeviceID:expectedUID:)`, `toggleMute(forDeviceID:expectedUID:)`; VolumeControlling additionally adds `flushPendingVolume(forDeviceID:expectedUID:)`.
Input monitoring adds `setScalar(_:onDeviceID:expectedUID:requestID:)`, `toggleMute(onDeviceID:expectedUID:)`; retain legacy APIs and keep non-current readbacks out of global current scalar/request state.

## Task1 — Output domain (output worker)
Files: AudioDeviceLevel, AudioOutputDevice, AudioOutputControlling, VolumeControlling, CoreAudioOutputController, VolumeMonitor, focused output tests/fakes.
- [x] Add RED regressions for explicit non-current device write/mute without default-route writes; stale UID and unavailable controls fail safely.
- [x] Read per-device native capabilities only under existing inventory demand; implement ID-bound controller writes and monitor dispatch, preserve default external backends and flush.
- [x] Run focused output/default/backend/lifecycle regression filters and record results.

## Task2 — Input domain (input worker)
Files: AudioInputStatus, AudioInputHardware/CoreAudioInputHardware, AudioInputMonitor and focused input tests/fakes.
- [x] Add RED tests for non-current scalar/mute, independent status, stale identity, serialized commands and stop/disconnect.
- [x] Fill inventory levels and execute explicit ID/UID commands via existing bounded worker. Preserve current-route behavior and idle lifecycle.
- [x] Run focused hardware/monitor/draft/lifecycle regressions and record results.

## Task3 — Presentation and wiring (parent)
Files: PanelAudioDeviceRow/VolumePanelState, AudioPanelMapper, StatusPanelActions, SystemStatusStore, VolumeControlsView, AudioInputControlsView, OutputDeviceList, new shared AudioDeviceLevelRow; focused layout/interaction/action tests.
- [x] Add RED mapper/action regressions demonstrating rows do not share the current scalar and slider callbacks identify the intended device.
- [x] Add row-local draft keyed by ID+UID; route explicit commands through actions/store without optimistic changes to other rows. Preserve callback completion and default shortcuts.
- [x] One compact row/device; current blue icon, separate mute, name72pt, thin slider, percentage34pt; per-section Settings control once. Initial3 with current device retained and overflow in side panel. Preserve listening modes and preview-only rows.
- [x] Export offscreen light/dark one/three/overflow/unsupported/muted fixtures; run focused presentation tests.

## Review focus
- Device ID reuse and unplug after gesture start cannot write to replacement hardware.
- Muting non-current device cannot toggle the selected device; a mute button with unknown state stays disabled.
- Async readback of one microphone cannot overwrite another row's draft or current-route scalar.
- Backend handoff for selected external outputs preserves DDC/BetterDisplay final flush.
- Hidden section/device/order/listening-mode preferences and one-row visibility remain coherent.

## Delivery
- [x] Independent code+Swift reviews; fix actionable findings and re-review changed scope.
- [x] Fetch/compare origin/main; full final profile and diff check; report baseline failures/unrun stages honestly.
- [ ] One local feature commit; build personal Debug, verify source SHA and settings-preserving identity, install/run if build succeeds. No push/merge/release in this task.

## Verification evidence (2026-11-07)

- Branch base: `f3efaf44fc0c31dd87b87f38089b1f67466d2ea8`. Fetched `origin/main` at `3e7574e0e788fa23139659af1f5cf351fa003c5c`, already an ancestor; no merge was needed.
- RED evidence includes missing explicit action/readback interfaces and assertion failures for nil UID commands; GREEN combined audio/presentation/settings/backend filter: 508 tests, zero failures. Input hardware and serial worker subset: 70 tests, zero failures.
- Review corrections cover concrete non-default input HAL writes, per-channel UID replacement, main-mute precedence, current-only wheel targets, unavailable UID controls, and drag-end readback timing.
- `scripts/verify-local.sh full` ran 2765 XCTest cases (87 visible UI cases skipped) and 935 Swift Testing cases. It stopped at the existing two app-artwork assertions and one charging-effect fingerprint assertion, matching the prior baseline fingerprints. No audio regressions were reported. This is not a passing full profile; its later build/native stages did not execute.
- Offscreen fixtures use shipping views and synthetic data; no windows were presented and no real hardware control was installed. Live device switching, actual gain/mute behavior, external displays and macOS 13 runtime acceptance remain unverified.
- Build/bundle and final installed commit evidence is recorded locally under `.build/verification/per-device-audio/`; none of this work publishes a branch or release.
