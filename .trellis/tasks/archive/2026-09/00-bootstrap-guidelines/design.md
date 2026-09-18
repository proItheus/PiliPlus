# Bootstrap Design: Project-Specific Trellis Guidelines

## Boundary

This task documents the existing PiliPlus architecture; it does not introduce or enforce a new architecture.

- **Backend layer in the Trellis scaffold:** the repository has no server process. Treat `backend` as the client integration and persistence layer under `lib/http/`, `lib/grpc/`, `lib/tcp/`, `lib/services/`, and `lib/utils/`.
- **Frontend layer:** Flutter UI and presentation state under `lib/pages/`, `lib/common/`, `lib/plugin/`, `lib/router/`, and `lib/main.dart`.
- **Generated and platform-owned code:** protobuf output under `lib/grpc/bilibili/`, Hive adapter output such as `lib/models/user/info.g.dart`, JNI output such as `lib/utils/android/bindings.g.dart`, and platform directories are references for boundaries, not manual-edit targets.

## Data-flow contracts to document

1. `lib/http/<domain>.dart` or `lib/grpc/<domain>.dart` exposes a domain-shaped static facade.
2. The facade builds an `Api` endpoint/request payload, invokes `Request`/`GrpcReq`, checks the remote response envelope, and returns `LoadingState<T>` (`Loading`, `Success`, or `Error`).
3. A page controller derives from a common GetX controller where appropriate, calls the facade, and updates `Rx` state.
4. The view observes that state with `Obx` and renders loading, success, or error branches; user-facing errors use existing `HttpError`, `SmartDialog`, or `LoadingState.toast()` patterns.
5. Durable local state flows through `GStorage`/`Pref` and Hive boxes rather than direct ad-hoc files or a second persistence library.

## Guideline-file mapping

### Backend

- `directory-structure.md`: integration, transport, service, model, persistence, and generated-code locations.
- `database-guidelines.md`: Hive CE as local persistence; no server ORM, schema, or migration layer.
- `error-handling.md`: response-envelope checks, `LoadingState`, parsing failures, Dio normalization, and user-facing reporting.
- `logging-guidelines.md`: `logger`, `Catcher2`, JSON log storage, debug/release levels, and secret-safe logging.
- `quality-guidelines.md`: analyzer rules, generated-code boundaries, async/resource cleanup, tests, and review checks.

### Frontend

- `directory-structure.md`: feature pages, shared widgets, controllers, models, router, services, and platform plugins.
- `component-guidelines.md`: `StatelessWidget`/`StatefulWidget`, const constructors, typed fields, composition, theme access, and accessibility.
- `hook-guidelines.md`: there is no Flutter hooks package; document `State` lifecycle, GetX controller lifecycle, and disposal instead.
- `state-management.md`: GetX `GetxController`, `Rx`/`.obs`, `Obx`, registration/tagging, and common controller pagination/loading state.
- `type-safety.md`: Dart null safety, typed `LoadingState<T>`, hand-written JSON models, Hive adapters, and generated protobuf boundaries.
- `quality-guidelines.md`: `flutter_lints`, project lints, package imports, tests, generated-file exclusions, and UI review checks.

## Trade-offs

- Keep the scaffold's backend/frontend filenames because Trellis task routing already references them, but explicitly translate their meaning to this Flutter client.
- Preserve existing mixed model generations (`lib/models/` and `lib/models_new/`) rather than claiming a migration that has not happened.
- Document observed permissive JSON parsing and some `dynamic`/`Object` API parameters as current reality; recommend typed values for new code only where the local boundary supports it.
- Keep shared thinking guides unchanged because they are already populated and are not project-specific templates.

## Compatibility and rollback

The deliverable is Markdown and task metadata only. It changes no runtime behavior, public Dart API, generated file, or persisted data format. Rollback is limited to reverting the task/spec documentation edits; no application migration is required.

## Verification design

- Read every final spec and both indexes for internal consistency.
- Search `.trellis/spec/` for template markers (`To be filled`, `To fill`, placeholder comments, and equivalent empty sections).
- Check that every referenced source path exists and every required guide is linked from its index.
- Validate the task metadata and manifests with the Trellis task script.
- Run the repository's relevant static/test commands after the docs are written; documentation-only changes must not alter Dart formatting or analyzer output.
