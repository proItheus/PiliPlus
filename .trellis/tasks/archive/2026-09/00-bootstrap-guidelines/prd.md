# Bootstrap Task: Fill Project Development Guidelines

## Goal

Create source-backed Trellis guidelines for this single-package Flutter application so future implementation and review sessions follow PiliPlus conventions instead of generic backend/frontend templates.

## Confirmed repository facts

- The repository is a Flutter application (`pubspec.yaml`) targeting Android, iOS, iPad, Windows, and Linux, with Dart 3.13+ and Flutter 3.47.4.
- There is no server-side backend or relational database in this repository. The integration/persistence layer is implemented under `lib/http/`, `lib/grpc/`, `lib/tcp/`, `lib/services/`, and `lib/utils/`.
- HTTP domain facades such as `DynamicsHttp` call the shared Dio wrapper in `lib/http/init.dart`, convert API envelopes into `LoadingState` values from `lib/http/loading_state.dart`, and parse hand-written models under `lib/models/` or `lib/models_new/`.
- gRPC transport is split between generated protobuf files under `lib/grpc/bilibili/`, request helpers such as `lib/grpc/grpc_req.dart`, and domain facades such as `lib/grpc/audio.dart`.
- Local persistence uses Hive CE boxes initialized by `GStorage.init()` in `lib/utils/storage.dart`; settings are exposed through `Pref` in `lib/utils/storage_pref.dart`, and keys are centralized in `lib/utils/storage_key.dart`.
- UI pages live under `lib/pages/<feature>/`, commonly with `view.dart`, `controller.dart`, and feature-local `widgets/`; shared UI is under `lib/common/`. GetX controllers and observables are the established state pattern.
- Models use hand-written `fromJson`/`toJson` code, Hive adapters, and generated protobuf/Hive/JNI files. The only committed test is `test/utils/accounts/deleted_account_test.dart`, which uses `flutter_test` and an isolated temporary Hive directory.
- `analysis_options.yaml` enables `flutter_lints` plus project-specific rules including package imports, declared return types, const usage, and resource-management lints.

## Requirements

1. Fill every required file under `.trellis/spec/backend/` with the repository's integration, persistence, error, logging, and quality conventions.
2. Fill every required file under `.trellis/spec/frontend/` with the repository's Flutter directory, widget, lifecycle/state, type, and quality conventions. The existing `hook-guidelines.md` must explain the actual non-hook lifecycle pattern rather than inventing React conventions.
3. Include multiple concrete source references and short code examples where they clarify a rule. Examples must point to existing files and symbols.
4. Mark the indexes as project-specific and keep their links synchronized with the final file set.
5. Remove template comments, “to be filled” text, and generic placeholder guidance from the populated spec files. Do not change application behavior or introduce an alternative architecture.

## In scope

- `.trellis/spec/backend/` and `.trellis/spec/frontend/` guideline content and indexes.
- Planning, research, and completion metadata inside `.trellis/tasks/00-bootstrap-guidelines/`.
- The task checklist and context manifests needed for future Trellis sub-agents.

## Out of scope

- Refactoring Dart code to make it conform to the new documentation.
- Adding a server, ORM, relational schema, migration system, Flutter hooks package, or new state-management library.
- Rewriting existing project code, generated files, README content, or shared thinking guides.
- Expanding test coverage solely to support this documentation task.

## Acceptance criteria

- All five backend guideline files and all six frontend guideline files contain concrete, English, project-specific guidance with real file references and anti-patterns.
- The backend database guide accurately states that this repo has no server database and documents Hive CE local persistence, box initialization, adapter registration, key ownership, and serialized writes where applicable.
- The frontend state and hook guides accurately document GetX controllers/observables and Flutter `StatefulWidget` lifecycle management; no React/Flutter-hooks advice remains.
- Both index files list the final guides and no longer say “To fill” or “To be filled”.
- A repository-wide placeholder scan finds no template markers in `.trellis/spec/`.
- `python3 ./.trellis/scripts/task.py validate 00-bootstrap-guidelines` passes, and the selected Flutter quality command(s) complete without introducing source changes.

## Completion checklist

- [x] Fill backend guidelines
- [x] Fill frontend guidelines
- [x] Add code examples
- [x] Verify indexes, placeholders, manifests, and task metadata
