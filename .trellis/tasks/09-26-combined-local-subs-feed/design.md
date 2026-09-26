# Technical design

## Change boundary

Add a remote-backed local-subscription dynamic feed without changing local-subscription storage, the existing management page, Bilibili API facades, generated models, or the authenticated account-subscription flow. The feed owns only aggregation state and presentation; management remains the source of truth for the saved creator list.

Expected production files:

- `lib/pages/local_subscription_feed/controller.dart` — multi-source cursor state, aggregation, pagination, and typed loading state.
- `lib/pages/local_subscription_feed/view.dart` — feed screen, empty/error/partial-failure states, refresh, and management navigation.
- `lib/router/app_pages.dart` — named route for the feed.
- `lib/pages/subscription/view.dart` and `lib/pages/mine/controller.dart` — existing local-subscription entry points target the feed.
- `test/pages/local_subscription_feed/controller_test.dart` or a feature-local aggregation test — focused merge and cursor behavior coverage.

The existing `lib/pages/local_subscription/` controller and view remain the management surface and are not moved or rewritten.

## Data flow

```text
LocalSubscriptions.load()
        -> unique local creator IDs in saved-list order
        -> one dynamic cursor per creator
        -> MemberHttp.memberDynamic(mid, offset) requests
        -> buffered source items + per-source offsets
        -> stable newest-first k-way merge
        -> CommonListController loading state
        -> Obx feed slivers -> DynamicPanel
```

`MemberHttp.memberDynamic` is reused because it already provides paginated creator timelines and does not require the current account to follow the creator. `DynamicPanel` remains the only dynamic-card renderer, so creator identity and existing dynamic navigation stay consistent.

## Controller and pagination

`LocalSubscriptionFeedController` extends `CommonListController<_FeedBatch, DynamicItemModel>` to retain the repository's request guard, refresh/load-more lifecycle, `LoadingState`, and scroll-controller cleanup. Its `customGetData` returns a feature-private batch containing the next merged chunk, whether more data remains, and source failures. `customHandleResponse` updates the observable partial-failure state and the end flag.

The controller keeps a private cursor per unique `mid`:

- saved-list index for deterministic tie-breaking;
- current `offset` and `hasMore` state;
- buffered `DynamicItemModel` values and the next buffer index;
- stable dynamic IDs already emitted;
- an error marker when that source fails.

Refresh resets all cursors, re-reads `LocalSubscriptions.load()`, and fetches the first page for all sources concurrently. A batch is filled with a k-way merge: compare the head item of each non-empty source buffer, emit the newest item, then advance that source. When a source buffer is exhausted, fetch its next page before selecting the next item; fetch multiple exhausted sources concurrently when the merge needs them. The UI batch size is fixed so load-more appends bounded work rather than loading an entire creator history.

Ordering uses `modules.moduleAuthor.pubTs` descending. Missing timestamps compare as zero. Equal timestamps retain saved-list order, then original source-page order. Non-null `idStr` values are deduplicated across source pages; null IDs are retained using their source position so malformed items cannot suppress unrelated content.

A source whose request fails is marked unavailable for the current load and does not block successful sources. The controller exposes the failed creator names/IDs as reactive state; the view shows a compact retryable warning. A refresh clears failures and retries every source. If every source fails before producing content, the controller exposes the normal `Error` state instead of an empty success state.

## Screen and navigation

`LocalSubscriptionFeedPage` follows the existing member-dynamics vertical slice:

- `SimpleScaffold` with a feed title, refreshable `CustomScrollView`, and management action;
- `Obx` around the loading/content subtree only;
- `dynSkeleton` for loading;
- `SliverList` or the existing dynamics waterfall setting for content;
- `DynamicPanel` for every item;
- explicit local-list-empty, no-content, partial-failure, and all-source-error branches using existing `HttpError`/theme conventions;
- safe-area bottom padding and the existing refresh indicator.

The management action navigates to `/localSubscription` and refreshes the feed when that route returns. The existing `/localSubscription` route continues to list, remove, and clear creators. The local-subscription actions in the account subscription page and Mine page navigate to the new feed route, making the feed the normal entry point without breaking the management deep link.

## Failure and compatibility behavior

- An empty saved list is a local empty state with a direct management action; it performs no network requests.
- A non-empty saved list whose creators have no dynamics is a distinct no-content state with refresh and management access.
- Partial source errors preserve successful items and offer refresh; failed sources are not removed from storage.
- All-source failure uses the shared retryable error presentation.
- No feed data is persisted or cached, and no background refresh or notification behavior is added.
- Existing account subscription/folder APIs and local subscription serialization remain untouched.

## Verification strategy

Use a focused unit test with an injected dynamic-page fetcher and deterministic fake source pages to prove source-page cursor advancement, newest-first interleaving, timestamp tie-breaking, duplicate suppression, exhausted-source handling, and partial/all-source failure behavior. Verify the Flutter surface with the repository's standard format check, analyzer, targeted test, and a manual feed/management smoke run when a desktop target is available.
