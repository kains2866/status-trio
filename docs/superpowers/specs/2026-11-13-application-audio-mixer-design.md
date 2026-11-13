# Application audio mixer

Approved scope: application output gain/mute first; microphone panel lists active input applications and devices only. Reuse the existing cascading hover submenu and neutral header highlighting. Preserve device sliders, selection, names and settings gears.

Entry: hover the Volume or Microphone section header (label plus empty middle); the gear retains its Settings action. Pointer transition/grace behavior follows CascadingSubmenuCoordinator. Keyboard users can click/activate the entry. Output rows: app icon, middle-truncated name with existing hover expansion, mute button, native slider, percentage. Stable ordering; Chrome helpers group under the owning browser when identity is trustworthy, not as independent tabs.

Use public CoreAudio process objects and process taps (macOS 14.2+); retain app deployment floor macOS 13 and show unavailable state on unsupported systems. No virtual driver or microphone per-app writes. FineTune is reference only (GPL-3.0); write independent implementation against Apple APIs.

On first explicit Enable action, request system audio capture access; hover alone never prompts or opens taps. Gain 0–100%, default 100%. A process tap, private aggregate output device and bounded gain stage are created only for apps actually adjusted. Closing the panel stops enumeration/listeners when no processing session needs them; established gain/mute continues until reset, app exit or application shutdown. Returning to 100% unmuted tears down interception. On permission/read/device/format failures, display unavailable and release interception so native playback can resume. No new high-frequency UI polling. Audio callbacks must not allocate, log, lock, dispatch, or touch UI.

First version targets independently controllable output sessions on a known output route. Preserve device routing; do not silently force all sources to the system default. Unsupported/ambiguous routes show an explanation. Browser subprocess identity, permission denial, exit/PID reuse, default-output/device loss, AirPods reconnection and closing/reopening the submenu require coverage. Real audio changes require manual user acceptance.

Sources: Apple Capturing system audio with Core Audio taps; local CoreAudio SDK AudioHardware.h, AudioHardwareTapping.h, CATapDescription.h. API floor verified as 14.2 in installed SDK.
