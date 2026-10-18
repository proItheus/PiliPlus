# Implementation plan

## Ordered changes

1. **Freeze the existing contracts and task context**
   - Keep the resolved canonical key `business|oid|cid`, `HistoryItemModel` JSON shape, `LocalHistory` queue, `load()` ordering, `progress == -1` behavior, and all existing callers.
   - Confirm all exported `LocalHistory` references before changing return types or adding `sync()`; do not modify generated models/adapters.
   - Add the backend/frontend specs and the task design/requirements to the implementation and check context manifests.

2. **Implement the pure HLC value and clock**
   - Add `lib/utils/hybrid_logical_clock.dart` with typed timestamp parsing/serialization, lexicographic comparison of `(physical_ms, logical)`, local `tick`, and remote `observe` arithmetic.
   - Test wall-clock rollback, repeated same-millisecond ticks, remote-future observation, and state round trips without Hive or filesystem dependencies.

3. **Implement the HLC LWW event owner**
   - Add `lib/utils/local_history_sync.dart` with version-2 event encode/decode, stable node identity, process writer identity, canonical key/validity helpers, total event ordering, deterministic duplicate handling, and the per-key upsert/delete plus clear-watermark reducer.
   - Add Hive-backed HLC/node metadata, durable outbox, append-and-flush writer, complete-line JSONL reader, malformed/tail handling, bootstrap, shared-root configuration, watcher debounce, retry, `changes`, and awaited close.
   - Keep all reducer logic independent of Hive projection writes and ensure all external errors are logged without replacing local state.

4. **Add storage/settings ownership**
   - Add `LocalHistoryBoxKey.cacheList`, `syncOutbox`, and `syncMetadata` plus `SettingBoxKey.localHistorySyncDirectory`.
   - Add `Pref.localHistorySyncDirectory` with an empty default; preserve `GStorage` box initialization, compaction, close, export, and clear behavior.

5. **Integrate `LocalHistory`**
   - Switch the cache key to `LocalHistoryBoxKey.cacheList`; delegate `keyOf` and validity to `LocalHistorySync`.
   - Publish upserts, deletes, and clear events inside the existing serialized queue while preserving local save/count semantics and JSON import/export.
   - Add non-recursive `LocalHistory.sync()` around `LocalHistorySync.sync()`. Ensure reconcile waits/drains correctly, writes the projection without publishing another event, and only notifies after the projection is saved.

6. **Wire startup, lifecycle, controller, and configuration UI**
   - Initialize sync after `GStorage.init()` and close it before Hive shutdown; schedule non-blocking sync on resume and main-route return.
   - Await sync in the local-history controller’s initial/explicit refresh, subscribe to change notifications, and cancel the subscription in `onClose`.
   - Add the automatic-sync popup flow on supported platforms using the existing directory picker, with configure/disable status and one-time configuration error reporting.

7. **Add focused regression coverage**
   - Add HLC unit tests for arithmetic, persistence shape, rollback, and remote observation.
   - Add isolated-Hive/shared-directory sync tests for independent writer union, same-key total ordering, clear/delete tombstones, resurrection, duplicate events, malformed lines, incomplete tails, bootstrap, outbox retry, version rejection, and no unrelated files.
   - Preserve/update local-history tests for ten unawaited records, import/export, completed playback, mutation queue ordering, and non-recursive sync projection writes.

## Validation commands and observable checks

Run from the repository Nix/FVM environment as required by `.trellis/spec/guides/development-workflow.md`:

```sh
just test test/utils/hybrid_logical_clock_test.dart
just test test/utils/local_history_test.dart
just test test/utils/local_history_sync_test.dart
just format-check
just analyze
```

If the focused test file is not yet committed during development, run the equivalent `fvm flutter test <file>` only through the documented `just test <file>` recipe after the file exists. Run the full `just test` suite before finish when the environment permits.

## Verification record

- `just format-check` passed with no formatting changes.
- Focused `fvm dart analyze` over the HLC, sync, local-history, storage, lifecycle, UI, and focused test files passed with no issues.
- A standalone HLC smoke script passed repeated ticks, wall-clock rollback, remote observation, and strict post-observation ordering.
- `just test test/utils/hybrid_logical_clock_test.dart test/utils/local_history_sync_test.dart test/utils/local_history_test.dart` and `fvm dart test test/utils/hybrid_logical_clock_test.dart` did not reach test execution: the transitive `objective_c` native-asset hook cannot find the macOS SDK (`Foundation/Foundation.h` and `assert.h`) in this environment.
- Full `just analyze` remains blocked by pre-existing project errors outside the changed lines, including unrelated errors in `lib/pages/dynamics/widgets/rich_node_panel.dart`, `lib/pages/dynamics_detail/view.dart`, `lib/pages/main/view.dart`, and generated Android shared-receiver bindings.

Exercise the actual changed behavior, not only wiring:

- Construct two writer logs in one shared directory and reconcile in different file orders; verify distinct-key union and one same-key winner.
- Verify HLC ticks remain strictly increasing after same-time calls and clock rollback, and that observing a remote timestamp makes the next local event greater.
- Verify delete tombstones block older upserts, clear hides older keys, later upserts resurrect, and duplicate replay is stable.
- Leave the shared root unavailable after a local mutation; verify the local item remains visible and the outbox drains after a valid root is configured.
- Verify a completed history item remains `progress == -1` and opens through `playbackProgress == 0`.
- Verify the sync directory contains only writer event files and no Hive/settings/lock artifacts.
- On a desktop run, configure two app instances against the same external folder and observe union, same-key conflict, delete/clear propagation, resurrection, disconnect retry, and controller refresh.

## Risk checkpoints and rollback points

- **Before integration:** HLC and event/reducer code plus tests are isolated; revert without changing local history.
- **After storage integration:** existing `cacheList` JSON remains readable; revert sync calls without a Hive migration.
- **After lifecycle/UI integration:** revert caller/controller/UI wiring independently; event files are ignored by the prior local-only code.
- **Before finish:** inspect every changed callsite, check that sync does not call public mutation APIs during reconcile, and confirm no generated or unrelated settings files changed.

## Review gates before activation

- `prd.md`, `design.md`, and this `implement.md` describe the same HLC schema, canonical key, tombstone semantics, and clear behavior.
- The implementation/check manifests contain real spec entries, not seed-only blank rows.
- No blocking product decision remains; the canonical key decision is recorded as `business|oid|cid`.
- Do not run `task.py start` until this planning summary is presented and the user explicitly approves it.
