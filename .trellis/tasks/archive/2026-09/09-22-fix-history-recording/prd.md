# Fix inconsistent history recording

## Goal

Make non-file playback history durable across continuous playlist playback and keep each entry's watched position close to the actual player position.

## Confirmed facts

- `VideoDetailPageV.playerListener` currently records local history only when playback enters `playing` and when the player reports `completed` (`lib/pages/video/view.dart:216-225`). The `playing` callback commonly observes the initial position, so it writes zero; pauses and ordinary position changes write nothing.
- `positionListener` receives the player position but currently updates only `VideoDetailController.playedTime` (`lib/pages/video/view.dart:188-190`).
- Route transitions remove the page's player listeners before pausing (`lib/pages/video/view.dart:424-449`), and app lifecycle pause handling does not snapshot local history.
- `LocalHistory.record` serializes Hive read-modify-write operations, but playback callers discard the returned future (`lib/pages/video/view.dart:319-343`). The local-history controller reads synchronously, so it can render before queued writes finish.
- Consecutive playback invokes `nextPlay` without awaiting the episode switch (`lib/pages/video/introduction/ugc/controller.dart:710-712`; equivalent PGC path), so the completion snapshot must be queued and durable independently of the next media source.

## Requirements

1. Record an entry when a non-file video starts, periodically while its position advances, and at every meaningful stop boundary: pause, completion, route transition, app pause, and page disposal.
2. Persist the latest position in the history API's seconds unit; a completed item remains `-1`. Periodic writes may be throttled, but an explicit stop-boundary snapshot must not be skipped.
3. Preserve every distinct `(business, oid, cid)` item during continuous playlist/episode playback. A later source switch must not overwrite an earlier item's final snapshot.
4. Keep local-history writes serialized and expose a completion boundary so readers can wait for queued writes before loading the list.
5. Keep remote Bilibili heartbeat/history behavior and file-source `watchProgress` behavior unchanged.

## Acceptance Criteria

- [ ] Watching a continuous playlist creates one local-history entry per distinct video after the queued writes are drained; entries are not limited to an early prefix of the playlist.
- [ ] Stopping a video after seeking or playing advances its local-history progress to the stop position rather than leaving the initial zero, and the persisted value is within the configured periodic checkpoint interval unless the player reports a stop boundary sooner.
- [ ] Pausing, leaving the video route, backgrounding the app, and completing a video each persist a final snapshot; completed entries use `-1` and reopen from the beginning.
- [ ] Opening local history while playback writes are pending waits for those writes and displays the complete persisted list.
- [ ] Existing local-history deduplication, import/export, deletion, and file playback behavior remain intact.
- [ ] Focused tests/smoke checks, formatting, and Flutter analysis pass.

## Scope boundary

Expected product files: `lib/pages/video/view.dart`, `lib/utils/local_history.dart`, and `lib/pages/local_history/controller.dart`; add a focused persistence regression test only if it can assert the observable queue/read contract without coupling to widget internals. Do not modify remote history APIs, generated files, or unrelated player/playlist behavior.
