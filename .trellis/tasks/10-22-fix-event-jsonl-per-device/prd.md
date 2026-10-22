# Fix event-<id>.jsonl per-session variation on same device

## Goal

Make `events-<id>.jsonl` writer-file identity stable per installation/device across app sessions, so the same device does not create a new event file on every launch, while preserving existing durability and append-failure recovery.

## Background / confirmed facts

- Writer files are named `events-$_writerId.jsonl` (`lib/utils/local_history_sync.dart:744`).
- `_writerId` is initialized to a fresh v4 UUID on every process start and never persisted (`lib/utils/local_history_sync.dart:184`); on append failure it rotates by regenerating a UUID (line 748). Result: one new event file per app session on the same device.
- Device/node identity `_nodeId` is already stable: loaded from syncMetadata `node_id`, generated + persisted on first run (`lib/utils/local_history_sync.dart:227-243`), validated by `_isUuid`.
- `_readEvents` reconciles every `events-*.jsonl` file (`lib/utils/local_history_sync.dart:809-814`), and the CRDT reducer dedupes by `event_id`, so file names are not semantically significant for convergence — this change is naming/identity only.
- Original CRDT design (archived task `<10-18-local-history-crdt-sync`) intentionally used a per-running-process `writer_id` "so process restarts do not overwrite another writer file" and documented failure rotation. This task changes `writer_id` from per-process to per-install persistence; rotation is kept, and the rotated id is persisted.
- Event schema v3, Hive outbox, HLC, and the reducer are unaffected. Tests use explicit writer labels (`writer-a`/`writer-b`/`writer-c`) and never reference `_writerId`.

## Requirements

- R1: A stable writer id is persisted in syncMetadata (same `localHistory` box as `node_id`) and reused across app launches on the same device; first run after upgrade generates and persists it.
- R2: If appending to the current writer file fails, rotate to a fresh writer id and persist the new id, so subsequent publishes continue on the rotated file (no drift back to the old id on later sessions).
- R3: Existing per-session `events-*.jsonl` files remain valid input to `_readEvents`; no cleanup or migration of legacy files is required.
- R4: Event schema, event fields, and outbox behavior are unchanged.

## Acceptance criteria

- AC1 (stability): In a test that runs `LocalHistorySync.initialize` → publish → `close()` → re-`initialize` → publish (two simulated sessions), the second publish appends to the same `events-<id>.jsonl` file as the first, and syncMetadata `writer_id` is unchanged.
- AC2 (rotation persistence): With an injected append failure on the current writer file, a fresh writer id is persisted in syncMetadata; after `close()` / re-`initialize`, subsequent publishes go to the rotated file name.
- AC3 (regression): Multiple pre-existing `events-*.jsonl` files (different writers) still reconcile to the same projection as today (existing multi-writer tests pass).
- AC4 (suite): `fvm flutter test test/utils/local_history_sync_test.dart` passes.

## Out of scope

- Deleting/compacting legacy per-session event files.
- Changing the event schema (v3 remains) or the CRDT reducer/order.
- Altering `node_id` semantics or multi-device merge behavior.
- iOS/web transport support (unchanged; `supported` gate).

## Key decisions

- D1: Persist `writer_id` (new syncMetadata field) rather than deriving the file name from `node_id`. Rationale: preserves the documented append-failure rotation recovery and keeps writer identity (log ownership) separate from node identity (CRDT actor). Tradeoff: one extra syncMetadata field; slightly more surface than reusing `node_id`.
- D2: Keep rotation on append failure and persist the rotated id. The alternative (drop rotation, always write the `node_id`-named file) would permanently block publication if the writer file path becomes persistently defective (e.g. a directory replacing the file path).

## Risks / deferred

- Upgrading devices have accumulated per-session files; they remain readable but stay on disk (deferred cleanup, out of scope). No functional impact.
- No blocking deferred items.
