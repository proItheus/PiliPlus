# Repository Findings for Bootstrap Specs

## Repository shape

- Single Flutter package; no package subdirectories or server process.
- Runtime entry point: `lib/main.dart`; named routes are centralized in `lib/router/app_pages.dart`.
- Feature UI is under `lib/pages/<feature>/`; shared UI and adapted Flutter widgets are under `lib/common/`; player/platform integrations are under `lib/plugin/` and `lib/utils/<platform>/`.
- API and transport code is organized by domain in `lib/http/`, `lib/grpc/`, and `lib/tcp/`.

## Integration and persistence patterns

- `Request` in `lib/http/init.dart` owns a configured Dio client, retry/log interceptors, account cookies, and normalized Dio failure responses.
- HTTP facades return `LoadingState<T>` and normally branch on `res.data['code'] == 0`; parsing failures are caught at selected model boundaries and represented as `Error`.
- `GrpcReq.request` in `lib/grpc/grpc_req.dart` handles protobuf bytes/compression and returns the same `LoadingState<T>` contract used by HTTP.
- `GStorage.init()` opens named Hive boxes under the application-support directory and registers adapters before use. `Pref` wraps typed settings/defaults over those boxes.
- `LocalSubscriptions` serializes read-modify-write operations through a private future queue and ignores malformed imported entries; this is a concrete persistence concurrency pattern.

## Presentation patterns

- `CommonController` owns a `ScrollController` and disposes it in `onClose()`.
- `CommonDataController` and `CommonListController` own typed reactive loading state, prevent duplicate requests, and expose refresh/reload/load-more operations.
- `ArticleListController` obtains route parameters, starts loading from `onInit()`, and delegates network access to `DynamicsHttp`.
- `ArticleListPage` registers a tagged controller with `Get.put`, observes controller state using `Obx`, and switches on `LoadingState` to render skeleton/success/error branches.
- Reusable widgets use typed `final` fields, `const` constructors, theme-derived colors, callbacks, and composition; stateful widgets dispose controllers/listeners/timers in `dispose()`.

## Type, generation, and verification patterns

- Hand-written models parse remote maps with `fromJson` and often normalize optional numeric/list values; `LocalSubscription` validates its required positive ID and serializes with `toJson`.
- Hive model classes use `@HiveType`/`@HiveField` plus committed `.g.dart` adapters. Protobuf and JNI outputs are generated and should not be edited manually.
- `analysis_options.yaml` excludes generated/platform trees and enables Flutter lints plus explicit package-import, return-type, const, async, and resource rules.
- The committed account tests create a temporary Hive directory, register adapters, open a typed box, clear state between tests, close Hive, and delete the directory in teardown.

## Known absence / anti-pattern guidance

- No `flutter_hooks` or React hook APIs are present; the hook template must describe Flutter/GetX lifecycle instead.
- No ORM, SQL schema, migration directory, or server database is present; database guidance must not prescribe one.
- Avoid direct user-facing toasts from low-level transport code unless the existing API explicitly does so; prefer returning `LoadingState` for controllers/views to handle.
- Avoid editing generated protobuf/Hive/JNI output or adding relative `lib/` imports; both conflict with repository conventions.
