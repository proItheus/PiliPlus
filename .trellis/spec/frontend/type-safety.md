# Dart and Model Type Safety

Use Dart null safety and explicit domain types at layer boundaries. The repository has both hand-written models under `lib/models/` and `lib/models_new/`, Hive-annotated classes, and generated protobuf/Hive/JNI output; document and preserve those existing boundaries rather than forcing an unobserved migration.

## Typed loading and controllers

Keep facade and controller signatures typed: `CommonListController<ArticleListData, ArticleListItemModel>` and `Future<LoadingState<ArticleListData>> customGetData()` in `lib/pages/article_list/controller.dart` make the expected response explicit. Pattern matching `Success(:final response)` and `Error(:final errMsg)` narrows the state before use. Avoid `LoadingState.data` until success is established.

## JSON and nullability

Hand-written models parse external maps deliberately. `UserInfoData.fromJson` in `lib/models/user/info.dart` maps API keys and normalizes integer money to `double`; `Owner.fromJson` in `lib/models/model_owner.dart` uses `safeToInt`; `LocalSubscription.fromJson` validates a positive numeric/string-convertible ID and throws `FormatException` for malformed data. Preserve nullable fields when the API may omit them and make required invariants explicit at the model boundary.

Use `toJson` as the matching persistence/import boundary. `LocalSubscription.toJson` omits null optional values; do not assume every remote map has the shape of a Hive record.

## Generated types

Classes marked with `@HiveType`/`@HiveField` (for example `UserInfoData`) have generated adapters in `.g.dart`; protobuf message classes and parsers are generated under `lib/grpc/bilibili/`; JNI bindings are generated under platform utility directories. Consume those types but do not hand-edit their output. When a schema/type changes, update the owning annotated/schema source and use the generator workflow.

## Avoid and common mistakes

- Do not cast raw maps to a model without validating required fields or preserving parse errors.
- Do not turn nullable API data into `!` merely to satisfy a widget; render an explicit empty/error state or establish the invariant first.
- Do not use `dynamic` for a controller's public state when `LoadingState<T>`, a model, or a collection type is available.
- Do not manually edit generated `.g.dart`, protobuf `.pb.dart`, or JNI binding files, and do not assign new persisted Hive field IDs casually.
- Do not claim all models use one generation style; current code intentionally contains both `lib/models/` and `lib/models_new/`.
