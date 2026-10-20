import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models_new/history/history.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/episode.dart';
import 'package:PiliPlus/models_new/video/video_detail/page.dart';
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

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'version': 3,
      'event_id': eventId,
      'node_id': nodeId,
      'hlc': hlc.toJson(),
      'op': op.name,
      if (key != null) 'key': key,
    };
    if (op == LocalHistorySyncOperation.upsert) {
      json.addAll({
        'history': item!.history.toJson(),
        'view_at': item!.viewAt,
        'progress': item!.progress,
        'duration': item!.duration,
      });
    }
    return json;
  }

  static LocalHistorySyncEvent? decode(Object? value) {
    try {
      final json = _stringMap(value);
      if (json == null) return null;
      final version = json['version'];
      if (version is! int || (version != 2 && version != 3)) {
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
      final rawHistory = json['history'];
      switch (op) {
        case LocalHistorySyncOperation.upsert:
          if (version == 2) {
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
          }
          final historyJson = _stringMap(rawHistory);
          if (json.length != 10 || key is! String || historyJson == null) {
            return null;
          }
          final item = HistoryItemModel(
            history: History.fromJson(historyJson),
            viewAt: json['view_at'] as int?,
            progress: json['progress'] as int?,
            duration: json['duration'] as int?,
          );
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
          if (json.length != 5 ||
              key != null ||
              rawItem != null ||
              rawHistory != null) {
            return null;
          }
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
  static const int _publishIntervalMs = 10 * 60 * 1000;
  static const int _retryIntervalMs = 10 * 60 * 1000;
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
  static bool debugSuppressHydrate = false;
  static bool get supported =>
      !kIsWeb && (PlatformUtils.isDesktop || Platform.isAndroid);

  static String keyOf(HistoryItemModel item) =>
      '${item.history.business ?? 'archive'}|${item.history.oid}|${item.history.cid ?? ''}';

  static bool isValid(HistoryItemModel item) =>
      item.history.oid != null && item.viewAt != null;

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

  static Future<void> publishUpsert(
    HistoryItemModel item, {
    bool force = false,
  }) {
    final key = keyOf(item);
    if (!isValid(item) || !_isCanonicalKey(key)) {
      return Future<void>.value();
    }
    return _publish(LocalHistorySyncOperation.upsert, key, item, force: force);
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
    HistoryItemModel? item, {
    bool force = false,
  }) => _serialized(() async {
    if (!supported || !_initialized) {
      return;
    }
    final root = Pref.localHistorySyncDirectory;
    if (root.isEmpty) {
      return;
    }
    final last = _lastPublishMap();
    if (!force && op == LocalHistorySyncOperation.upsert) {
      final due = item?.progress == -1 || _isDue(key!, last);
      if (!due) return;
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
    if (op == LocalHistorySyncOperation.upsert) {
      last[key!] = DateTime.now().millisecondsSinceEpoch;
      await _saveLastPublish(last);
    }
  });

  static Map<String, int> _lastPublishMap() {
    final raw = _metadataMap()['lastPublish'];
    if (raw is! Map) return <String, int>{};
    final out = <String, int>{};
    raw.forEach((k, v) {
      if (k is String && v is int) out[k] = v;
    });
    return out;
  }

  static Future<void> _saveLastPublish(Map<String, int> last) =>
      _metadata((meta) => meta['lastPublish'] = last);

  static bool _isDue(String key, Map<String, int> last) {
    final t = last[key];
    if (t == null) return true;
    return DateTime.now().millisecondsSinceEpoch - t >= _publishIntervalMs;
  }

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
    final hydrateQueue = <HistoryItemModel>[];
    for (final event in latest.values) {
      if (event.op == LocalHistorySyncOperation.upsert &&
          (clear == null || _compare(event, clear) > 0)) {
        final item = event.item!;
        _fillFromCache(item);
        if (!_hasDisplayMeta(item)) hydrateQueue.add(item);
        visible.add(item);
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
    if (!debugSuppressHydrate && hydrateQueue.isNotEmpty) {
      unawaited(_hydrate(hydrateQueue));
    }
  });

  static Map<String, dynamic>? _metaGet(String key) {
    final all = _stringMap(
      GStorage.localHistory.get(
        LocalHistoryBoxKey.videoMeta,
        defaultValue: <String, dynamic>{},
      ),
    );
    return _stringMap(all?.containsKey(key) == true ? all![key] : null);
  }

  static Future<void> _metaPut(String key, Map<String, dynamic> meta) async {
    final all =
        _stringMap(
          GStorage.localHistory.get(
            LocalHistoryBoxKey.videoMeta,
            defaultValue: <String, dynamic>{},
          ),
        ) ??
        <String, dynamic>{};
    all[key] = meta;
    await GStorage.localHistory.put(LocalHistoryBoxKey.videoMeta, all);
  }

  static void _fillFromCache(HistoryItemModel item) {
    final meta = _metaGet(keyOf(item));
    if (meta == null) return;
    item.title ??= meta['title'] as String?;
    item.cover ??= meta['cover'] as String?;
    item.authorName ??= meta['author_name'] as String?;
    item.authorMid ??= meta['author_mid'] as int?;
    item.videos ??= meta['videos'] as int?;
    item.duration ??= meta['duration'] as int?;
  }

  static bool _hasDisplayMeta(HistoryItemModel item) =>
      item.title?.isNotEmpty == true;

  static Future<void> _hydrate(List<HistoryItemModel> items) async {
    const batchSize = 4;
    for (var start = 0; start < items.length; start += batchSize) {
      final end = start + batchSize < items.length
          ? start + batchSize
          : items.length;
      await Future.wait([
        for (var i = start; i < end; i++) _fetchMeta(items[i]),
      ]);
    }
  }

  static Future<void> _fetchMeta(HistoryItemModel item) async {
    final key = keyOf(item);
    final existing = _metaGet(key);
    if (existing?['title'] is String &&
        (existing!['title'] as String).isNotEmpty) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastAttempt = existing?['lastAttempt'] as int?;
    if (lastAttempt != null && now - lastAttempt < _retryIntervalMs) return;
    Map<String, dynamic>? enrichment;
    try {
      if ((item.history.business ?? 'archive') == 'archive' &&
          item.history.bvid != null) {
        final res = await VideoHttp.videoIntro(bvid: item.history.bvid!);
        if (res case Success(:final response)) {
          final page = _findPage(response.pages, item.history.cid);
          enrichment = <String, dynamic>{
            'title': response.title,
            'cover': response.pic,
            'author_name': response.owner?.name,
            'author_mid': response.owner?.mid,
            'videos': response.videos,
            'duration': page?.duration ?? response.duration,
          };
        }
      } else if (item.history.business != 'archive' &&
          item.history.epid != null) {
        final res = await SearchHttp.pgcInfo(epId: item.history.epid);
        if (res case Success(:final response)) {
          final ep = _findEpisode(response.episodes, item.history.cid);
          enrichment = <String, dynamic>{
            'title': ep?.title,
            'cover': ep?.cover,
            'duration': ep?.duration != null
                ? (ep!.duration! / 1000).round()
                : null,
          };
        }
      }
    } catch (_) {}
    enrichment ??= <String, dynamic>{};
    enrichment['lastAttempt'] = now;
    await _metaPut(key, enrichment);
    if (enrichment['title'] is String &&
        (enrichment['title'] as String).isNotEmpty) {
      item
        ..title = enrichment['title'] as String
        ..cover = enrichment['cover'] as String?
        ..authorName = enrichment['author_name'] as String?
        ..authorMid = enrichment['author_mid'] as int?
        ..videos = enrichment['videos'] as int?
        ..duration = enrichment['duration'] as int?;
      await _patchProjectionRow(item);
      _changes.add(null);
    }
  }

  static Part? _findPage(List<Part>? pages, int? cid) {
    if (pages == null || cid == null) return null;
    for (final p in pages) {
      if (p.cid == cid) return p;
    }
    return null;
  }

  static EpisodeItem? _findEpisode(List<EpisodeItem>? episodes, int? cid) {
    if (episodes == null) return null;
    if (cid != null) {
      for (final e in episodes) {
        if (e.cid == cid) return e;
      }
    }
    return episodes.isEmpty ? null : episodes.first;
  }

  static Future<void> _patchProjectionRow(HistoryItemModel item) async {
    final raw = GStorage.localHistory.get(LocalHistoryBoxKey.cacheList);
    if (raw is! List) return;
    final list = List<dynamic>.from(raw);
    final key = keyOf(item);
    for (var i = 0; i < list.length; i++) {
      final row = list[i];
      if (row is! Map) continue;
      try {
        final existing = HistoryItemModel.fromJson(
          Map<String, dynamic>.from(row),
        );
        if (keyOf(existing) != key) continue;
      } catch (_) {
        continue;
      }
      final merged = item.toJson();
      final kid = row['kid'];
      if (kid != null) merged['kid'] = kid;
      list[i] = merged;
      await GStorage.localHistory.put(LocalHistoryBoxKey.cacheList, list);
      return;
    }
  }

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
      try {
        await _appendToWriter(writer, event);
      } catch (_) {
        _writerId = const Uuid().v4();
        rethrow;
      }
      outbox.remove(raw);
      await GStorage.localHistory.put(_outboxKey, outbox);
    }
  }

  static Future<void> _appendToWriter(
    File writer,
    LocalHistorySyncEvent event,
  ) async {
    List<int>? prefix;
    if (writer.existsSync()) {
      final bytes = writer.readAsBytesSync();
      if (bytes.isNotEmpty && bytes.last == 0x0a) {
        final idx = bytes.lastIndexOf(0x0a, bytes.length - 2);
        final start = idx + 1;
        final end = bytes.length - 1;
        if (end > start) {
          try {
            final decoded = LocalHistorySyncEvent.decode(
              jsonDecode(utf8.decode(bytes.sublist(start, end))),
            );
            if (decoded != null &&
                decoded.op != LocalHistorySyncOperation.clear &&
                event.op != LocalHistorySyncOperation.clear &&
                decoded.key != null &&
                decoded.key == event.key) {
              prefix = bytes.sublist(0, start);
            }
          } catch (_) {}
        }
      }
    }
    final line = '${jsonEncode(event.toJson())}\n';
    if (prefix == null) {
      final handle = await writer.open(mode: FileMode.append);
      try {
        await handle.writeString(line);
        await handle.flush();
      } finally {
        await handle.close();
      }
    } else {
      final raf = await writer.open(mode: FileMode.write);
      try {
        await raf.writeFrom(prefix);
        await raf.writeString(line);
        await raf.flush();
      } finally {
        await raf.close();
      }
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
