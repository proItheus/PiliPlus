# Implement CRDT local history sync

## Goal

Synchronize non-file local playback history across app installations that share a user-selected folder, with deterministic convergence under concurrent offline writes. The replicated value is an LWW map whose entries are keyed by a stable video identity and whose values are either a history item or a tombstone.

## Confirmed facts

- The current branch stores local history as one Hive `cacheList` JSON list and serializes mutations through `LocalHistory._queue`.
- The existing local-history contract deduplicates by `business|oid|cid`; the player constructs that identity when recording playback.
- `History` also contains `bvid`, but PGC records may not have one, and `cid`/`page` distinguish playback units in the current code.
- The archived `local-history-sync` design and implementation exist on the `localhist2` branch, not in the current branch. That design uses writer-specific JSONL files, a Hive outbox, a watcher, and tombstone events, but orders events by wall-clock milliseconds plus UUID.
- The current branch has no tracked sync implementation. An ignored sync test file is present from the other branch and is reference material, not an existing production contract.

## Requirements

### CRDT semantics

- Use an LWW register per stable video key. Every mutation is an immutable upsert or tombstone carrying a Hybrid Logical Clock (HLC) timestamp and a unique event ID.
- HLC timestamps MUST be monotonic for a writer, MUST advance on observed remote timestamps, and MUST provide a deterministic total order for equal physical/logical components using a writer identifier.
- Merge MUST be idempotent, commutative, and associative: replay order, duplicate events, and independent writer files cannot change the converged winner.
- A tombstone MUST win over an older upsert and remain in replicated state so an old event cannot resurrect a deleted item. A later upsert MAY resurrect the key.
- Preserve complete tombstone state in the shared log; do not infer deletion only from absence in the Hive projection.

### Local history and transport

- Preserve the existing `LocalHistory` APIs, serialized read-modify-write behavior, progress/completed playback semantics, JSON import/export, and synchronous projection-only `load()` behavior.
- Publish local mutations through a durable Hive outbox before attempting to append to a process-specific JSONL event file under the configured shared root. Failed appends remain retryable; duplicate event IDs are harmless.
- Reconcile all complete valid events from every writer file into the Hive projection without republishing reconciled data. Malformed records and incomplete final lines MUST not discard valid records.
- Keep shared-folder configuration, watcher debounce, lifecycle retries, and controller refreshes inside the app. Do not sync Hive boxes, settings, cookies, or unrelated files.
- Preserve local-only behavior on unsupported platforms and when synchronization is disabled. Do not add retention or compaction in this task.

### UI and lifecycle

- Initialize synchronization after storage startup, retry on startup/resume/main-route return/local-history reads and mutations, and close watcher resources before Hive closes.
- The local-history controller MUST await the sync read boundary for initial and explicit refreshes, react to external changes, and release its subscription.
- Provide the existing local-history popup's automatic-sync configuration flow using the existing directory picker; allow selecting a shared root or disabling synchronization without deleting local history. No merge/conflict dialog is needed.

## Acceptance Criteria

- [ ] Two independent writer logs converge to the same visible projection regardless of file/replay order, with distinct keys retained and one deterministic winner per key.
- [ ] HLC ordering remains monotonic across local writes and observed remote events; same-physical-time concurrent events still have a deterministic writer/event tie-break.
- [ ] A tombstone hides an older upsert on every reader, survives replay and restart, and a later upsert resurrects the key.
- [ ] Duplicate events, malformed lines, and incomplete final lines do not alter valid convergence; a later completed line is readable.
- [ ] A failed shared-directory append keeps the local record visible and the outbox pending until a later retry succeeds.
- [ ] Existing record/import/remove/clear, JSON import/export, completed playback reopening, and the ten-unawaited-record queue behavior remain valid.
- [ ] The controller, configuration UI, startup/resume lifecycle, and resource cleanup follow the existing Flutter/GetX ownership boundaries.
- [ ] Focused sync/local-history tests, formatting, and analysis pass through the documented repository recipes; a desktop smoke scenario exercises independent writers, same-key conflicts, tombstones, resurrection, and retry.

## Scope boundary

This task owns the app-side HLC LWW event model, tombstone reducer, outbox, shared-folder reader/writer, watcher, local-history integration, configuration UI, lifecycle triggers, and focused regression coverage. It does not install/configure Syncthing or SMB, implement a network protocol, sync unrelated application data, add network-clock verification, or change iOS/iPad behavior beyond keeping it local-only.

## Key decision

Use the existing `business|oid|cid` identity as the canonical CRDT key. It matches the player’s playback boundary, distinguishes archive pages/parts, and remains available for PGC records without `bvid`.
