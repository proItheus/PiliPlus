# Implement — Paused video stuck audio-only after long idle (macOS)

## Status

Planning. Blocked on user approval of the final planning summary before `task.py start`.

## Checklist

- [ ] Reproduce on macOS: `just run -d macos`, open a video, pause, set system idle to sleep the display during the pause, resume, confirm frozen-frame + audio-continues.
- [ ] Enable/collect mpv logs around the freeze (`stream.log` in debug; grep for VO/EGL/display errors).
- [ ] Isolate layer via minimal standalone media_kit repro (same fork commit, same `video-sync`/`autosync` options).
- [ ] Probe mpv state properties around freeze (video-frame-count, vo-cpu, display-fps, video-fps).
- [ ] A/B `video-sync` and `autosync` to classify sync vs render-context fault.
- [ ] Apply smallest fix per design branch (A app-level config → B fork patch → C workaround). Re-run the exact repro to confirm video+audio resume together.
- [ ] Regression: normal play/pause, mobile background pause/resume, audio-focus/notification resume all unchanged.

## Validation

- `just analyze` and `just test` pass.
- Repro AC2 (video+audio resume together) passes post-fix.
- No behavior change on non-macOS paths unless explicitly decided.

## Rollback

- Fix is small and in-repo (branch A): revert config default.
- Fork patch (branch B): revert dependency override in `pubspec.lock`/`pubspec.yaml`.
