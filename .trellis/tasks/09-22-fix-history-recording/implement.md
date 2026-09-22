# Implementation plan

1. Update `LocalHistory` with a public queue-drain method and preserve the existing serialized read-modify-write contract.
2. Change `LocalHistoryController` initialization to await the queue drain before its first load, preventing a newly opened history page from observing a partial prefix.
3. Update `VideoDetailPageV` to:
   - return/await local-history writes from status callbacks;
   - checkpoint player positions at a bounded interval;
   - force snapshots for pause, completion, app pause, route transitions, and disposal;
   - keep file sources and remote heartbeat behavior out of this path.
4. Add or update a focused test for the observable queued-write/read contract if the existing Flutter test setup can isolate the Hive box without global-state coupling.
5. Run the focused test or a throwaway Hive smoke scenario, then `just format-check` and `just analyze`; run the relevant Flutter test command if a permanent regression test is added.
6. Review the diff for generated-file and scope violations, update the relevant spec if the lifecycle/serialized-write lesson is project-wide, and commit the completed fix.

## Validation commands

- `just format-check` (passed locally).
- `fvm dart analyze lib/utils/local_history.dart lib/pages/local_history/controller.dart lib/pages/video/view.dart test/utils/local_history_test.dart` (passed with three pre-existing `cascade_invocations` infos in `local_history.dart`).
- `just analyze` remains blocked by pre-existing `lib/common/widgets/draggable_sheet/dyn.dart` errors against the installed Flutter SDK; no changed-file errors appeared in targeted Dart analysis.
- `just test test/utils/local_history_test.dart` is reserved for CI: local Flutter test execution reaches the `objective_c` native-assets hook and fails because this workstation has no Xcode/macOS SDK.
- A real playback smoke check covering multiple consecutive playlist items, pause/seek, route leave, and local-history reload is CI/device work; do not run a local platform build here.

## Risk/rollback points

- Before changing source: the current history implementation and player lifecycle are documented in `prd.md`.
- After storage boundary change: verify old exported/imported JSON still loads and writes.
- After page lifecycle change: verify no listener is left registered after `dispose` and no file-source path records local history.
