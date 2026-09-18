import 'package:PiliPlus/models_new/local_subscription.dart';
import 'package:PiliPlus/utils/storage.dart';

/// 本地订阅：保存常用 UP 主，访问其主页不依赖登录或服务器关注关系。
abstract final class LocalSubscriptions {
  static const String _cacheKey = 'items';
  static Future<void> _queue = Future.value();

  static Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  static List<LocalSubscription> load() {
    final raw = GStorage.localSubscriptions.get(_cacheKey);
    if (raw is! List) return <LocalSubscription>[];

    final result = <LocalSubscription>[];
    for (final value in raw) {
      if (value is! Map) continue;
      try {
        result.add(
          LocalSubscription.fromJson(Map<String, dynamic>.from(value)),
        );
      } on FormatException {
        // Ignore malformed entries left by an interrupted or old import.
      } on TypeError {
        // Ignore malformed entries left by an interrupted or old import.
      }
    }
    return result;
  }

  static bool contains(int mid) => load().any((item) => item.mid == mid);

  /// Toggle a channel and return its new subscribed state.
  static Future<bool> toggle({
    required int mid,
    String? name,
    String? face,
    String? sign,
  }) => _serialized(() async {
    final list = load();
    final index = list.indexWhere((item) => item.mid == mid);
    if (index >= 0) {
      list.removeAt(index);
      await _save(list);
      return false;
    }

    list.insert(
      0,
      LocalSubscription(mid: mid, name: name, face: face, sign: sign),
    );
    await _save(list);
    return true;
  });

  static Future<void> remove(int mid) => _serialized(() async {
    final list = load()..removeWhere((item) => item.mid == mid);
    await _save(list);
  });

  static Future<void> clear() =>
      _serialized(() => GStorage.localSubscriptions.delete(_cacheKey));

  static Future<void> _save(List<LocalSubscription> list) => GStorage
      .localSubscriptions
      .put(_cacheKey, list.map((item) => item.toJson()).toList());
}
