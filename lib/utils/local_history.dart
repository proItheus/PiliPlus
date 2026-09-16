import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/utils/storage.dart';

/// 本地观看历史：记录播放过的视频（不依赖登录/服务器），支持导出/导入。
///
/// 存储格式为 `HistoryItemModel` 的 JSON 序列化列表（纯文本可读），
/// 以 `business|oid|cid` 作为去重键。
abstract final class LocalHistory {
  static const String _cacheKey = 'cacheList';

  /// 串行化读改写操作，避免并发播放事件交替读写丢失记录
  static Future<void> _queue = Future.value();

  static Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

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
          ..sort((a, b) => (b.viewAt ?? 0).compareTo(a.viewAt ?? 0));
    return list;
  }

  static HistoryItemModel _fromRaw(Map<dynamic, dynamic> json) {
    final item = HistoryItemModel.fromJson(
      Map<String, dynamic>.from(json),
    );
    // 列表项依赖 videos 展示，缺失时按单 P 处理
    item.videos ??= 1;
    return item;
  }

  static bool _isValid(HistoryItemModel item) =>
      item.title?.isNotEmpty == true &&
      item.history.oid != null &&
      item.viewAt != null;

  static String keyOf(HistoryItemModel item) =>
      '${item.history.business ?? 'archive'}|'
      '${item.history.oid}|${item.history.cid ?? ''}';

  /// 记录一条观看记录：按去重键更新，已存在则刷新并置顶。
  static Future<void> record(HistoryItemModel item) => _serialized(() async {
    if (!_isValid(item)) return;
    final key = keyOf(item);
    final list = load();
    list.removeWhere((e) => keyOf(e) == key);
    list.add(item);
    list.sort((a, b) => (b.viewAt ?? 0).compareTo(a.viewAt ?? 0));
    await _save(list);
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
    if (valid.isEmpty) {
      if (!merge) {
        // 替换模式下文件无有效记录则清空（内联执行，避免嵌套串行化死锁）
        await GStorage.localHistory.delete(_cacheKey);
      }
      return 0;
    }
    final List<HistoryItemModel> list;
    if (merge) {
      list = load();
      for (final item in valid) {
        final key = keyOf(item);
        final index = list.indexWhere((e) => keyOf(e) == key);
        if (index == -1) {
          list.add(item);
        } else if ((item.viewAt ?? 0) >= (list[index].viewAt ?? 0)) {
          // 同时间戳以导入数据为准
          list[index] = item;
        }
      }
    } else {
      list = valid;
    }
    list.sort((a, b) => (b.viewAt ?? 0).compareTo(a.viewAt ?? 0));
    await _save(list);
    return valid.length;
  });

  /// 删除单条记录。
  static Future<void> remove(HistoryItemModel item) => _serialized(() async {
    final key = keyOf(item);
    final list = load();
    list.removeWhere((e) => keyOf(e) == key);
    await _save(list);
  });

  static Future<void> clear() => _serialized(
    () => GStorage.localHistory.delete(_cacheKey),
  );

  static Future<void> _save(List<HistoryItemModel> list) =>
      GStorage.localHistory.put(
        _cacheKey,
        list.map((e) {
          // HistoryItem 的删除菜单依赖 kid 非空
          e.kid ??= keyOf(e).hashCode;
          return e.toJson();
        }).toList(),
      );
}
