# Implementation plan

## Ordered checklist

1. Add an injectable dynamic-page fetcher and feature-private source cursor/merge state. Read the saved local creators on refresh, deduplicate creator IDs, fetch source pages concurrently, and emit bounded merged chunks through `CommonListController`.
2. Implement stable ordering by `pubTs`, saved-source order, and source-page order; suppress repeated non-null dynamic IDs; advance each source offset exactly once per successful page; stop when all sources are exhausted or unavailable.
3. Expose partial-source failures separately from the normal `LoadingState`. Preserve successful items, render a retryable warning, and return the normal error branch only when no source produced content.
4. Add `LocalSubscriptionFeedController` lifecycle wiring and `LocalSubscriptionFeedPage` loading, local-empty, no-content, partial-warning, all-error, refresh, pagination, and management-navigation branches. Reuse `dynSkeleton`, `DynamicPanel`, `HttpError`, `refreshIndicator`, safe-area padding, and the existing waterfall preference.
5. Register `/localSubscriptionFeed`; update the account subscription and Mine local-subscription entry points to target it. Keep `/localSubscription` as the unchanged management route and refresh the feed after returning from it.
6. Add focused controller/aggregation tests with fake source pages covering interleaving order, timestamp ties, duplicate IDs, source-page cursor advancement, exhausted sources, partial failures, and all-source failure.
7. Run the targeted test and standard project checks. Exercise the actual feed and management navigation manually when a supported Flutter desktop target is available.

## Validation commands

Run from the repository's Nix/direnv environment through Just/FVM:

```sh
just format-check
just test test/pages/local_subscription_feed/controller_test.dart
just analyze
```

For the surface smoke check, use the documented run recipe with an available target, for example:

```sh
just run -d macos
```

Exercise: empty local list -> management action; two saved creators -> interleaved dynamic items; scroll to load more; pull to refresh; remove a creator in management and return; trigger retry/error branches with the test seam or an unavailable source. Do not rely on the smoke run as a substitute for the focused merge tests.

## Risk and rollback points

- **Aggregation algorithm:** keep cursor/merge logic isolated in the feature controller or a feature-local helper; if ordering regresses, revert that unit without touching storage or route wiring.
- **Partial failures:** keep failure presentation additive; successful feed rendering must remain usable if the warning branch is removed during rollback.
- **Navigation:** add the new route before changing callers; reverting caller changes restores the existing management destination while leaving persistence intact.
- **API compatibility:** do not edit `MemberHttp`, generated models, or storage serialization unless implementation evidence proves the existing contract insufficient.

## Review gates before activation

- `prd.md` has no unresolved product decisions and acceptance criteria map to observable behavior.
- `design.md` and this checklist match the planned route, controller, cursor, and failure contracts.
- `implement.jsonl` and `check.jsonl` contain curated frontend specs and relevant research entries.
- `task.py validate` passes before `task.py start`.
