# PiliPlus Flutter Frontend Guidelines

> Project-specific guidance for Flutter widgets, page structure, GetX controllers, and presentation state. This is not a web or React application: it has no Flutter hooks package and uses Flutter `State` plus GetX lifecycle conventions.

## Pre-Development Checklist

Before changing a page or widget:

- [ ] Locate the feature under `lib/pages/<feature>/`; check its `view.dart`, `controller.dart`, and local `widgets/` before adding a new abstraction.
- [ ] Trace the presentation flow: domain facade -> `Request`/`GrpcReq` -> `LoadingState<T>` -> controller Rx -> `Obx` view.
- [ ] Decide whether state belongs to a Flutter `StatefulWidget` or a tagged GetX controller; put initialization and cleanup in the matching lifecycle.
- [ ] Check `Loading`, `Success`, empty, `Error`, retry, refresh, and load-more branches for the affected screen.
- [ ] Reuse `lib/common/` widgets and theme/safe-area conventions; keep route names in `lib/router/app_pages.dart`.
- [ ] Keep typed fields and package imports; treat generated models/protobuf/Hive/JNI output as non-manual-edit boundaries.

## Guides

| Guide | Focus |
|---|---|
| [Directory Structure](./directory-structure.md) | Feature pages, shared widgets, routes, models, services, and platform boundaries |
| [Component Guidelines](./component-guidelines.md) | Typed composition, const widgets, theme, accessibility, and resource ownership |
| [Hook Guidelines](./hook-guidelines.md) | Flutter `State` and GetX lifecycle; explicitly no React or Flutter hooks |
| [State Management](./state-management.md) | `GetxController`, `Rx`/`.obs`, `Obx`, tags, loading, refresh, and pagination |
| [Type Safety](./type-safety.md) | Null safety, typed loading, hand-written models, Hive, protobuf, and generated boundaries |
| [Quality Guidelines](./quality-guidelines.md) | Flutter lints, lifecycle/resource checks, state transitions, and UI review |

## Quality checks

- [ ] The feature uses its existing page/controller/widget structure and does not duplicate shared components.
- [ ] Controllers expose typed reactive state, prevent duplicate requests, and are registered/tagged at the page boundary.
- [ ] Views use `Obx` for only the reactive subtree and render loading/content/empty/error states with a retry path.
- [ ] Stateful resources are disposed; GetX resources are released in `onClose`; no work starts from `build`.
- [ ] New widgets use const constructors/final typed fields where applicable, theme-derived styling, safe-area handling, and package imports.
- [ ] No React hooks, `flutter_hooks`, alternate state library, generated-file edits, or unrelated application rewrites were introduced.

Use `.trellis/spec/guides/` for cross-layer and reuse questions. All linked guidance is English and describes observed PiliPlus Flutter/GetX behavior.
