# Lifecycle Guidelines (No Flutter Hooks)

This repository does not use React hooks or the `flutter_hooks` package. Do not invent hook APIs or prescribe adding a hooks dependency. Use Flutter's `StatefulWidget` lifecycle and GetX controller lifecycle already present in the codebase.

## Flutter State lifecycle

`ArticleListPage` in `lib/pages/article_list/view.dart` is a `StatefulWidget`; `_ArticleListPageState` stores page-local layout state (`padding`) and mixes in `GridMixin`. Flutter calls `build` with a `BuildContext`, and the page reads theme/media-query values there. If a widget owns a `TextEditingController`, `ScrollController`, listener, timer, or stream subscription, initialize it at the appropriate state lifecycle point and release it in `dispose()`.

Do not perform one-time network work from `build`, because Flutter may rebuild it. Put page data loading in the GetX controller's `onInit`, as `ArticleListController.onInit` calls `queryData()` once after `super.onInit()`.

## GetX controller lifecycle

A page controller extends `GetxController` directly or a common controller base. `CommonController.onClose` disposes its `ScrollController` before calling `super.onClose()`. Controller registration belongs to the page/route boundary; `ArticleListPage` uses `Get.put(ArticleListController(), tag: Get.parameters['id']!)`, so two parameterized pages do not share accidental state.

Use `onInit` for initial state setup and first query, `onClose` for controller-owned cleanup, and `dispose` for Flutter `State` resources. Choose the owner deliberately: a widget-local animation/listener follows `State`, while page data, pagination, and `Rx` values follow the GetX controller.

## Playback history lifecycle

`VideoDetailPageV` owns the player listeners and the current non-file history snapshot. Status `playing` starts a history item; position callbacks checkpoint only while `_historyPlaying` is true and use a bounded interval; pause, completion, app pause, route push, and disposal force a snapshot. A completion snapshot is awaited before the existing automatic next-play branch runs.

When a media source changes, compare the constructed `business|oid|cid` key with the last persisted item. Drop a stale position callback for a mismatched key; a non-start boundary persists the previous item; the next `playing` callback persists the previous item before recording the new key. This prevents an asynchronous pause/source-ID update from writing the old position into the new item.

The local-history controller owns the read boundary: initialize its reactive list empty, await `LocalHistory.flush()` in `onInit`, and load only if the controller remains open. File-source playback continues through its existing `watchProgress` path and must not enter this history branch.

## Avoid and common mistakes

- Do not import or recommend `flutter_hooks`, React `useState`, `useEffect`, or custom hook conventions; they are absent from `pubspec.yaml` and source.
- Do not start requests or mutate state from `build`; rebuilds are not initialization callbacks.
- Do not dispose a GetX controller's resources from an unrelated widget, or leave a `State`-owned listener alive after unmounting.
- Do not register parameterized controllers without the existing tag strategy when multiple route instances can coexist.
- Do not assume `onInit` is a substitute for awaiting asynchronous prerequisites; storage/network initialization still follows `main.dart` startup ordering.
- Do not use the initial `playing` position as the only progress snapshot; ordinary position updates and explicit stop boundaries carry the actual progress.
- Do not let position callbacks continue writing after pause/completion/route disposal, or let a mismatched source key overwrite the prior item's final snapshot.
