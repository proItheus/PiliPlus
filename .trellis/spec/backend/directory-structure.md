# Backend Integration and Directory Structure

PiliPlus is a Flutter client, not a server application. In the Trellis `backend` layer, read “backend” as the client integration, transport, service, and local-persistence code. There is no server process, remote ORM, relational schema, or migration directory in this repository.

## Layer map

| Responsibility | Location | Local example |
|---|---|---|
| HTTP transport and response normalization | `lib/http/` | `Request` in `lib/http/init.dart`; `LoadingState<T>` in `lib/http/loading_state.dart` |
| HTTP domain facades | `lib/http/<domain>.dart` | `DynamicsHttp.articleList` in `lib/http/dynamics.dart` |
| gRPC transport | `lib/grpc/` | `GrpcReq.request` in `lib/grpc/grpc_req.dart` |
| gRPC domain facades | `lib/grpc/<domain>.dart` | `lib/grpc/audio.dart` |
| Other client transport | `lib/tcp/` | TCP clients and protocol-specific integration stay here rather than in widgets |
| App services | `lib/services/` | `lib/services/logger.dart`, account/download services |
| Local storage and utilities | `lib/utils/` | `GStorage`/`Pref`, `LocalSubscriptions`, and path helpers |
| Hand-written models | `lib/models/` and `lib/models_new/` | `UserInfoData.fromJson` and `LocalSubscription.fromJson` |
| Generated boundaries | `lib/grpc/bilibili/`, `*.g.dart`, `lib/utils/android/bindings.g.dart` | Protobuf, Hive adapter, and JNI output |

## Request-to-state boundary

A feature facade should expose a domain-shaped operation and keep transport details below the page layer. For example, `ArticleListController.customGetData` delegates to `DynamicsHttp.articleList(id)` (`lib/pages/article_list/controller.dart:31-33`), rather than constructing a Dio request in the controller. HTTP facades call `Request`, validate the API envelope, parse a model, and return `LoadingState<T>`; gRPC facades use `GrpcReq` and the same result contract.

The normal presentation flow is:

```text
lib/http/<domain>.dart or lib/grpc/<domain>.dart
  -> Request / GrpcReq
  -> LoadingState<T>
  -> GetX controller Rx state
  -> Obx view (Loading / Success / Error)
```

Durable local state follows `GStorage` boxes and `Pref` accessors. `GStorage.init()` in `lib/utils/storage.dart` creates the application-support Hive directory, registers adapters, and opens named boxes before `Request` and pages use them. Keep feature-specific key ownership in `lib/utils/storage_key.dart`; do not create a second ad-hoc storage mechanism.

## Generated-code boundary

Treat `lib/grpc/bilibili/**/*.pb.dart`, Hive adapter output such as `lib/models/user/info.g.dart`, and JNI output such as `lib/utils/android/bindings.g.dart` as generated or platform-owned. Change the source schema/annotation or generator input when applicable, then regenerate through the project workflow. These files are useful for understanding types but are not manual extension points.

## Avoid and common mistakes

- Do not place Dio, protobuf encoding, Hive writes, or retry policy in a widget or `GetxController`; call the domain facade and let the controller own presentation state.
- Do not describe this client as having a server database, ORM, SQL migrations, or backend routes. Local Hive boxes are the persistence boundary.
- Do not add relative `lib/` imports; `analysis_options.yaml` enables `always_use_package_imports` and `avoid_relative_lib_imports`.
- Do not hand-edit generated protobuf/Hive/JNI output or add handwritten fields there.
- Do not bypass `GStorage.init()` by opening boxes at arbitrary call sites; initialization and adapter registration belong to `GStorage`.
