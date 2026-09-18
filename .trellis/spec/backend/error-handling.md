# Integration Error Handling

Errors cross the integration boundary as data. Transport/domain code should normalize failures into `LoadingState<T>` so a controller can decide whether to retain, reload, or render the error. The standard state type is `Loading`, `Success<T>`, or `Error` from `lib/http/loading_state.dart`.

## HTTP contract

`Request` in `lib/http/init.dart` configures the shared Dio client, timeouts, compression decoding, cookies, and interceptors. Its `get`, `post`, and download methods catch `DioException` and return a `Response` whose map data contains a normalized `message`; callers should not each implement a separate Dio exception format.

A domain facade such as `DynamicsHttp` in `lib/http/dynamics.dart` calls `Request`, checks the API envelope (normally `res.data['code'] == 0`), and returns a typed state. Parsing failures at model boundaries should become `Error` rather than escaping as an untyped exception. Keep the result typed even when the upstream payload is permissive.

```dart
final LoadingState<ArticleListData> result =
    await DynamicsHttp.articleList(id: id);
if (result case Success(:final response)) {
  // hand the typed response to the controller
} else if (result case Error(:final errMsg)) {
  // controller/view decides how to present or retry
}
```

`LoadingState.dataOrNull` is safe for optional reads; `data` deliberately throws unless the state is `Success`. `LoadingState.toast()` exists for an explicitly user-facing state, but low-level transport should normally return the state instead of showing UI.

## gRPC contract

`GrpcReq.request` in `lib/grpc/grpc_req.dart` posts framed protobuf bytes through `Request`, requires `Grpc-Status: 0` for success, parses the response with the supplied generated message parser, and returns `Success` or `Error`. It translates `Grpc-Status-Details-Bin` into an optional code and message, with extra diagnostic status details only in debug mode. Invalid bytes and non-`Uint8List` data are errors, not successful empty payloads.

Generated parsers under `lib/grpc/bilibili/` define the wire types. A facade such as `lib/grpc/audio.dart` should preserve the typed `LoadingState` boundary rather than exposing raw bytes to the UI.

## Presentation and user reporting

`CommonDataController` and `CommonListController` (`lib/pages/common/`) update their Rx state on success/error and guard duplicate requests. `ArticleListPage._buildBody` in `lib/pages/article_list/view.dart:69-88` renders skeletons for `Loading`, content for `Success`, and `HttpError` with `onReload` for `Error`. This keeps retry UI in the presentation layer.

Use `HttpError`, an existing `LoadingState.toast()` call, or the established `SmartDialog` path only where a user-facing message is appropriate. Internal diagnostics belong in the logger/Catcher path, not in a transport helper's arbitrary toast.

## Avoid and common mistakes

- Do not treat any HTTP 2xx response as domain success without checking the API envelope.
- Do not let a controller cast raw `dynamic` response maps or catch all failures into an empty list; preserve `Error` and its message/code.
- Do not read `LoadingState.data` while the state is `Loading` or `Error`; use pattern matching or `dataOrNull`.
- Do not show a SmartDialog/toast from every low-level network failure; return `LoadingState` and let the page choose `HttpError` or retry behavior.
- Do not bypass `GrpcReq` by decoding generated protobuf bytes in a widget, and do not expose generated message parsing as presentation logic.
