# Local Persistence Guidelines

This repository has no server-side database, SQL schema, ORM, migration system, or remote persistence service. The database-shaped part of the Trellis scaffold means local Hive CE persistence used by this Flutter client. Do not introduce a relational or server architecture while implementing a feature.

## Hive lifecycle and boxes

`GStorage.init()` in `lib/utils/storage.dart:29-94` initializes Hive below the application-support path, calls `regAdapter()`, and opens named boxes such as `userInfo`, `setting`, `localCache`, `localSubscriptions`, `video`, and `watchProgress`. `GStorage.regAdapter()` registers `OwnerAdapter`, `UserInfoDataAdapter`, account adapters, `SetIntAdapter`, and `RuleFilterAdapter` before typed values are read. The application calls `await GStorage.init()` during startup in `lib/main.dart:92-102`; consumers should not race that initialization.

Use the existing box fields and typed accessors:

```dart
final user = GStorage.userInfo.get('userInfoCache');
final darkMode = Pref.themeMode; // Pref reads GStorage.setting via storage_pref.dart
await GStorage.localSubscriptions.put('items', serializedItems);
```

`Pref` in `lib/utils/storage_pref.dart` is the settings API. Pair every new setting with an owned constant in `SettingBoxKey`, `LocalCacheKey`, or `VideoBoxKey` in `lib/utils/storage_key.dart`, and provide a typed default where the current code does. `Pref.blackMids` and `Pref.setBlackMid` show the read/write pattern for a local cache value.

## Serialization and writes

Hand-written models own JSON conversion at API/import boundaries. `LocalSubscription.fromJson` in `lib/models_new/local_subscription.dart` rejects a missing or non-positive `mid`, while `toJson` emits only non-null optional fields. Persist the serialized map/list in the existing box rather than storing arbitrary model objects in an unregistered box.

When a value can be updated concurrently, serialize the complete read-modify-write operation. `LocalSubscriptions._serialized` in `lib/utils/local_subscriptions.dart` chains a private future queue; `toggle`, `remove`, and `clear` all use it, and `_save` writes the resulting list to the `localSubscriptions` box. This prevents a late toggle from overwriting an earlier operation.

For account persistence, follow the existing account lifecycle and deletion tombstone behavior covered by `test/utils/accounts/deleted_account_test.dart`; do not re-create deleted data from a late asynchronous callback.

## Export, cleanup, and tests

`GStorage.exportAllSettings` and `importAllJsonSettings` in `lib/utils/storage.dart` define the current setting backup boundary (`setting` and `video`). `GStorage.close`, `clear`, and `compact` operate on the known boxes. Tests that use Hive should isolate state: the committed account tests create a temporary directory, call `Hive.init`, register adapters, open a typed box, clear it between tests, close Hive, and delete the temporary directory in `tearDownAll`.

## Avoid and common mistakes

- Do not add SQL tables, ORM entities, migrations, server repositories, or claims about remote transactions; none exist in this client.
- Do not call `Hive.openBox` from a page or controller when a named `GStorage` box/accessor already exists.
- Do not invent string keys beside `storage_key.dart`, store a setting under a different box, or silently change an existing key: persisted data depends on these names.
- Do not perform unsynchronized read-modify-write operations like `load(); await put(...)` when multiple calls can overlap; use the `LocalSubscriptions` queue pattern or an equivalent existing ownership boundary.
- Do not manually edit `.g.dart` adapters or alter Hive type IDs/field numbers casually; generated adapters and persisted field IDs are compatibility boundaries.
