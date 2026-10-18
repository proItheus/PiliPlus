import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/services/logger.dart';
import 'package:PiliPlus/utils/local_history_sync.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';

/// 本地观看历史：记录播放过的视频（不依赖登录/服务器），支持导出/导入。
///
/// 存储格式为 `HistoryItemModel` 的 JSON 序列化列表（纯文本可读），
/// 以 `business|oid|cid` 作为去重键。
abstract final class LocalHistory {
  static const String _cacheKey = LocalHistoryBoxKey.cacheList;

  /// 串行化读改写操作，避免并发播放事件交替读写丢失记录
  static Future<void> _queue = Future.value();

  static Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Completes when all currently queued local-history writes have finished.
  static Future<void> flush() => _queue;

  /// 读取本地历史，按观看时间倒序。
  static List<HistoryItemModel> load() {
    final raw = GStorage.localHistory.get(_cacheKey);
    if (raw is! List) return <HistoryItemModel>[];
    final list =
        raw
            .whereType<Map<dynamic, dynamic>>()
            .map(_fromRaw)
            .where(_isValid)
            .toList()
          ..sort((a, b) {
            final date = (b.viewAt ?? 0).compareTo(a.viewAt ?? 0);
            return date != 0 ? date : keyOf(a).compareTo(keyOf(b));
          });
    return list;
  }

  static HistoryItemModel _fromRaw(Map<dynamic, dynamic> json) {
    final item = HistoryItemModel.fromJson(
      Map<String, dynamic>.from(json),
    );
    // 列表项依赖 videos 展示，缺失时按单 P 处理
    return item..videos ??= 1;
  }

  static bool _isValid(HistoryItemModel item) => LocalHistorySync.isValid(item);

  static String keyOf(HistoryItemModel item) => LocalHistorySync.keyOf(item);

  /// Records playback locally and publishes it to the sync outbox.
  static Future<void> record(HistoryItemModel item) => _serialized(() async {
    if (!_isValid(item)) return;
    final key = keyOf(item);
    final list = load()
      ..removeWhere((e) => keyOf(e) == key)
      ..add(item)
      ..sort((a, b) => (b.viewAt ?? 0).compareTo(a.viewAt ?? 0));
    await _save(list);
    await _publish(() => LocalHistorySync.publishUpsert(item));
  });

  /// 导入记录。
  ///
  /// [merge] 为 true（默认）时与现有记录合并，重复项保留较新的记录；
  /// 为 false 时清空现有记录后整体替换。
  /// 返回成功导入（含合并更新）的条数。
  static Future<int> import(
    List<HistoryItemModel> items, {
    required bool merge,
  }) => _serialized(() async {
    final valid = items.where(_isValid).toList();
    if (valid.isEmpty && !merge) {
      await GStorage.localHistory.delete(_cacheKey);
      await _publish(LocalHistorySync.publishClear);
      return 0;
    }
    final List<HistoryItemModel> list;
    final changed = <HistoryItemModel>[];
    if (merge) {
      list = load();
      for (final item in valid) {
        final key = keyOf(item);
        final index = list.indexWhere((e) => keyOf(e) == key);
        if (index == -1) {
          list.add(item);
          changed.add(item);
        } else if ((item.viewAt ?? 0) >= (list[index].viewAt ?? 0)) {
          list[index] = item;
          changed.add(item);
        }
      }
    } else {
      list = valid;
      changed.addAll(valid);
    }
    list.sort((a, b) => (b.viewAt ?? 0).compareTo(a.viewAt ?? 0));
    await _save(list);
    if (!merge) await _publish(LocalHistorySync.publishClear);
    for (final item in changed) {
      await _publish(() => LocalHistorySync.publishUpsert(item));
    }
    return valid.length;
  });

  /// 删除单条记录。
  static Future<void> remove(HistoryItemModel item) => _serialized(() async {
    final key = keyOf(item);
    final list = load()..removeWhere((e) => keyOf(e) == key);
    await _save(list);
    await _publish(() => LocalHistorySync.publishDelete(key));
  });

  static Future<void> clear() => _serialized(() async {
    await GStorage.localHistory.delete(_cacheKey);
    await _publish(LocalHistorySync.publishClear);
  });

  static Future<void> sync() => _serialized(() async {
    try {
      await LocalHistorySync.sync();
    } catch (error, stack) {
      logger.e(
        'Local history synchronization failed',
        error: error,
        stackTrace: stack,
      );
    }
  });

  static Future<void> _publish(Future<void> Function() publish) async {
    try {
      await publish();
    } catch (error, stack) {
      logger.e(
        'Local history publication failed',
        error: error,
        stackTrace: stack,
      );
    }
  }

  static Future<void> _save(List<HistoryItemModel> list) =>
      GStorage.localHistory.put(
        _cacheKey,
        list.map((e) {
          e.kid ??= keyOf(e).hashCode;
          return e.toJson();
        }).toList(),
      );
}
