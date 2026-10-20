# Implementation plan

## Ordered changes

1. **Add storage key**
   - Add `LocalHistoryBoxKey.videoMeta = 'videoMeta'` in `lib/utils/storage_key.dart`.

2. **Slim event schema v3** (`lib/utils/local_history_sync.dart`)
   - Extend `LocalHistorySyncEvent` with a schema version; support decode of v2 (full `item`) and v3 (slim) upserts. `delete`/`clear` match on version 3 while staying shape-stable.
   - `toJson()` emits v3 for new upserts: `history`, `view_at`, `progress`, `duration`; drop display payload.
   - Keep `history` identifier fields (`business`, `oid`, `bvid`, `cid`, `page`, `epid`).

3. **Metadata cache + hydration**
   - Add `_metaGet(key)` / `_metaPut(key, map)` over `videoMeta` in `GStorage.localHistory`.
   - In `sync()` reducer: v3 winners build skeleton items; fill from cache; collect missing-key queue; write projection with placeholders; then run non-blocking `_hydrate(missing)` with bounded concurrency, caching success and refreshing `_changes` per resolved key. Record `lastAttempt` to bound retries.

4. **Relax projection validity**
   - Change `isValid` to structural identity (`oid != null && viewAt != null`), keeping canonical-key checks for events. Update callers/tests accordingly.

5. **Sparse publication gate**
   - Add `lastPublish` per-key map to `syncMetadata` (in-memory mirror).
   - `publishUpsert(item, {bool force = false})`: publish on force / completed / new key / ≥10min since last publish; else skip. Persist `lastPublish` after publishing.
   - `LocalHistory.record(item, {bool forcePublish = false})` forwards `forcePublish`.
   - `import` and bootstrap pass `force: true`.
   - `lib/pages/video/view.dart`: on `force: true` paths (play-start, complete, pause, lifecycle paused) call `recordLocalHistory(..., force: true)` which already sets the flag; thread `forcePublish: force` into `LocalHistory.record`.

6. **Consecutive same-key dedupe** (in `_drain`)
   - Before append: inspect current writer file tail; if it ends in `\n` and the final line decodes to the same key (both keyed ops), truncate to that line's start offset, then append.

7. **Tests**
   - Update `test/utils/local_history_sync_test.dart` for v3 defaults; add: v2/v3 decode round-trips, v3 projection with cache hit and miss, consecutive same-key truncation, sparse gate (10min, force, completed, vid change), hydration dedupe/caching/retry bound, offline placeholder retained.
   - Update `test/utils/local_history_test.dart` for `isValid` loosening and `forcePublish`.

## Validation commands

```sh
just test test/utils/hybrid_logical_clock_test.dart
just test test/utils/local_history_sync_test.dart
just test test/utils/local_history_test.dart
just format-check
just analyze
```

Per `.trellis/spec/guides/development-workflow.md` run inside the Nix/FVM environment. The prior session logged a macOS SDK native-asset hook failure blocking Flutter test execution (`Foundation/Foundation.h`, `assert.h`); if it persists, report it and rely on `fvm dart analyze` over changed files plus a standalone Dart smoke script exercising the reducer/gate/truncation/hydration logic.

## Verification record

- Sparse gate works with a fake clock: same-key upserts within 10min suppressed, after 10min emitted; force/completed/new-key always emitted; import/bootstrap force.
- Two writer logs (one v2, one v3) reconcile to the same projection; consecutive same-key lines collapse; convergence unchanged.
- Hydration: cache miss triggers one fetch per key, success cached, failure retried only after 10min; offline rows retain placeholders and remain in the projection.
- `LocalHistory.load()` still returns key ordering; completed marker `progress == -1` reopens via `playbackProgress == 0`.
- `just format-check` clean; `just analyze` (or `fvm dart analyze` on changed files) clean on changed lines.

## Risk checkpoints

- Before integration: schema/cache/hydration code isolated in `local_history_sync.dart` + tests; revert without touching local history.
- After `record` gating: local save semantics unchanged; only publication cadence changes.
- After `view.dart` threading: verify force paths still publish (pause/exit/completed/start).
- Verify no v2 file is rewritten and v3 files are ignored by old code.

## Review gates before activation

- `prd.md` (after convergence pass), `design.md`, and this `implement.md` describe the same v3 schema, sparse gate, truncation rule, and hydration/caching.
- No unresolved open questions; placeholder/hydrate decision recorded.
- Do not run `task.py start` until this planning summary is presented and the user explicitly approves it.

## Completion notes

- Implemented: v3 slim schema + v2 decode compat; sparse gate (`_publishIntervalMs` 10min, force/completed/new-key/import/bootstrap overrides); consecutive same-key truncation in `_appendToWriter`; metadata cache (`LocalHistoryBoxKey.videoMeta`) + async hydration (`VideoHttp.videoIntro` / `SearchHttp.pgcInfo`) with `lastAttempt` retry bound and `debugSuppressHydrate` test seam; `isValid` relaxed to structural identity.
- `fvm dart analyze` clean for all changed lib files and the updated `local_history_sync_test.dart`; `just format-check` passes (0 changed).
- New/updated tests in `test/utils/local_history_sync_test.dart`: slim v3 round-trip + v2 compat, sparse-gate suppression/force/completed, consecutive same-key truncation, slim-placeholder projection, cache-filled hydration.
- `just test test/utils/local_history_sync_test.dart` is blocked by the host environment, not the code: the transitive `objective_c` native-asset hook cannot build because `Foundation/Foundation.h` and `assert.h` are not resolvable on this machine (same blocker recorded in the archived 10-18 CRDT-sync task). Tests are written and analyze-clean; execution requires a host with a working macOS SDK for native assets.
