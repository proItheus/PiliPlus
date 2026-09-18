# Flutter Frontend Directory Structure

PiliPlus is organized as a single Flutter package. Feature pages live under `lib/pages/<feature>/`; shared presentation utilities live under `lib/common/`; route registration is centralized in `lib/router/`; integration, services, models, and platform/player code remain in their own layer.

## Locations and responsibilities

| Location | Responsibility | Example |
|---|---|---|
| `lib/pages/<feature>/` | Feature view, controller, and local widgets | `lib/pages/article_list/view.dart`, `controller.dart`, `widgets/` |
| `lib/pages/common/` | Reusable GetX controller bases | `CommonController`, `CommonDataController`, `CommonListController` |
| `lib/common/` | Shared widgets, constants, refresh/error components | `lib/common/widgets/loading_widget/http_error.dart` |
| `lib/router/` | Named GetX route declarations | `lib/router/app_pages.dart` (`Routes.getPages`) |
| `lib/models/`, `lib/models_new/` | Hand-written API/domain models and serialization | `UserInfoData`, `LocalSubscription` |
| `lib/http/`, `lib/grpc/`, `lib/tcp/` | Client integration facades and transport | `DynamicsHttp`, `GrpcReq` |
| `lib/services/` | App-wide services and diagnostics | `LoggerUtils`, account/download services |
| `lib/plugin/`, `lib/utils/<platform>/` | Player and platform-specific integration | media/player and JNI bindings |

A route in `app_pages.dart` should create a page, while the page obtains its controller and composes widgets. `ArticleListPage` registers `ArticleListController` with a route-parameter tag and delegates data access to the controller; it does not construct a Dio request.

## Feature flow

Use the established vertical flow for new remote-backed screens:

```text
page controller -> domain facade -> LoadingState<T>
             -> Rx state -> Obx in view -> loading/content/error widgets
```

Use `Obx` only around the state-dependent subtree. In `lib/pages/article_list/view.dart`, the header observes `_controller.list.value` and the body observes `_controller.loadingState.value`; `_buildBody` maps each `LoadingState` variant to a skeleton, grid, or `HttpError`.

## Avoid and common mistakes

- Do not put feature files in a new top-level directory when the existing `lib/pages/<feature>/` or `lib/common/` location fits.
- Do not register routes in individual views or navigate by duplicating route names; use `Routes.getPages` in `lib/router/app_pages.dart`.
- Do not move integration, Hive, or platform code into `lib/common/widgets`; keep UI and client boundaries explicit.
- Do not create a controller per stateless leaf widget merely to hold a callback; use typed fields and composition.
- Do not manually edit generated protobuf, Hive, or JNI files while implementing a UI feature.
