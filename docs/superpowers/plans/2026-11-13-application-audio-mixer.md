# Application Audio Mixer Implementation Plan

Goal: add a working opt-in output mixer and a read-only microphone usage submenu while preserving the personal panel.
Spec: ../specs/2026-11-13-application-audio-mixer-design.md

1. Implement independently owned audio processing backend: CoreAudio tap plus private aggregate output, realtime-safe gain, bounded ownership/teardown, 14.2 availability, format/route validation; focused unit tests for gain/state/cleanup.
2. Implement process discovery/controller: enumerate output/input clients, resolve app identity, stable grouping and ordering, event-driven refresh scoped to demand, permission/action state and session controls; focused model tests.
3. Integrate hover entries and app rows using existing native panel controls; localize new strings, audio capture usage description; prevent hover from requesting capture and keep gear and device-name interactions intact.
4. Review Swift/native lifetime and permissions, run focused tests during iteration, one final full local delivery profile. Build independent development bundle; report baseline fingerprint failures and manual audio coverage honestly. No automatic live taps or recording for verification.

Review focus: browser helper processes; explicit output routes and multi-output ambiguity; callbacks/teardown; permission denial; app exit/PID reuse; input-only display; normal-route restoration on reset/failure.
