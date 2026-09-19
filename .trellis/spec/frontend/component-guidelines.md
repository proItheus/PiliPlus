# Flutter Component Guidelines

Build UI from small typed widgets and existing shared components. Use `StatelessWidget` when rendering depends only on constructor inputs and `StatefulWidget` when the widget owns mutable framework resources. Prefer composition over large feature widgets.

## Constructors and fields

Use `const` constructors where possible, `final` typed fields, named parameters, and callbacks for child-to-parent events. `HttpError` in `lib/common/widgets/loading_widget/http_error.dart` is a representative shared component: it has a const constructor, typed optional fields (`String? errMsg`, `VoidCallback? onReload`), derives colors from `Theme.of(context)`, and composes existing `SelectionText` and button widgets.

`ArticleListPage` composes `CustomScrollView`, `SliverAppBar`, `SliverGrid.builder`, `ArticleListItem`, and `HttpError` rather than placing item rendering and loading fallback logic in one generic child. Feature-local widgets belong in `lib/pages/article_list/widgets/` when they are not shared.

## Theme and accessibility

Read colors and text styles from `Theme.of(context)` or `theme.colorScheme`, as `ArticleListPage._buildHeader` does, instead of hard-coding a light/dark color. Keep interactive controls discoverable through semantic labels and meaningful button text; preserve selection/error text behavior supplied by shared widgets. Respect safe-area and platform padding (`MediaQuery.viewPaddingOf(context)`) where a page already does so.

For asynchronous content, render explicit loading, success/empty, and error branches. The article list's `_buildBody` uses a skeleton for `Loading`, a grid for non-empty `Success`, and `HttpError(onReload: ...)` for empty/error cases. Keep callbacks typed and route retry actions to the controller.

## Stateful ownership

A `StatefulWidget` owns only resources tied to its mounted state. Create controllers/listeners/timers in the state lifecycle where needed and dispose them in `dispose()`. A GetX controller owns longer-lived page state and disposes its resources in `GetxController.onClose`; `CommonController` demonstrates this for `ScrollController`.

## Avoid and common mistakes

- Do not use untyped `dynamic` widget fields or positional booleans when a named typed field communicates intent.
- Do not call network/storage facades from `build`; use the controller lifecycle and reactive state.
- Do not hard-code theme colors, assume a fixed safe-area inset, or remove reload/error affordances from a loading branch.
- Do not create a second copy of `HttpError`, refresh behavior, or shared loading widgets for a feature without a concrete presentation difference.
- Do not forget to dispose a controller, listener, timer, or subscription owned by a `State` object.
