# Personal Version %VERSION% (Build %BUILD%)

### Application mixer — preview

- Enable Application mixer in Settings → Audio, then hover over the volume or microphone section header to open its side panel. The preference is saved and defaults to off.
- Output apps get independent 0–100% gain and mute controls, app icons and full-name hover expansion. 100% preserves the app's original signal; device master volume is unchanged.
- Reset restores all apps to 100% and unmutes them while keeping the mixer enabled. Microphone apps are listed read-only.
- Gain survives pause/resume for the same app instance. Route or format changes release processing; failed cleanup retains an explicit retry action.

### Fixes

- Clear stale charging labels after unplugging, including in-flight charging operations.
- Improve Bluetooth device deduplication, accessory battery attribution and AirPods endpoint matching; prevent a second Dock click from reopening the panel.

### Availability and validation

- The mixer requires macOS 14.2+ and system audio capture permission on the first actual adjustment. Opening or hovering over the panel does not capture audio. No audio is saved or uploaded.
- Preview supports only validated single stereo output endpoints without physical input streams. Shared bidirectional, aggregate and multi-output routes are unsupported. Audio quality, capture authorization and AirPods behavior still require real-device validation. Quit other app mixers such as FineTune before testing.
- The app retains macOS 13 support; the mixer is unavailable on older systems. Existing personal panel layouts and interactions are preserved.
