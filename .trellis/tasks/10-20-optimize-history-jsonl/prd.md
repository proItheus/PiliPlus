# Optimize history sync jsonl size

## Goal

Reduce shared-folder history jsonl bloat without changing the CRDT convergence contract. Three changes: (1) publish events at a sparse cadence (every 10 minutes, or on pause/exit/video-change), (2) dedupe consecutive same-key lines when appending to a writer file, and (3) slim event payloads to bare identifying fields, hydrating display metadata from the server with local caching.

## Background / confirmed facts

- Sync writes one JSONL line per published event in `lib/utils/local_history_sync.dart` (`_drain`, file `events-<writer_id>.jsonl`). Event schema v2 stores the full `HistoryItemModel.toJson()` (`item`) per upsert.
- Publication triggers: `LocalHistory.record/remove/clear/import` → `publishUpsert/publishDelete/publishClear`. Every playback checkpoint currently publishes a full upsert.
- Playback cadence is controlled by `lib/pages/video/view.dart`: `_historyCheckpointInterval = Duration(seconds: 10)` gates `recordLocalHistory`. Boundary paths already pass `force: true`: playback start, completion, pause (player status listener and app-lifecycle `paused`), and video change (key differs from `_lastHistoryKey`). The position listener calls non-force `recordLocalHistory(position:, stalePosition: true)`, throttled to 10s.
- The reducer keeps a per-key LWW maximum plus a `clear` watermark and converges regardless of replay order. Removing an older same-key line from a writer file is semantically safe: a later same-writer event for that key always carries a greater HLC, so the retained line still wins.
- Metadata APIs already exist in the repo: `Api.videoIntro(bvid)` (in `lib/http/video.dart`) returns `VideoDetailData` (title, pic, owner, videos, duration, pages) for `archive`; `SearchHttp.pgcInfo(epId:)` (in `lib/http/search.dart`) returns `PgcInfoModel` (episodes) for `pgc`. `Api.episodeInfo` exists but is unused.
- Persistence is Hive (`hive_ce`); there is no sqlite/drift. `GStorage.localHistory` box already holds `cacheList`, `syncOutbox`, `syncMetadata`.
- Existing tests: `test/utils/local_history_sync_test.dart`, `test/utils/local_history_test.dart`, `test/utils/hybrid_logical_clock_test.dart`.

## Requirements

### 1. Sparse event emission
- Local Hive projection saves keep the current 10s progress checkpoint; only event publication becomes sparse.
- Publish an upsert only when one of the following holds:
  - the canonical key differs from the last published key (video change);
  - the item is completed (`progress == -1`);
  - a forced boundary occurs (pause, exit/`-cycle, playback start);
  - ≥10 minutes have elapsed since the last published upsert for the same key.
- `delete` and `clear` behave as today (always publish).

### 2. Consecutive same-key dedupe
- Before appending a keyed operation (upsert/delete) to a writer file, if the file's final byte is a newline and the final complete line decodes to the same canonical key as the new event, truncate that line, then append the new line.
- Clear events (no key) are never deduped.
- Convergence must be preserved: only the newest same-key line remains, which the reducer would select anyway.

### 3. Slim events + metadata hydration
- Add slim event schema v3: keep only the fields needed to uniquely identify a video and to preserve history semantics (`history` identifier fields, `viewAt`, `progress`, `duration`). Drop display payload (`title`, `cover`, `covers`, `uri`, `authorName`, `authorMid`, `videos`, `badge`, `showTitle`, `isFav`, `kid`, `tagName`, `liveStatus`).
- Keep decoding existing v2 fat events so previously written shared folders remain fully readable.
- Reconciliation hydrates slim items from a metadata cache keyed by the canonical key. On cache miss, fetch from the server (`archive` via `bvid`, `pgc` via `epId`) with bounded concurrency, and cache the result. Failed fetches leave placeholder display fields and are retried on a later sync.
- Projection inclusion must not drop a synced item purely because its display metadata is not yet available (offline case).

## Acceptance criteria

- [ ] During continuous playback, at most one upsert event per video is emitted per 10 minutes, plus one at pause, play start, completion, and on video change; local Hive projection continues to update at the existing 10s checkpoint cadence.
- [ ] Appending a same-key event truncates the immediately preceding same-key line; the writer file never grows from consecutive same-key upserts, and CRDT projection is unchanged by the truncation.
- [ ] A slim v3 event round-trips through the writer/reader; the projection built from a v3 event lacks no required history row (progress, view_at, key retained).
- [ ] Existing v2 event files still reconcile to an identical projection.
- [ ] A metadata cache hit avoids a network request; a cache miss triggers at most one request per key per sync; a failed request leaves the row visible with placeholder display fields and retries on a later sync.
- [ ] Archive (UGC) and pgc (episode) metadata hydrate into the projection (title/cover/author) when the server responds.
- [ ] Focused sync/local-history tests, formatting, and analysis pass through the documented repository recipes.

## Out of scope

- No js/retention/compaction beyond the consecutive line truncation.
- No network-clock verification; no protocol changes.
- No changes to Hive boxes, settings, cookies, or unrelated files.
- No change to the canonical key `business|oid|cid` or the LWW/clear reducer semantics.

## Key decisions

- Canonical key remains `business|oid|cid`.
- New writes use schema v3; v2 remains readable and is never rewritten.
- Metadata cache lives in the existing `GStorage.localHistory` box under a new key `videoMeta` (no new Hive box, no init change).
- Hydration is asynchronous and non-blocking relative to sync; sync writes the projection from cached metadata and enqueues missing-key fetches that refresh the controller when they complete.

- Synced rows without cached metadata render with placeholder title/cover and hydrate in the background, auto-refreshing when metadata arrives (approved decision).
