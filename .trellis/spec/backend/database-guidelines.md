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

## Local playback history queue contract

### 1. Scope / Trigger

This contract applies when player callbacks persist local non-file playback history through `LocalHistory` in `lib/utils/local_history.dart`. It prevents concurrent playlist callbacks from losing records and prevents a history reader from observing a queue prefix.

### 2. Signatures

- `LocalHistory.record(HistoryItemModel item) -> Future<void>` serializes one complete read-modify-write.
- `LocalHistory.flush() -> Future<void>` completes after the writes currently in the queue.
- `LocalHistory.load() -> List<HistoryItemModel>` reads the persisted `cacheList`; callers that need the latest queued state must await `flush()` first.

### 3. Contracts

- The persisted value is a JSON list in `GStorage.localHistory['cacheList']`.
- Deduplication is `business|oid|cid`; updating one key must retain every other key.
- `HistoryItemModel.progress` is seconds; `-1` means completed and must reopen at zero through `playbackProgress`.
- `record`, `import`, `remove`, and `clear` share the serialized queue. A queue failure must not prevent later operations from running; a caller that awaits a record must contain/report its error without breaking playback.

### 4. Validation & Error Matrix

| Condition | Required behavior |
| --- | --- |
| Invalid title, oid, or view timestamp | Skip the item; do not write an invalid record. |
| Concurrent record/import/remove/clear | Execute complete operations in invocation order; never read and write concurrently. |
| Reader starts while writes are queued | Await `LocalHistory.flush()` before the first `load()`. |
| Hive write failure | Keep the queue usable for later operations; the playback caller logs the failure and continues player/UI work. |

### 5. Good/Base/Bad Cases

- **Good:** A position listener checkpoints a non-file item at a bounded interval, then awaits a forced snapshot on pause/completion/route disposal; the history controller awaits `flush()` before loading.
- **Base:** A single `record` updates one key and `load()` returns the sorted list after `record` completes.
- **Bad:** Each callback calls `load()` and `put()` independently, or a controller reads immediately after scheduling records without a queue barrier; later playlist items disappear or the list shows a partial prefix.

### 6. Tests Required

- Isolate Hive in a temporary directory and assert that ten unawaited `record` calls followed only by `await LocalHistory.flush()` produce ten persisted keys.
- When a player lifecycle test is available in CI, assert distinct playlist keys, a non-zero pause/seek position, `-1` completion, stale-position suppression after a boundary, and unchanged file-source behavior.

### 7. Wrong vs Correct

**Wrong:**

```dart
LocalHistory.record(item);
final visible = LocalHistory.load();
```

**Correct:**

```dart
await LocalHistory.record(item);
final visible = LocalHistory.load();
// Or, at a read boundary that follows several producers:
await LocalHistory.flush();
final visible = LocalHistory.load();
```

## Avoid and common mistakes

- Do not add SQL tables, ORM entities, migrations, server repositories, or claims about remote transactions; none exist in this client.
- Do not call `Hive.openBox` from a page or controller when a named `GStorage` box/accessor already exists.
- Do not invent string keys beside `storage_key.dart`, store a setting under a different box, or silently change an existing key: persisted data depends on these names.
- Do not perform unsynchronized read-modify-write operations like `load(); await put(...)` when multiple calls can overlap; use the `LocalSubscriptions` queue pattern or an equivalent existing ownership boundary.
- Do not manually edit `.g.dart` adapters or alter Hive type IDs/field numbers casually; generated adapters and persisted field IDs are compatibility boundaries.
