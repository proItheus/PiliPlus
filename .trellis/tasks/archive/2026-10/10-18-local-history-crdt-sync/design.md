# Technical design

## Behavior gap

`LocalHistory` currently stores one device-local Hive list. Synchronizing that list directly would let independent devices overwrite each other, and deleting a row by omission would let an older copy resurrect it. The feature needs an append-only replicated operation set whose deterministic projection is an LWW map keyed by the existing `business|oid|cid` identity.

The archived `localhist2` design is the starting boundary: writer-specific JSONL files, a Hive outbox, a shared-root watcher, lifecycle reconciliation, and a non-publishing Hive projection. Its wall-clock `event_at` ordering is replaced here by a persisted Hybrid Logical Clock (HLC) and an explicit LWW register model.

## Architecture and ownership

```text
LocalHistory mutation
  -> LocalHistory serialized queue
  -> HLC event creation + Hive outbox
  -> writer-specific JSONL append + flush
  -> shared folder transport (Syncthing/SMB/etc.)
  -> debounced watcher or explicit sync boundary
  -> typed event decode + deterministic event set
  -> LWW map reducer (upsert/delete per key + clear watermark)
  -> Hive cacheList projection
  -> LocalHistoryController Rx refresh
```

- `LocalHistory` remains the public local-history facade and owner of the serialized Hive projection queue.
- `LocalHistorySync` owns the event schema, canonical key/validity helpers, node identity, HLC persistence, outbox, shared-folder writer/reader, reducer, watcher, configuration, and change notifications.
- `HybridLogicalClock` owns only HLC arithmetic and serialization. It has no Hive, filesystem, or Flutter dependencies.
- `LocalHistoryController` owns the page subscription and reactive list. It does not parse event JSON or merge records.
- `GStorage`, `SettingBoxKey`, `LocalHistoryBoxKey`, and `Pref` remain the existing persistence/settings boundaries.

## Canonical identity

The replicated key is exactly the existing `business|oid|cid` value:

- `business` uses `archive` when the source field is null.
- `oid` is the required numeric object ID.
- `cid` is the numeric page/part ID or an empty suffix when null.
- `business` cannot contain `|`; the numeric components use their canonical decimal spelling.

`LocalHistory.keyOf` delegates to `LocalHistorySync.keyOf`, and the same owner validates incoming event keys and items. `bvid` is payload metadata only; it is not the CRDT key because it is absent for some PGC records and would merge distinct archive pages.

## Event contract

Use schema version `2`; version `1` wall-clock events from `localhist2` are rejected rather than interpreted as HLC events. Each complete JSONL record has exactly these fields for its operation:

```json
{
  "version": 2,
  "event_id": "uuid",
  "node_id": "stable-installation-uuid",
  "hlc": {"physical_ms": 1730000000000, "logical": 4},
  "op": "upsert",
  "key": "archive|123|456",
  "item": {"...": "HistoryItemModel.toJson()"}
}
```

`delete` has `key` and no `item`; `clear` has neither `key` nor `item`. Unknown fields, unsupported versions, invalid UUIDs, invalid HLC components, malformed canonical keys, invalid items, and operation/field mismatches are rejected and logged. A non-newline-terminated final line is retained as an unread tail and retried by the next read.

The event ID is the idempotency identity. A duplicate event ID with the same canonical payload is ignored on replay. Conflicting payloads for one event ID are treated as invalid for that ID, so readers do not choose based on directory listing order. Valid events are sorted by their total LWW order before reduction; file order is never semantic.

## HLC and LWW ordering

`HybridLogicalClock` stores `(physical_ms, logical)` and supports:

- `tick(now_ms)` for a local event: `physical_ms = max(now_ms, last.physical_ms)` and increment `logical` when the physical component does not advance.
- `observe(remote, now_ms)` after reading remote/outbox events, using the standard HLC maximum of local, remote, and wall time, then advancing the logical component so the next local event is strictly later than the observed timestamp.
- JSON conversion with non-negative bounded integer components.

Each installation has a stable random `node_id` persisted in `syncMetadata`. The HLC state is persisted after every local tick and after observing the greatest received timestamp. A running process has a separate `writer_id` for its append file, so process restarts do not overwrite another writer file. The LWW total order is:

```text
(hlc.physical_ms, hlc.logical, node_id, event_id)
```

The HLC pair supplies causal/clock ordering; `node_id` and `event_id` make concurrent equal pairs deterministic. The order is a total order, so selecting the maximum is deterministic. HLC does not claim synchronized wall clocks or protect against a device whose clock is deliberately far in the future.

A local event updates/persists the clock before it enters the outbox. Reconciliation observes the maximum valid remote timestamp before any bootstrap/local event is generated. This prevents a later local event from receiving an HLC lower than a timestamp already seen, including after a process restart.

## CRDT state and reducer

The replicated state is the join of two LWW components over the union of immutable events:

1. `latestByKey[key]`: the maximum `upsert` or `delete` event for that key.
2. `latestClear`: the maximum `clear` event, acting as a reset watermark.

For each key, an upsert is visible iff it is the maximum per-key event, is an upsert, and is strictly newer than `latestClear`. A delete is a retained tombstone and is never visible. A key event at or before the clear watermark is hidden. A later upsert or delete applies normally. The clear watermark preserves the existing “clear all known history” behavior without inventing a non-keyed deletion for every possible future key; concurrent events with a greater HLC remain governed by the same LWW order.

The reducer is pure over the validated event set. Set union is idempotent, commutative, and associative; component-wise maximum has the same properties; projection therefore converges regardless of file order, duplicate delivery, or replay count. Tombstones and clear events remain in source files because no compaction/retention is in scope.

Visible upserts are deduplicated by canonical key and sorted by descending `viewAt`, with the canonical key as the deterministic tie-break. The existing completed marker (`progress == -1`) remains in the payload and therefore reopens through `playbackProgress == 0`.

## Persistence, outbox, and file transport

Add `LocalHistoryBoxKey.cacheList`, `syncOutbox`, and `syncMetadata`; add `SettingBoxKey.localHistorySyncDirectory` and `Pref.localHistorySyncDirectory` with an empty default. Reuse `GStorage.localHistory` for all three local-history values.

Each publication is serialized by `LocalHistorySync`:

1. Create the event and advance/persist HLC state.
2. Append the event to `syncOutbox` before touching the shared folder.
3. Ensure the configured root and fixed `PiliPlus/local-history-sync` child are available.
4. Append one complete JSON line to `events-<writer_id>.jsonl`, flush, close the file, then remove that event from the outbox.
If an append fails after the writer file is opened, the process rotates to a fresh writer file before retrying; the old partial tail remains unread and the event stays durable in the outbox. The reader splits files on byte newlines and decodes each complete line independently, so an incomplete or invalid UTF-8 tail cannot discard earlier valid records.
5. On any directory or append failure, stop draining, keep the event in the outbox, and log the failure. The local Hive mutation remains visible.

Startup, configure, explicit `LocalHistory.sync()`, later local mutations, resume, and main-route return attempt the same drain path. Reading ignores unrelated files, malformed complete lines, and incomplete tails; it never rewrites source logs. Duplicate append after a crash is harmless because event IDs are idempotent.

`configure(root)` validates directory creation and append access before persisting the selected root. A failed change leaves the previous setting and active watcher untouched. Empty/null disables the watcher and transport without deleting local history, shared events, metadata, or retryable outbox events. A newly selected root is bootstrapped once: valid existing local items missing from the root's event set are emitted as upserts, then the merged projection becomes authoritative. Metadata records the root identity and bootstrap state separately from the stable node/HLC identity.
The reconciliation captures the selected root once for its drain, bootstrap, and projection reads. Root selection and bootstrap-marker invalidation are committed in the same sync queue operation; the watcher and `LocalHistory.sync` callback are advanced only after that state transition, so an in-flight reconciliation cannot mix two roots. Invalid cached rows are skipped, but bootstrap publication or persistence failures abort before the marker or cache projection is replaced; retryable outbox events remain durable.

## LocalHistory integration

All public mutations remain on `LocalHistory._queue`:

- `record` keeps the current keyed replace/sort/save behavior, then publishes an upsert for the accepted item.
- `import(merge: true)` keeps the existing `viewAt` winner rule and publishes only valid items that actually add/replace a local row; stale duplicates publish nothing.
- `import(merge: false)` saves the replacement list, publishes one clear event, then publishes replacement upserts so each replacement is newer than that clear.
- `remove` saves the local projection and publishes a delete even if the key was already absent.
- `clear` deletes the local projection and publishes a clear event.

Publication failures do not roll back a successful local save. `LocalHistory.sync()` waits inside the existing queue and invokes `LocalHistorySync.sync()`, whose reducer writes the cache projection without publishing another event and notifies `LocalHistorySync.changes`. Reconciled writes never call `record`, so watcher updates cannot create an event loop. `load()` remains synchronous and returns only the current Hive projection; callers that need shared freshness await `sync()`.

## Lifecycle and UI

After `GStorage.init()`, initialize `LocalHistorySync` with `LocalHistory.sync` as the external-change callback. On app resume and main-route return, schedule non-blocking sync. Shutdown first waits for any queued configuration transition to finish, then cancels the final watcher/debounce and drains external callbacks before awaiting the sync queue and closing `GStorage`; a transition cannot recreate a watcher after Hive closes.

The local-history controller awaits `LocalHistory.sync()` before its first and explicit refresh loads, listens to `changes`, and cancels the subscription in `onClose`. The local-history popup adds an automatic-sync action on Android and desktop using the existing directory picker. It displays disabled/enabled path state, configures then synchronizes the selected root, permits disable without deleting data, and reports configuration errors once. Sync failures remain logger diagnostics rather than merge dialogs or blocking playback.

## Compatibility and rollback

- The Hive `cacheList` JSON shape and public local-history APIs remain readable and unchanged.
- HLC event schema `version: 2` intentionally does not interpret old `localhist2` wall-clock records; a configured root is bootstrapped from the current local projection instead.
- No generated model, Hive adapter, unrelated setting export, or platform-owned file changes are needed.
- Reverting the app code restores local-only history. Existing event files/outbox entries are inert to the old implementation and do not alter the old `cacheList`.

## Failure matrix

| Boundary | Failure | Required behavior |
| --- | --- | --- |
| Event decode | Malformed line, old version, invalid HLC/key/item | Log and skip; preserve other events and source files |
| File tail | Incomplete final line | Ignore until a newline-complete retry |
| HLC persistence | Metadata write failure | Keep the local mutation; log and do not claim durable publication |
| Shared root | Missing, disconnected, read-only, or append failure | Keep local projection and outbox; retry later |
| Projection save | Hive write failure during reconcile | Keep source events/outbox; do not publish a derived projection |
| Watcher | Burst, cancellation, or callback exception | Debounce/isolate; never block the file-system callback |
| Process crash | Append succeeds before outbox removal | Replay duplicate event ID idempotently |
| Clock rollback | Wall time moves backward | HLC retains prior physical component and advances logical component |
