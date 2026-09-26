# Combined feed for local subscriptions

## Goal

Give users one chronological feed for the creators they saved as local subscriptions, without requiring those creators to be account-followed.

## Background and confirmed facts

- Local subscriptions persist creator identity metadata (`mid`, name, avatar, signature) in `LocalSubscriptions` and are managed from `/localSubscription`.
- The current local-subscription page only lists creators, opens each creator's member page, and supports removing or clearing entries.
- Each creator already has a paginated dynamic timeline through `MemberHttp.memberDynamic(mid, offset)`, returning `DynamicsDataModel` items rendered by the shared `DynamicPanel`.
- The account subscription page is a separate authenticated grid of subscribed collections; it is not the local-subscription feed.

## Requirements

- Aggregate each saved local creator's dynamic timeline into one feed.
- Order merged items newest first by the dynamic author's publication timestamp; use deterministic source order and source response order for ties.
- Preserve pagination, pull-to-refresh, loading, empty, error, retry, and load-more behavior using the repository's existing Flutter/GetX patterns.
- Keep local-subscription management available; viewing or refreshing the feed must not alter the saved list.
- Reuse the existing dynamic item rendering and navigation behavior rather than introducing a parallel card format.
- Work without requiring the current account to follow the locally saved creators.
- If some creators cannot be loaded, keep successful content visible and expose the failure with a retry path; show the full error state only when no source can provide content.

## Acceptance Criteria

- [ ] Existing local-subscription entry points open the combined dynamic feed and show content from more than one saved creator when each has available content.
- [ ] Every visible dynamic identifies its creator through the existing author panel, and merged items follow the defined newest-first ordering.
- [ ] Load-more fetches older pages from the saved creators without duplicate dynamic IDs or repeated source pages.
- [ ] Pull-to-refresh reloads the current local-subscription set; adding or removing a creator in management is reflected after returning to the feed.
- [ ] Empty local list and no available content have distinct usable states, including access to local-subscription management.
- [ ] Loading, partial-source failure with retry, all-source failure with retry, and successful pagination are observable and usable.
- [ ] Existing account subscription behavior, local-subscription persistence, and management operations remain unchanged.

## Out of scope

- Changing the persistence format or sync semantics of local subscriptions.
- Replacing the authenticated account subscription/folder page.
- Aggregating latest videos instead of dynamic timelines.
- Adding creator-following, notification, background refresh, or offline-cache semantics.

## Product decisions

- The feed aggregates dynamic timelines, not latest-video lists.
- The existing local-subscription destinations become entry points to the combined feed; the current `/localSubscription` page remains the management surface and is reachable from the feed.

