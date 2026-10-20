# Technical design

## Behavior gap

Shared-folder history events currently store the full `HistoryItemModel` (title, cover, uri, author, …, all serialized) and are published on every 10-second playback checkpoint. During continuous playback this grows a writer file by ~6 lines/minute with mostly-redundant payloads. The CRDT reducer needs only per-key max + clear watermark, so we can (a) publish sparsely, (b) truncate consecutive same-key lines, and (c) ship a slim event carrying only identifiers plus progress/view-at, hydrating display metadata from server-cached lookups.

## Changes

### 1. Sparse event emission (`lib/utils/local_history_sync.dart`, `lib/utils/local_history.dart`, `lib/pages/video/view.dart`)

Local Hive projection saves keep the existing 10s checkpoint cadence. Only publication is gated.

- `LocalHistory.record(item, {bool forcePublish = false})` keeps saving every call and forwards `forcePublish` to `LocalHistorySync.publishUpsert(item, force: forcePublish)`.
- `publishUpsert(item, {bool force = false})` decides:
  - publish when `force` (pause / lifecycle-exit / play-start paths pass `force: true` from `view.dart`),
  - publish when `item.progress == -1` (completed),
  - publish when the canonical key has no previous publish (video change),
  - publish when `now - lastPublish[key] >= 10 minutes`,
  - otherwise skip publishing (still saved locally).
- Last-publish times are kept per key in `syncMetadata` as `lastPublish: {key: physicalMs}` with an in-memory mirror; persisted after each publish.
- `import` (both merge modes) and bootstrap publish with `force: true` so explicit imports and initial seeding are never suppressed by the 10-minute gate.
- `delete` / `clear` publish unconditionally as today.

### 2. Consecutive same-key dedupe (`_drain` in `local_history_sync.dart`)

Before appending a keyed event to `events-<writer_id>.jsonl`:

- Open the file with `RandomAccessFile`; if it exists with non-zero length and ends in `\n`, read the trailing bytes back to the previous `\n` and decode that last complete line.
- If the last line decodes to the same canonical `key` and both the old and new operations are keyed (upsert/delete), truncate the file to the byte offset where that line begins.
- Then append the new line as today (flush + close).
- Clear events (no key) never truncate. A malformed or incomplete tail is left untouched. Runs under the existing serialized `_queue`, so no interleaving.

Why safe: a later same-writer event for a key always carries a greater HLC, so the reducer's per-key maximum is the retained line; convergence is unchanged. The local write/outbox path is unaffected.

### 3. Slim event schema v3 + metadata hydration

#### Schema
- New writes emit version 3:
  ```json
  {"version":3, "event_id":"…", "node_id":"…", "hlc":{…},
   "op":"upsert", "key":"business|oid|cid",
   "history":{"business":"archive","oid":…,"bvid":"…","cid":…,"page":…,"epid":…},
   "view_at":…, "progress":…, "duration":…}
  ```
- `delete` / `clear` keep their existing shapes (version 3, same fields).
- `decode` accepts both version 2 (full `item`, unchanged) and version 3. v2 files stay readable forever and are never rewritten.

#### Reducer/water
- v2 winning upserts use `event.item` directly.
- v3 winning upserts build a `HistoryItemModel` skeleton from `history` + `view_at` + `progress` + `duration`.
- Skeleton display fields (`title`, `cover`, `authorName`, `authorMid`, `videos`, `uri`, …) are filled from a metadata cache keyed by canonical key; missing fields remain null placeholders and the key is queued for background hydration.
- Projection inclusion no longer drops a row solely for missing display metadata: `isValid` is relaxed to require `oid != null && viewAt != null` (structural identity), title no longer mandatory.

#### Metadata cache
- New key `LocalHistoryBoxKey.videoMeta` in the existing `GStorage.localHistory` box: `Map<key, Map<String,dynamic>>` enrichment (`title`, `cover`, `author_name`, `author_mid`, `videos`, `duration`, `uri`), plus a `lastAttempt` timestamp to bound retries.
- In `sync()`, after the projection is written, non-blocking `_hydrate(keys)` runs with bounded concurrency (≈4). For each key:
  - `archive` → `Api.videoIntro(bvid:)` → `VideoDetailData` (title, pic, owner, videos, duration, pages).
  - `pgc` → `SearchHttp.pgcInfo(epId:)` → episode fields.
  - On success: cache the enrichment, patch the matching row in `cacheList`, emit `_changes` (controller refreshes).
  - On failure: record `lastAttempt`; retry when the attempt is >10 minutes stale (guards against re-fetch storms on watcher ticks).
- Hydration is asynchronous and never blocks sync convergence or app startup.

## Backward compatibility and rollback

- v2 event files reconcile unchanged; a viewer running old code reads v3? It will reject v3 (unsupported version) and log—acceptable, since output is written only when the writer is new code. Existing v2 files are inert and readable by old and new code.
- Reverting app code restores local-only history exactly as before; v3 files are simply ignored by the old implementation.
- No Hive box changes: the metadata cache reuses the open `localHistory` box.

## Failure matrix

| Boundary | Failure | Required behavior |
| --- | --- | --- |
| Publish gate | `syncMetadata` write fails | Keep local save; publication state stale; next publish recomputes |
| Tail truncation | File unreadable / empty / incomplete tail | Skip truncation; append normally |
| Hydration | Network down / API error | Placeholder fields kept; `lastAttempt` recorded; retry after 10min |
| Hydration | No bvid (pgc) / no epid | Skip hydrate gracefully; row still visible |
| Projection | Event v3 with missing history | Rejected and logged (same as today) |
| Offline | No cache, no network | Row renders with placeholder title/cover; converges |
