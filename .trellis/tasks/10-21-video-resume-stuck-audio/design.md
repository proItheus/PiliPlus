# Design — Paused video stuck audio-only after long idle (macOS)

## Problem restated

On macOS desktop, after a long idle with the player paused, resuming plays briefly then the video freezes (static last frame) while audio keeps playing.

## Confirmed constraints

- Desktop (macOS): no lifecycle observer, no wake-lock effect, `NativeVideoController` (vo=libmpv + EGL/D3D surface, created once via `VideoOutputManager.Create`).
- mpv options in use: `video-sync=display-resample` (default), `autosync=0` (non-Android).
- Static last frame ⇒ decode/audio alive, video output path stops presenting frames; texture id/rect remain valid (not the blank-`SizedBox` path).
- The fork creates the video surface once and never recreates it (unlike Android `AndroidVideoController`, which re-creates on `videoParams`).

## Leading hypothesis

The failure is on the **video output / render-context path**, not decode. The strongest candidate: on macOS the OS invalidates the EGL/render surface when the display sleeps during the long pause; neither the fork nor the app recreates it, so after resume mpv can't present new frames (audio, on its own clock, continues). Secondary candidate: `video-sync=display-resample` with a stale display-FPS estimate after wake.

## Diagnostic plan (order matters)

1. **Reproduce on macOS** with mpv logging enabled (already wired in `debug` via `stream.log`). Capture the window around resume.
2. **Isolate layer**: reproduce with a minimal standalone media_kit app (same fork, same options) vs. this app. If the standalone reproduces → third-party/fork/native fault; if only this app → app-level.
3. **Probe mpv properties** around the freeze (video-frame-count, vo-cpu, display-fps, video-fps, eof) to see whether frames stop being produced or stop being presented.
4. **A/B mpv options**: toggle `video-sync` and `autosync`; if one eliminates the freeze, the fault is sync/timing; if not, likely render-context loss.

## Fix branches (decided after diagnosis)

- **A — app-level config**: adjust default `video-sync`/`autosync` (or expose/repair the setting) so resume survives display sleep.
- **B — fork patch**: recreate the video surface on wake / when the render context is lost (dependency override on the pinned `media_kit_video` fork). Largest blast radius; only if A can't fix.
- **C — upstream/known-workaround**: adopt a documented media_kit workaround (e.g. re-open or re-create `VideoController`) if a clean path exists.

## Safety

- No changes until root cause is confirmed by reproduction + probes.
- Prefer the smallest, in-repo change (branch A) over forking.
- Preserve existing play/pause, background (mobile), and audio-focus behaviors.
