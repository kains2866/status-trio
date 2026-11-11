# Per-device audio controls

The user requested the FineTune-style per-device layout and confirmed that the left highlighted icon selects the system's current output/input, with a separate mute control. This is the approved interaction contract.

## User-visible behavior

- Keep output and microphone sections visible together, with one row per device: selection icon, short device name, separate mute button, native thin slider, percentage. Remove the duplicated global slider above the device list.
- Blue selection means the current system route, independently of mute. Exactly one device per section is selected. Clicking the current icon is idempotent; selecting a different icon switches only that section's default.
- Dragging any supported row adjusts that device without switching defaults. A muted device stays explicitly muted until the mute button is used; moving a slider must not silently switch another route.
- Preserve current device identity/order/hiding preferences, existing listening-mode controls, 330pt panel width, fonts, neutral hover, and the existing three-device compact-list convention. Additional devices open in the established hover side panel. Active devices remain reachable even when reordered/hidden.
- A missing or unsupported level is shown as unavailable, never as a fabricated 0%. Only the unavailable control is disabled; device selection stays available when supported.
- One-row sections still show their device name/selection icon/slider. Existing Settings visibility controls retain their meaning; a hidden device list uses the existing current-device-only control as a compatibility fallback.

## Implementation approach

Adopt actual per-device control (instead of moving the current-device slider beside every name). Add a small device-level snapshot shared by the hardware domains, then keep targeted writes identity-bound through actions/store/monitors. Existing default-route APIs remain for global wheel/keyboard shortcuts and existing backend integrations.

For output hardware, query native capabilities per device while the inventory is demanded and write the explicit ID/UID. Existing BetterDisplay/DDC current-route paths stay supported. Non-current external devices without safely addressable controls remain unavailable instead of switching routes to write them. This is unrelated to the deferred display-brightness backend changes.

For microphones, include per-device scalar/mute capability in visible inventory reads. Reuse the serialized worker and request/generation gates for explicit-device writes. Never open an audio capture stream or request new privacy permissions to adjust HAL controls.

No extra idle polling, broad listening to every device while hidden, process audio mixing, or simultaneous multi-output/multi-microphone routing. Changes remain macOS13 compatible. Menu Bar/Dock reflect the current route through the same existing snapshot.

## Verification

Tests must prove independent device writes, no implicit default selection, stale UID/unplug rejection, unsupported/unknown controls, per-device draft/readback isolation, selection while dragging, final-value flushing, one/three/more-than-three layouts, existing hidden/order/listening-mode behavior, and no new hidden-surface reads. Use offscreen synthetic fixtures for light/dark previews. Real device writes require user acceptance after build; automated tests must use fake hardware.

Ruling: the user's reply confirming icon selection approves the presented per-device design; routine layout values follow the existing brightness rows. One feature is kept in one local commit including its design/plan, honoring the user's commit preference.
