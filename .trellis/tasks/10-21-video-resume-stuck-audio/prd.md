# Fix paused video stuck audio-only after long idle

## Goal

Fix a bug on the player (power/plugin/pl_player): after idling for a long time with the video **paused**, tapping resume plays the video only for a short time, then the video frame freezes while audio continues.

## User value

Playback stays usable after a long pause + screen sleep; resuming reliably re-arms the video output instead of a frozen frame with audio.

## Background (confirmed facts from code inspection)

- Player is a singleton `PlPlayerController` wrapping media_kit `Player` + `VideoController`; rendering via `PLVideoPlayer` (lib/plugin/pl_player/view/view.dart) using the fork's `SimpleVideo` (a Flutter `Texture`).
- App-lifecycle pause/resume handlers are **mobile-only** (`addObserverMobile`, lib/utils/mobile_observer.dart). On background they call `Player.pause()` / `Player.play()` **directly** (view.dart:345-359), bypassing `PlPlayerController.play()/pause()` (no `audioSessionHandler.setActive`, no `_playerCount` guard, no controls re-arm).
- Wake-lock is state-driven (`controller.dart:867-920`): it is **enabled on `playing` stream true, released 500 ms after pause/completion** (`WakelockPlus.disable()`). During a long pause the device/screen can therefore fall asleep.
- Android video output uses a **fork of media_kit_video** (`AndroidVideoController`, commit `73771ec`): it creates an `android.view.Surface`, assigns `--wid`, uses `--vo=gpu`, and **on every `videoParams` event re-creates the SurfaceTexture and re-assigns `android-surface-size`/`wid`/`vo=gpu`** (fork `real.dart:71-214`). The app sets `androidAttachSurfaceAfterVideoParameters: false` (`controller.dart:751`), so attach happens before video params are known.
- `SimpleVideo` renders a blank `SizedBox()` whenever `id`/`rect`/`_visible` is stale (`simple_video_texture.dart:62-80`); audio and video share one mpv `Player`, so "audio continues" means decode/audio is alive while the video-output/VO is not advancing.
- No dedicated long-idle/auto-dim logic exists; the only pause timers are hide-controls, brightness/volume indicator, long-press, and the 500 ms wake-lock release.

## Root-cause hypothesis (to confirm during debugging)

The freeze is on the **video output path**, not decode: after a long pause the OS destroys the video Surface/surface (screen-off), and resume re-attaches/re-creates the VO incorrectly (fork `AndroidVideoController` + `androidAttachSurfaceAfterVideoParameters: false`), so frames stop reaching the `Texture` while the audio path keeps running. A secondary suspect is the direct-lifecycle resume path (view.dart:356) bypassing controller state.

## Requirements

- R1. After a long idle pause (screen sleep included), resuming restores continuous video+audio playback; video must not freeze while audio continues.
- R2. The fix must not regress normal play/pause, background pause/resume (`continuePlayInBackground`), or audio-focus/notification resume paths.

## Acceptance criteria

- [ ] AC1. Reproduce: pause video, idle long enough for the screen to sleep, resume; confirm the video freeze + audio-continues symptom on the target platform.
- [ ] AC2. After the fix, the same repro shows video and audio resuming together and staying in sync (no frozen frame).
- [ ] AC3. Normal pause/play (no screen sleep) is unchanged.
- [ ] AC4. Background resume and audio-focus interruption resume still work (`plPlayerController.play()` path intact).

## Out of scope

- Video/audio track selection, codec/hwdec switching.
- Anything not reproducible on the target platform's path.

## Open questions

- Q1. Which platform(s) does this reproduce on? (gates which video-output path to debug: Android Surface fork vs iOS/desktop `NativeVideoController` vs generic mpv `video-sync`/`autosync` handling)
- Q2. On freeze, is the video a **static last frame**, or does it go black/blank? (distinguishes stale-Surface vs blank-`SizedBox` path)
