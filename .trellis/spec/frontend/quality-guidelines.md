# Flutter Frontend Quality Guidelines

Review UI changes against the actual Flutter/GetX patterns and analyzer configuration, not generic web conventions. `analysis_options.yaml` includes `flutter_lints`, requires package imports and declared return types, and checks const usage, async/resource handling, and common Flutter style rules.

## Pre-merge checks

For a page or widget change, inspect the complete loading/error/empty path, controller lifecycle, route parameters, and resource cleanup. Confirm that the view observes typed state through `Obx`, that a retry callback reaches the controller, and that a controller cannot issue duplicate refresh/load-more requests. `ArticleListPage` and `ArticleListController` are the reference vertical slice.

Prefer `const` constructors/literals where they are valid, `final` fields, explicit return types, and package imports such as `package:PiliPlus/...`. Keep generated files and platform directories outside manual UI edits; analyzer exclusions in `analysis_options.yaml` include `lib/grpc/bilibili/**`, `lib/**/*.g.dart`, and native platform trees.

## Lifecycle and interaction checks

A `StatefulWidget` must release every listener/controller/timer/subscription it owns. A GetX controller must release controller-owned resources in `onClose`; `CommonController` disposes its `ScrollController`. Verify mounted/lifecycle-sensitive async callbacks and avoid work in `build`.

Use theme-derived colors and typography, safe-area values, semantic/selection-friendly text, and shared widgets such as `HttpError` rather than duplicating behavior. Check narrow/large layouts where the existing page uses grid or sliver helpers and preserve route tags for parameterized instances.

Tests should defend an observable behavior or boundary. The existing `test/utils/accounts/deleted_account_test.dart` shows isolated Hive setup/teardown and tests async deletion ordering; do not add tests merely to assert field forwarding or widget implementation text.

## Avoid and common mistakes

- Do not apply web/React review rules or introduce Flutter hooks; this is a Flutter/GetX application.
- Do not suppress analyzer warnings globally, use relative `lib` imports, or rely on `print` for diagnostics.
- Do not treat a successful build as proof of correct loading/error behavior; exercise the state transitions and retry path relevant to the change.
- Do not leave controllers, streams, timers, or listeners alive after a route/widget is gone.
- Do not modify generated protobuf/Hive/JNI output or unrelated platform code to make a frontend change compile.
