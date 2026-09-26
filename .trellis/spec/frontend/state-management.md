# GetX State Management

GetX controllers and observables are the established presentation state pattern. A controller owns feature state and delegates integration to a domain facade; a view observes only the reactive values it renders.

## Common controller bases

`CommonController<R, T>` in `lib/pages/common/common_controller.dart` extends `GetxController`, owns a `ScrollController`, exposes `Rx<LoadingState> loadingState`, and provides `onRefresh`, `onLoadMore`, and `onReload`. `CommonDataController` initializes `LoadingState<T>.loading().obs`, prevents duplicate requests with `isLoading`, and updates state after a typed facade response. `CommonListController` adds page/end/footer state, appends successful load-more results, and suppresses load-more calls after `isEnd`.

A concrete controller declares the response and item types and supplies the facade operation:

```dart
class ArticleListController
    extends CommonListController<ArticleListData, ArticleListItemModel> {
  final id = Get.parameters['id']!;

  @override
  void onInit() {
    super.onInit();
    queryData();
  }

  @override
  Future<LoadingState<ArticleListData>> customGetData() =>
      DynamicsHttp.articleList(id: id);
}
```

Use `.obs`/`Rx<T>` for state that a view must react to, such as `loadingState` and the article `list`. Keep immutable configuration and one-time route parameters as regular typed fields when reactivity is unnecessary.

## View observation

Use `Obx` around the smallest state-dependent subtree. `ArticleListPage.build` observes `_controller.list.value` for its header and `_controller.loadingState.value` for its body. `_buildBody` pattern-matches `Loading`, `Success`, and `Error` and passes `onReload` back to the controller. This preserves the data flow `LoadingState -> Rx -> Obx` and avoids rebuilding unrelated layout.

Register controllers through GetX at the page/route boundary (`Get.put`, with a parameter tag when required). Reuse the common lifecycle and pagination behavior rather than reimplementing request guards in every feature.

## Multi-source paginated feeds

When a screen merges independent paginated timelines, keep source cursors and merge buffers in the controller rather than the view:

- Deduplicate persisted source IDs in deterministic saved-list order before issuing requests.
- Keep one offset, `hasMore`, buffer, and failure marker per source; advance an offset only after a successful page, and stop when the API returns a terminal or unchanged offset.
- Keep emitted non-null item IDs in controller state across load-more calls; clear cursors, buffers, failures, and emitted IDs on refresh so the current persisted source list is re-read.
- Return a typed aggregate batch containing items, `hasMore`, and failed sources through `LoadingState`.

Partial source failures remain a successful feed batch with a retryable warning when content exists; an all-source failure before any content uses the normal `Error` branch. This keeps the shared request guard and pagination lifecycle while preventing stale pages and duplicate items.

```dart
return Success(
  FeedBatch(items: items, hasMore: hasMore, failedSources: failedSources),
);
```

## Avoid and common mistakes

- Do not store network calls or raw API maps directly in a view; expose typed `LoadingState<T>` from a controller.
- Do not assign to an Rx's wrapper instead of its `.value`, and do not mutate a list without refreshing/notifying the observable when the existing pattern requires it.
- Do not issue duplicate requests: honor `isLoading`, `isEnd`, and the common controller refresh/load-more methods.
- Do not wrap an entire app/page in `Obx` when only a body or header depends on one value.
- Do not create a second state-management library, event bus, or “hook” layer for a feature.
