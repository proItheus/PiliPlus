# Technical design

## Smallest behavior gap

Local history is sampled at status transitions instead of at the player position stream, and its asynchronous Hive writes are neither awaited by playback transitions nor awaited by the local-history reader. The fix belongs at both boundaries: `VideoDetailPageV` owns the current video metadata and player lifecycle, while `LocalHistory` owns ordered durable writes.

## Data flow

```text
media_kit position/status
  -> VideoDetailPageV capture (metadata + current position)
  -> LocalHistory serialized read-modify-write
  -> Hive localHistory/cacheList
  -> LocalHistoryController waits for queued writes and loads
```

- Status `playing` creates/refreshes an entry immediately.
- Position callbacks checkpoint the current item only after a small position delta; this avoids one Hive full-list write per media-kit tick.
- Status pause, completion, app pause, route transition, and page disposal force a checkpoint.
- Completion stores `progress = -1`; all other snapshots store rounded seconds.
- `LocalHistory` continues to deduplicate by `business|oid|cid` and serialize complete list updates.

## Contracts and ordering

- `recordLocalHistory` returns the `Future<void>` from `LocalHistory.record`. Status callbacks await their own snapshot before continuing to completion/next-play handling. Position callbacks intentionally dispatch without blocking the media-kit stream; the shared storage queue preserves order.
- The page tracks the last key/position checkpoint locally. A key change always records; same-key position changes are throttled; forced boundaries always record.
- `LocalHistory.flush()` returns the current serialized queue. It does not permit new writes after the call; callers use it at the read boundary after route-transition snapshots have been enqueued.
- `LocalHistoryController` starts empty, waits for `LocalHistory.flush()`, then loads. Existing explicit refreshes remain synchronous after their awaited mutation calls.

## Lifecycle coverage

1. Playback start: status listener forces a record.
2. Active playback: position listener checkpoints at the configured interval.
3. User pause/completion: status listener forces a record; completion is awaited before `nextPlay`.
4. App pause: lifecycle callback forces a record.
5. Route push/pop/disposal: route callback/page disposal forces a record before listener removal/player disposal.

## Compatibility and rollback

No storage schema or key changes. Existing JSON list format, deduplication key, imports/exports, remote heartbeats, and file-source progress remain unchanged. Rollback is limited to reverting the page sampling/lifecycle changes and the queue flush/read wait; no migration is required.

## Risks

- Hive writes serialize the complete local-history list, so checkpointing must remain interval-based rather than per position event.
- Metadata for a newly switched source can arrive after the first `playing` event; later position checkpoints refresh the same key with the loaded metadata. No new player source or playlist contract is introduced.
