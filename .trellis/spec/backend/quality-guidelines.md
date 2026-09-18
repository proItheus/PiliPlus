# Integration Quality Guidelines

Quality checks for this layer preserve the client data flow and the repository's analyzer boundaries. A normal feature should be reviewable as:

```text
facade -> Request/GrpcReq -> LoadingState<T> -> controller Rx -> Obx view
```

For local state, review `GStorage` initialization, adapter availability, key ownership, and write ordering as carefully as the network path.

## Analyzer and source boundaries

`analysis_options.yaml` includes `flutter_lints` and enables project rules including `always_declare_return_types`, `always_use_package_imports`, `avoid_relative_lib_imports`, `avoid_print`, `prefer_const_constructors`, `cancel_subscriptions`, `await_only_futures`, and resource-related checks. Follow these rules in new integration/service code instead of adding file-wide ignores.

The analyzer excludes generated protobuf (`lib/grpc/bilibili/**`), Hive output (`lib/**/*.g.dart`), platform directories, and build output. Those exclusions identify ownership boundaries, not permission to hand-edit generated files. Source models such as `lib/models/user/info.dart` retain `fromJson` and Hive annotations; generated adapters remain output.

## Async and resources

Await storage initialization before reading boxes (`lib/main.dart` calls `await GStorage.init()`), and await writes where the caller depends on durability. Dispose or close resources that your code owns: `CommonController.onClose` disposes its `ScrollController`; `GStorage.close` closes Hive boxes; `JsonFileHandler` serializes and flushes file operations. Cancel timers/subscriptions and avoid unawaited void async methods.

For a new facade, verify envelope and parse failure branches, preserve `LoadingState<T>`, and test the observable behavior at the controller boundary when a plausible bug is not otherwise covered. The repository's `test/utils/accounts/deleted_account_test.dart` demonstrates isolated Hive setup and asynchronous deletion ordering without touching the production storage directory.

## Review checklist

- Is the operation in the correct domain facade rather than a widget/controller?
- Are success, API error, transport error, and parse error represented distinctly?
- Are typed models and existing `Pref`/`GStorage` accessors reused?
- Is any generated or platform-owned file untouched?
- Are file handles, Hive boxes, timers, and stream subscriptions closed or serialized?
- Does the code preserve package imports and explicit return types?

## Avoid and common mistakes

- Do not hide analyzer failures with broad `// ignore` directives or edit generated files to satisfy a type mismatch.
- Do not add tests that only assert an implementation detail such as a field copy; prefer an observable loading/error, persistence, or lifecycle contract.
- Do not run network or Hive work synchronously in a widget build method.
- Do not create a second `LoadingState`/error abstraction when existing facades and controllers already share this contract.
- Do not claim a project-wide server quality gate, ORM migration test, or database transaction guarantee that cannot exist in this Flutter client.
