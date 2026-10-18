import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/services/logger.dart';
import 'package:PiliPlus/utils/hybrid_logical_clock.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

Map<String, dynamic>? _stringMap(Object? value) {
  if (value is! Map) return null;
  try {
    return Map<String, dynamic>.from(value);
  } catch (_) {
    return null;
  }
}

enum LocalHistorySyncOperation { upsert, delete, clear }

final class LocalHistorySyncEvent {
  const LocalHistorySyncEvent({
    required this.eventId,
    required this.nodeId,
    required this.hlc,
    required this.op,
    this.key,
    this.item,
  });

  final String eventId;
  final String nodeId;
  final HlcTimestamp hlc;
  final LocalHistorySyncOperation op;
  final String? key;
  final HistoryItemModel? item;

  Map<String, dynamic> toJson() => {
    'version': 2,
    'event_id': eventId,
    'node_id': nodeId,
    'hlc': hlc.toJson(),
    'op': op.name,
    if (key != null) 'key': key,
    if (item != null) 'item': item!.toJson(),
  };

  static LocalHistorySyncEvent? decode(Object? value) {
    try {
      final json = _stringMap(value);
      if (json == null || json['version'] is! int || json['version'] != 2) {
        return null;
      }
      final op = LocalHistorySyncOperation.values.byName(json['op'] as String);
      final id = json['event_id'] as String;
      final node = json['node_id'] as String;
      if (!LocalHistorySync._isUuid(id) || !LocalHistorySync._isUuid(node)) {
        return null;
      }
      final hlcRaw = _stringMap(json['hlc']);
      if (hlcRaw == null) return null;
      final hlc = HlcTimestamp.fromJson(hlcRaw);
      final key = json['key'];
      final rawItem = json['item'];
      switch (op) {
        case LocalHistorySyncOperation.upsert:
          final itemJson = _stringMap(rawItem);
          if (json.length != 7 || key is! String || itemJson == null) {
            return null;
          }
          final item = HistoryItemModel.fromJson(itemJson);
          if (!LocalHistorySync.isValid(item) ||
              !LocalHistorySync._isCanonicalKey(key) ||
              key != LocalHistorySync.keyOf(item)) {
            return null;
          }
          return LocalHistorySyncEvent(
            eventId: id,
            nodeId: node,
            hlc: hlc,
            op: op,
            key: key,
            item: item,
          );
        case LocalHistorySyncOperation.delete:
          if (json.length != 6 ||
              key is! String ||
              !LocalHistorySync._isCanonicalKey(key)) {
            return null;
          }
          return LocalHistorySyncEvent(
            eventId: id,
            nodeId: node,
            hlc: hlc,
            op: op,
            key: key,
          );
        case LocalHistorySyncOperation.clear:
          if (json.length != 5 || key != null || rawItem != null) return null;
          return LocalHistorySyncEvent(
            eventId: id,
            nodeId: node,
            hlc: hlc,
            op: op,
          );
      }
    } catch (_) {
      return null;
    }
  }
}

/// Shared-folder event log and deterministic CRDT projection owner.
abstract final class LocalHistorySync {
  static const String _outboxKey = LocalHistoryBoxKey.syncOutbox;
  static const String _metadataKey = LocalHistoryBoxKey.syncMetadata;
  static final StreamController<void> _changes =
      StreamController<void>.broadcast();
  static Stream<void> get changes => _changes.stream;
  static StreamSubscription<FileSystemEvent>? _watch;
  static Timer? _debounce;
  static Future<void> _queue = Future<void>.value();
  static Future<void> _configureQueue = Future<void>.value();
  static Future<void> Function()? _onExternalChange;
  static Future<void> _externalWork = Future<void>.value();
  static late String _nodeId;
  static String _writerId = const Uuid().v4();
  static late HybridLogicalClock _clock;
  static bool _initialized = false;
  static bool get supported =>
      !kIsWeb && (PlatformUtils.isDesktop || Platform.isAndroid);

  static String keyOf(HistoryItemModel item) =>
      '${item.history.business ?? 'archive'}|${item.history.oid}|${item.history.cid ?? ''}';

  static bool isValid(HistoryItemModel item) =>
      item.title?.isNotEmpty == true &&
      item.history.oid != null &&
      item.viewAt != null;

  static bool _isCanonicalKey(String key) {
    final parts = key.split('|');
    if (parts.length != 3 || parts[0].isEmpty || parts[0].contains('|')) {
      return false;
    }
    final oid = int.tryParse(parts[1]);
    final cid = parts[2].isNotEmpty ? int.tryParse(parts[2]) : null;
    return oid != null &&
        oid.toString() == parts[1] &&
        (parts[2].isEmpty || (cid != null && cid.toString() == parts[2]));
  }

  static bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);

  static Future<void> initialize(
    Future<void> Function() onExternalChange,
  ) async {
    if (!supported) return;
    _initialized = false;
    _onExternalChange = onExternalChange;
    final metadata =
        _stringMap(
          GStorage.localHistory.get(
            _metadataKey,
            defaultValue: <String, dynamic>{},
          ),
        ) ??
        <String, dynamic>{};
    final rawNodeId = metadata['node_id'];
    final nodeId = rawNodeId is String ? rawNodeId : null;
    _nodeId = nodeId != null && _isUuid(nodeId) ? nodeId : const Uuid().v4();
    final rawHlc = metadata['hlc'];
    HlcTimestamp? initial;
    if (rawHlc is Map) {
      try {
        final hlcJson = _stringMap(rawHlc);
        if (hlcJson != null) initial = HlcTimestamp.fromJson(hlcJson);
      } catch (_) {
        initial = null;
      }
    }
    _clock = HybridLogicalClock(initial);
    metadata['node_id'] = _nodeId;
    metadata['hlc'] = _clock.last.toJson();
    await GStorage.localHistory.put(_metadataKey, metadata);
    _initialized = true;
    try {
      await configure(Pref.localHistorySyncDirectory, persist: false);
    } catch (error, stackTrace) {
      logger.e(
        'Local history sync initialization failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<void> configure(String? root, {bool persist = true}) {
    if (!supported) return Future<void>.value();
    final result = _configureQueue.then(
      (_) => _configure(root, persist: persist),
    );
    _configureQueue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  static Future<void> _configure(String? root, {required bool persist}) async {
    final selected = root?.trim() ?? '';
    StreamSubscription<FileSystemEvent>? nextWatch;
    String? previousRoot;
    try {
      if (selected.isNotEmpty) {
        final directory = _eventsDirectory(selected);
        await directory.create(recursive: true);
        final probe = File(
          path.join(directory.path, '.access-${const Uuid().v4()}'),
        );
        await probe.writeAsString('', flush: true);
        await probe.delete();
        nextWatch = directory.watch().listen(
          (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 350), () {
              final callback = _onExternalChange;
              if (callback != null) {
                _externalWork = _externalWork.then(
                  (_) => _invokeExternal(callback),
                );
              }
            });
          },
          onError: (Object error, StackTrace stack) {
            logger.e(
              'Local history sync watcher failed',
              error: error,
              stackTrace: stack,
            );
          },
        );
      }
      if (persist) {
        await _serialized(() async {
          previousRoot = Pref.localHistorySyncDirectory;
          await GStorage.setting.put(
            SettingBoxKey.localHistorySyncDirectory,
            selected,
          );
          try {
            await _metadata((meta) => meta.remove('bootstrappedRoot'));
          } catch (_) {
            await GStorage.setting.put(
              SettingBoxKey.localHistorySyncDirectory,
              previousRoot,
            );
            rethrow;
          }
        });
      }
    } catch (_) {
      await nextWatch?.cancel();
      if (persist && previousRoot != null) {
        try {
          await GStorage.setting.put(
            SettingBoxKey.localHistorySyncDirectory,
            previousRoot,
          );
        } catch (error, stack) {
          logger.e(
            'Failed restoring local history sync setting',
            error: error,
            stackTrace: stack,
          );
        }
      }
      rethrow;
    }
    _debounce?.cancel();
    final previous = _watch;
    _watch = nextWatch;
    await previous?.cancel();
    if (selected.isNotEmpty) {
      final callback = _onExternalChange;
      if (callback != null) {
        await callback();
      } else {
        await sync();
      }
    }
  }

  static Future<void> _invokeExternal(Future<void> Function() callback) async {
    try {
      await callback();
    } catch (error, stack) {
      logger.e(
        'Local history sync watcher failed',
        error: error,
        stackTrace: stack,
      );
    }
  }

  static Directory _eventsDirectory(String root) => Directory(
    path.join(root, 'PiliPlus', 'local-history-sync'),
  );

  static Future<void> publishUpsert(HistoryItemModel item) {
    final key = keyOf(item);
    if (!isValid(item) || !_isCanonicalKey(key)) {
      return Future<void>.value();
    }
    return _publish(LocalHistorySyncOperation.upsert, key, item);
  }

  static Future<void> publishDelete(String key) {
    if (!_isCanonicalKey(key)) return Future<void>.value();
    return _publish(LocalHistorySyncOperation.delete, key, null);
  }

  static Future<void> publishClear() => _publish(
    LocalHistorySyncOperation.clear,
    null,
    null,
  );

  static Future<void> _publish(
    LocalHistorySyncOperation op,
    String? key,
    HistoryItemModel? item,
  ) => _serialized(() async {
    if (!supported || !_initialized) {
      return;
    }
    final root = Pref.localHistorySyncDirectory;
    if (root.isEmpty) {
      return;
    }
    final ts = _clock.tick(DateTime.now().millisecondsSinceEpoch);
    await _saveClock();
    final event = LocalHistorySyncEvent(
      eventId: const Uuid().v4(),
      nodeId: _nodeId,
      hlc: ts,
      op: op,
      key: key,
      item: item,
    );
    final outbox = _readOutbox()..add(event.toJson());
    await GStorage.localHistory.put(_outboxKey, outbox);
    await _drain(root);
  });

  static Future<void> sync() => _serialized(() async {
    if (!supported || !_initialized) return;
    final root = Pref.localHistorySyncDirectory;
    await _drain(root);
    final events = await _readEvents(root);
    if (events.isNotEmpty) {
      final maxTimestamp = events
          .map((e) => e.hlc)
          .reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
      _clock.observe(maxTimestamp, DateTime.now().millisecondsSinceEpoch);
      await _saveClock();
    }
    final metadata = _metadataMap();
    final dir = root.isEmpty ? null : _eventsDirectory(root);
    if (dir != null && metadata['bootstrappedRoot'] != path.normalize(root)) {
      final known = events
          .where((e) => e.key != null)
          .map((e) => e.key)
          .toSet();
      final cache = GStorage.localHistory.get(LocalHistoryBoxKey.cacheList);
      if (cache is List) {
        for (final raw in cache) {
          if (raw is! Map) continue;
          HistoryItemModel? item;
          try {
            item = HistoryItemModel.fromJson(Map<String, dynamic>.from(raw));
          } catch (_) {
            continue;
          }
          final key = keyOf(item);
          if (isValid(item) && _isCanonicalKey(key) && !known.contains(key)) {
            await _enqueue(
              LocalHistorySyncOperation.upsert,
              key,
              item,
              root: root,
            );
          }
        }
      }
      await _metadata(
        (meta) => meta['bootstrappedRoot'] = path.normalize(root),
      );
    }
    final allEvents = await _readEvents(root);
    if (allEvents.isEmpty) return;
    final maxTimestamp = allEvents
        .map((e) => e.hlc)
        .reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
    _clock.observe(maxTimestamp, DateTime.now().millisecondsSinceEpoch);
    await _saveClock();
    final byId = <String, LocalHistorySyncEvent>{};
    final conflicted = <String>{};
    for (final event in allEvents) {
      final prior = byId[event.eventId];
      if (prior == null) {
        byId[event.eventId] = event;
      } else if (jsonEncode(prior.toJson()) != jsonEncode(event.toJson())) {
        conflicted.add(event.eventId);
      }
    }
    for (final id in conflicted) {
      byId.remove(id);
    }
    final latest = <String, LocalHistorySyncEvent>{};
    LocalHistorySyncEvent? clear;
    for (final event in byId.values) {
      if (event.op == LocalHistorySyncOperation.clear) {
        if (clear == null || _compare(event, clear) > 0) {
          clear = event;
        }
      } else {
        final prior = latest[event.key];
        if (prior == null || _compare(event, prior) > 0) {
          latest[event.key!] = event;
        }
      }
    }
    final visible = <HistoryItemModel>[];
    for (final event in latest.values) {
      if (event.op == LocalHistorySyncOperation.upsert &&
          (clear == null || _compare(event, clear) > 0)) {
        visible.add(event.item!);
      }
    }
    visible.sort((a, b) {
      final date = (b.viewAt ?? 0).compareTo(a.viewAt ?? 0);
      return date != 0 ? date : keyOf(a).compareTo(keyOf(b));
    });
    await GStorage.localHistory.put(
      LocalHistoryBoxKey.cacheList,
      visible.map((item) {
        item.kid ??= keyOf(item).hashCode;
        return item.toJson();
      }).toList(),
    );
    _changes.add(null);
  });

  static int _compare(LocalHistorySyncEvent a, LocalHistorySyncEvent b) {
    final time = a.hlc.compareTo(b.hlc);
    if (time != 0) return time;
    final node = a.nodeId.compareTo(b.nodeId);
    return node != 0 ? node : a.eventId.compareTo(b.eventId);
  }

  static Future<void> _enqueue(
    LocalHistorySyncOperation op,
    String? key,
    HistoryItemModel? item, {
    required String root,
  }) async {
    final timestamp = _clock.tick(DateTime.now().millisecondsSinceEpoch);
    await _saveClock();
    final event = LocalHistorySyncEvent(
      eventId: const Uuid().v4(),
      nodeId: _nodeId,
      hlc: timestamp,
      op: op,
      key: key,
      item: item,
    );
    await GStorage.localHistory.put(
      _outboxKey,
      _readOutbox()..add(event.toJson()),
    );
    await _drain(root);
  }

  static Future<void> _drain(String root) async {
    if (!supported || root.isEmpty) return;
    final directory = _eventsDirectory(root);
    await directory.create(recursive: true);
    final outbox = _readOutbox();
    for (final raw in List<dynamic>.of(outbox)) {
      final event = LocalHistorySyncEvent.decode(raw);
      if (event == null) {
        outbox.remove(raw);
        await GStorage.localHistory.put(_outboxKey, outbox);
        continue;
      }
      final writer = File(path.join(directory.path, 'events-$_writerId.jsonl'));
      var opened = false;
      try {
        final handle = await writer.open(mode: FileMode.append);
        opened = true;
        try {
          await handle.writeString('${jsonEncode(event.toJson())}\n');
          await handle.flush();
        } finally {
          await handle.close();
        }
      } catch (_) {
        if (opened) {
          _writerId = const Uuid().v4();
        }
        rethrow;
      }
      outbox.remove(raw);
      await GStorage.localHistory.put(_outboxKey, outbox);
    }
  }

  static Future<List<LocalHistorySyncEvent>> _readEvents(String root) async {
    if (!supported || root.isEmpty) return [];
    final directory = _eventsDirectory(root);
    if (!directory.existsSync()) return [];
    final result = <LocalHistorySyncEvent>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File ||
          !path.basename(entity.path).startsWith('events-') ||
          !entity.path.endsWith('.jsonl')) {
        continue;
      }
      try {
        final bytes = await entity.readAsBytes();
        var lineStart = 0;
        for (var index = 0; index < bytes.length; index++) {
          if (bytes[index] != 0x0a) continue;
          final lineBytes = bytes.sublist(lineStart, index);
          lineStart = index + 1;
          if (lineBytes.isEmpty) continue;
          try {
            final event = LocalHistorySyncEvent.decode(
              jsonDecode(utf8.decode(lineBytes)),
            );
            if (event == null) {
              logger.w(
                'Skipping malformed local history event in ${entity.path}',
              );
            } else {
              result.add(event);
            }
          } catch (error, stack) {
            logger.w(
              'Skipping malformed local history event in ${entity.path}',
              error: error,
              stackTrace: stack,
            );
          }
        }
      } catch (error, stack) {
        logger.e(
          'Failed reading local history events',
          error: error,
          stackTrace: stack,
        );
        rethrow;
      }
    }
    return result;
  }

  static List<dynamic> _readOutbox() {
    final raw = GStorage.localHistory.get(
      _outboxKey,
      defaultValue: <dynamic>[],
    );
    return raw is List ? List<dynamic>.from(raw) : <dynamic>[];
  }

  static Future<void> _saveClock() =>
      _metadata((meta) => meta['hlc'] = _clock.last.toJson());

  static Map<String, dynamic> _metadataMap() =>
      _stringMap(GStorage.localHistory.get(_metadataKey)) ??
      <String, dynamic>{};

  static Future<void> _metadata(
    void Function(Map<String, dynamic>) update,
  ) async {
    final metadata = _metadataMap();
    update(metadata);
    await GStorage.localHistory.put(_metadataKey, metadata);
  }

  static Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  static Future<void> close() async {
    await _configureQueue;
    _debounce?.cancel();
    await _watch?.cancel();
    _watch = null;
    await _externalWork;
    await _queue;
    _initialized = false;
    _onExternalChange = null;
  }
}
