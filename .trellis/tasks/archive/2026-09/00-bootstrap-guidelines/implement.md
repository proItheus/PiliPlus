# Bootstrap Implementation Plan

## Ordered checklist

1. Write the five backend guides from the observed HTTP, gRPC, persistence, logging, and test patterns.
2. Write the six frontend guides from the observed Flutter page/widget/controller/model patterns.
3. Update `.trellis/spec/backend/index.md` and `.trellis/spec/frontend/index.md` so every listed guide has a project-specific description and no template status.
4. Create real `implement.jsonl` and `check.jsonl` entries for the backend and frontend indexes/guides so future Trellis sub-agents receive the relevant context.
5. Update the bootstrap task checklist after the spec content is complete.

## Source references to use

- `pubspec.yaml`, `analysis_options.yaml`, and `README.md` for runtime/platform/dependency facts.
- `lib/http/init.dart`, `lib/http/loading_state.dart`, `lib/http/dynamics.dart`, and `lib/http/api.dart` for API boundaries and error/result contracts.
- `lib/grpc/grpc_req.dart`, `lib/grpc/audio.dart`, and generated `lib/grpc/bilibili/**/*.pb.dart` for protobuf transport.
- `lib/utils/storage.dart`, `lib/utils/storage_pref.dart`, `lib/utils/storage_key.dart`, `lib/utils/local_subscriptions.dart`, and `lib/utils/accounts/account.dart` for local persistence and serialized writes.
- `lib/services/logger.dart`, `lib/utils/json_file_handler.dart`, `lib/utils/utils.dart`, and `lib/main.dart` for logging and exception reporting.
- `lib/pages/common/common_controller.dart`, `common_data_controller.dart`, and `common_list_controller.dart` for controller/state/lifecycle conventions.
- `lib/pages/article_list/controller.dart`, `lib/pages/article_list/view.dart`, `lib/pages/main/view.dart`, and `lib/common/widgets/**/*.dart` for feature/page/widget conventions.
- `lib/models/user/info.dart`, `lib/models_new/local_subscription.dart`, and `lib/models/**/*.dart` for model and serialization conventions.
- `test/utils/accounts/deleted_account_test.dart` for isolated Hive tests and async lifecycle assertions.

## Validation commands

Run from the repository root after implementation:

```bash
python3 ./.trellis/scripts/task.py validate 00-bootstrap-guidelines
flutter analyze
flutter test
```

Use a targeted placeholder/path scan in addition to the commands above. Do not run formatters over application code; no Dart source is in scope.

## Verification results

- `python3 ./.trellis/scripts/task.py validate 00-bootstrap-guidelines` passed; both manifests contain 18 curated entries.
- The specification scans passed: all required guides exist and link targets resolve; no template markers remain; every guide has an “Avoid and common mistakes” section; no application or generated files changed.
- Flutter 3.47.4 `analyze` and `test` were executed from a temporary SDK. Both reach the project and fail on existing private/custom Flutter and `material_ui` API mismatches in `lib/common/widgets/` and dependent pages; this documentation-only task does not alter those sources.

## Review gates

- Every required guide has at least two real path/symbol references where the subject has multiple examples.
- Every guide has an explicit “avoid”/anti-pattern section grounded in repository behavior.
- No guide claims a library, directory, workflow, or test policy absent from the repository.
- Generated files are identified as generated and are not presented as hand-authored extension points.
- Error/logging guidance distinguishes internal diagnostics from user-facing toasts.
- The hook guide does not describe React hooks or recommend adding `flutter_hooks`.
- The database guide does not invent migrations or a remote database.

## Rollback points

- If a rule cannot be supported by source evidence, remove or weaken that rule rather than changing application code.
- If a source path becomes invalid while writing, re-read the repository and update the reference.
- If validation fails because of task metadata, repair only the task artifacts; do not broaden the application scope.
