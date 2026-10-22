import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/models_new/history/history.dart';
import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/utils/hybrid_logical_clock.dart';
import 'package:PiliPlus/utils/local_history.dart';
import 'package:PiliPlus/utils/local_history_sync.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as path;

HistoryItemModel _item({
  required int oid,
  required int cid,
  required int viewAt,
  int progress = 1,
}) => HistoryItemModel(
  title: 'Video $oid',
  history: History(oid: oid, cid: cid, business: 'archive'),
  viewAt: viewAt,
  progress: progress,
);

String _uuid(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

LocalHistorySyncEvent _event({
  required int eventId,
  required int nodeId,
  required int physicalMs,
  required LocalHistorySyncOperation op,
  String? key,
  HistoryItemModel? item,
  int logical = 0,
}) => LocalHistorySyncEvent(
  eventId: _uuid(eventId),
  nodeId: _uuid(nodeId),
  hlc: HlcTimestamp(physicalMs: physicalMs, logical: logical),
  op: op,
  key: key,
  item: item,
);

LocalHistorySyncEvent _upsert({
  required int eventId,
  required int nodeId,
  required int physicalMs,
  required HistoryItemModel item,
  int logical = 0,
}) => _event(
  eventId: eventId,
  nodeId: nodeId,
  physicalMs: physicalMs,
  logical: logical,
  op: LocalHistorySyncOperation.upsert,
  key: LocalHistorySync.keyOf(item),
  item: item,
);

LocalHistorySyncEvent _delete({
  required int eventId,
  required int nodeId,
  required int physicalMs,
  required String key,
}) => _event(
  eventId: eventId,
  nodeId: nodeId,
  physicalMs: physicalMs,
  op: LocalHistorySyncOperation.delete,
  key: key,
);

LocalHistorySyncEvent _clear({
  required int eventId,
  required int nodeId,
  required int physicalMs,
}) => _event(
  eventId: eventId,
  nodeId: nodeId,
  physicalMs: physicalMs,
  op: LocalHistorySyncOperation.clear,
);

Directory _eventsDirectory(Directory root) => Directory(
  path.join(root.path, 'PiliPlus', 'local-history-sync'),
);

Future<void> _writeEvents(
  Directory directory,
  String writer,
  List<LocalHistorySyncEvent> events, {
  bool append = false,
}) async {
  final file = File(path.join(directory.path, 'events-$writer.jsonl'));
  await file.writeAsString(
    '${events.map((event) => jsonEncode(event.toJson())).join('\n')}\n',
    mode: append ? FileMode.append : FileMode.write,
    flush: true,
  );
}

void main() {
  late Directory hiveDirectory;
  late Directory sharedRoot;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'piliplus-local-history-sync-hive-',
    );
    Hive.init(hiveDirectory.path);
    GStorage.regAdapter();
    GStorage.localHistory = await Hive.openBox('localHistory');
    GStorage.setting = await Hive.openBox('setting');
  });

  setUp(() async {
    await LocalHistorySync.close();
    await LocalHistory.flush();
    await GStorage.localHistory.clear();
    LocalHistorySync.debugSuppressHydrate = true;
    await GStorage.setting.clear();
    sharedRoot = await Directory.systemTemp.createTemp(
      'piliplus-local-history-sync-shared-',
    );
    await LocalHistorySync.initialize(LocalHistory.sync);
    await LocalHistorySync.configure(sharedRoot.path);
    await LocalHistorySync.close();
  });

  tearDown(() async {
    await LocalHistorySync.close();
    await LocalHistory.flush();
    if (sharedRoot.existsSync()) {
      await sharedRoot.delete(recursive: true);
    }
  });

  tearDownAll(() async {
    await LocalHistorySync.close();
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('slim v3 round-trips and legacy v2 events still decode', () {
    final item = _item(oid: 12, cid: 3, viewAt: 100, progress: -1);
    final event = _upsert(
      eventId: 1,
      nodeId: 2,
      physicalMs: 1000,
      item: item,
    );
    final json = event.toJson();
    expect(json['version'], 3);
    expect(json.containsKey('title'), isFalse);
    expect(json.containsKey('item'), isFalse);

    final decoded = LocalHistorySyncEvent.decode(json);
    expect(decoded?.key, 'archive|12|3');
    expect(decoded?.item?.progress, -1);
    expect(decoded?.item?.viewAt, 100);
    expect(decoded?.item?.history.oid, 12);
    expect(
      decoded?.hlc,
      const HlcTimestamp(physicalMs: 1000, logical: 0),
    );

    final dynamicMap = <dynamic, dynamic>{
      ...json,
      'hlc': <dynamic, dynamic>{...json['hlc'] as Map},
    };
    expect(LocalHistorySyncEvent.decode(dynamicMap)?.key, 'archive|12|3');

    final v2 = <String, dynamic>{
      'version': 2,
      'event_id': _uuid(1),
      'node_id': _uuid(2),
      'hlc': const HlcTimestamp(physicalMs: 1000, logical: 0).toJson(),
      'op': 'upsert',
      'key': 'archive|12|3',
      'item': item.toJson(),
    };
    final v2Decoded = LocalHistorySyncEvent.decode(v2);
    expect(v2Decoded?.item?.title, 'Video 12');
  });

  test('rejects legacy and malformed operation records', () {
    final base = <String, dynamic>{
      'version': 2,
      'event_id': _uuid(1),
      'node_id': _uuid(2),
      'hlc': const HlcTimestamp(physicalMs: 1, logical: 0).toJson(),
      'op': 'delete',
      'key': 'archive|12|3',
    };
    expect(LocalHistorySyncEvent.decode({...base, 'version': 1}), isNull);
    expect(
      LocalHistorySyncEvent.decode({
        ...base,
        'item': _item(oid: 12, cid: 3, viewAt: 1).toJson(),
      }),
      isNull,
    );
    expect(LocalHistorySyncEvent.decode({...base, 'unknown': true}), isNull);
    expect(
      LocalHistorySyncEvent.decode({...base, 'key': 'archive|012|3'}),
      isNull,
    );
  });

  test(
    'converges independent writer files and deterministic same-key winners',
    () async {
      final first = _item(oid: 100, cid: 1, viewAt: 100, progress: 1);
      final second = _item(oid: 200, cid: 2, viewAt: 200, progress: 2);
      final sameKeyFromFirst = _item(
        oid: 100,
        cid: 1,
        viewAt: 110,
        progress: 3,
      );
      final sameKeyFromSecond = _item(
        oid: 100,
        cid: 1,
        viewAt: 120,
        progress: 4,
      );
      final directory = _eventsDirectory(sharedRoot);

      await _writeEvents(directory, 'writer-a', [
        _upsert(eventId: 10, nodeId: 10, physicalMs: 100, item: first),
        _upsert(
          eventId: 12,
          nodeId: 10,
          physicalMs: 1000,
          item: sameKeyFromFirst,
        ),
      ]);
      await _writeEvents(directory, 'writer-b', [
        _upsert(eventId: 11, nodeId: 11, physicalMs: 200, item: second),
        _upsert(
          eventId: 13,
          nodeId: 11,
          physicalMs: 1000,
          item: sameKeyFromSecond,
        ),
      ]);

      await LocalHistorySync.sync();
      expect(LocalHistory.load(), hasLength(2));
      expect(
        LocalHistory.load().map(LocalHistory.keyOf),
        containsAll(<String>['archive|100|1', 'archive|200|2']),
      );
      expect(
        LocalHistory.load()
            .singleWhere((item) => item.history.oid == 100)
            .progress,
        4,
      );

      await _writeEvents(
        directory,
        'writer-a',
        [
          _upsert(
            eventId: 14,
            nodeId: 10,
            physicalMs: 1100,
            item: sameKeyFromFirst,
          ),
        ],
        append: true,
      );
      await LocalHistorySync.sync();
      expect(
        LocalHistory.load()
            .singleWhere((item) => item.history.oid == 100)
            .progress,
        3,
      );
      expect(LocalHistory.load(), hasLength(2));
    },
  );

  test('ignores duplicate events and conflicting event identities', () async {
    final first = _item(oid: 500, cid: 5, viewAt: 50, progress: 1);
    final conflicting = _item(oid: 500, cid: 5, viewAt: 51, progress: 2);
    final other = _item(oid: 501, cid: 5, viewAt: 52, progress: 3);
    final directory = _eventsDirectory(sharedRoot);
    final duplicate = _upsert(
      eventId: 40,
      nodeId: 40,
      physicalMs: 40,
      item: first,
    );
    final conflict = _upsert(
      eventId: 40,
      nodeId: 40,
      physicalMs: 40,
      item: conflicting,
    );

    await _writeEvents(directory, 'writer-a', [duplicate, duplicate]);
    await _writeEvents(directory, 'writer-b', [conflict]);
    await _writeEvents(
      directory,
      'writer-c',
      [_upsert(eventId: 41, nodeId: 41, physicalMs: 41, item: other)],
    );

    await LocalHistorySync.sync();
    expect(LocalHistory.load().map(LocalHistory.keyOf), ['archive|501|5']);
  });

  test(
    'retains tombstones, supports resurrection, and applies clear watermark',
    () async {
      final first = _item(oid: 100, cid: 1, viewAt: 10);
      final second = _item(oid: 200, cid: 2, viewAt: 20);
      final firstKey = LocalHistory.keyOf(first);
      final directory = _eventsDirectory(sharedRoot);

      await _writeEvents(directory, 'writer-a', [
        _upsert(eventId: 20, nodeId: 20, physicalMs: 10, item: first),
        _upsert(eventId: 21, nodeId: 20, physicalMs: 11, item: second),
        _delete(eventId: 22, nodeId: 20, physicalMs: 12, key: firstKey),
        _upsert(
          eventId: 23,
          nodeId: 21,
          physicalMs: 11,
          item: _item(oid: 100, cid: 1, viewAt: 11, progress: 9),
        ),
      ]);
      await LocalHistorySync.sync();
      expect(LocalHistory.load().map(LocalHistory.keyOf), ['archive|200|2']);
      await LocalHistorySync.close();
      await LocalHistorySync.initialize(LocalHistory.sync);
      await LocalHistorySync.sync();
      expect(LocalHistory.load().map(LocalHistory.keyOf), ['archive|200|2']);

      await _writeEvents(
        directory,
        'writer-b',
        [
          _upsert(
            eventId: 24,
            nodeId: 21,
            physicalMs: 13,
            item: _item(oid: 100, cid: 1, viewAt: 13, progress: 13),
          ),
        ],
      );
      await LocalHistorySync.sync();
      expect(LocalHistory.load().map(LocalHistory.keyOf), contains(firstKey));

      await _writeEvents(
        directory,
        'writer-c',
        [_clear(eventId: 25, nodeId: 22, physicalMs: 14)],
      );
      await LocalHistorySync.sync();
      expect(LocalHistory.load(), isEmpty);
      await LocalHistorySync.close();
      await LocalHistorySync.initialize(LocalHistory.sync);
      await LocalHistorySync.sync();
      expect(LocalHistory.load(), isEmpty);

      await _writeEvents(
        directory,
        'writer-c',
        [_upsert(eventId: 26, nodeId: 22, physicalMs: 15, item: second)],
        append: true,
      );
      await LocalHistorySync.sync();
      expect(LocalHistory.load().map(LocalHistory.keyOf), ['archive|200|2']);
    },
  );

  test('skips malformed lines and retries an incomplete UTF-8 tail', () async {
    final first = _item(oid: 100, cid: 1, viewAt: 10);
    final second = _item(oid: 200, cid: 2, viewAt: 20)..title = '中文视频';
    final firstLine = jsonEncode(
      _upsert(eventId: 30, nodeId: 30, physicalMs: 10, item: first).toJson(),
    );
    final secondLine = jsonEncode(
      _upsert(eventId: 31, nodeId: 30, physicalMs: 20, item: second).toJson(),
    );
    final secondBytes = utf8.encode(secondLine);
    final split = secondBytes.indexOf(0xe4) + 1;
    expect(split, greaterThan(0));
    final file = File(
      path.join(_eventsDirectory(sharedRoot).path, 'events-tail.jsonl'),
    );
    await file.writeAsBytes([
      ...utf8.encode('$firstLine\nnot-json\n'),
      ...secondBytes.sublist(0, split),
    ], flush: true);

    await LocalHistorySync.sync();
    expect(LocalHistory.load().map(LocalHistory.keyOf), ['archive|100|1']);

    await file.writeAsBytes(
      [...secondBytes.sublist(split), 0x0a],
      mode: FileMode.append,
      flush: true,
    );
    await LocalHistorySync.sync();
    expect(
      LocalHistory.load().map(LocalHistory.keyOf),
      containsAll(<String>['archive|100|1', 'archive|200|2']),
    );
  });

  test('bootstraps existing local records into a new shared root', () async {
    await LocalHistorySync.configure('');
    final item = _item(oid: 300, cid: 3, viewAt: 30);
    await LocalHistory.record(item);

    final newRoot = await Directory.systemTemp.createTemp(
      'piliplus-local-history-sync-bootstrap-',
    );
    addTearDown(() async {
      if (newRoot.existsSync()) await newRoot.delete(recursive: true);
    });

    await LocalHistorySync.configure(newRoot.path);
    expect(LocalHistory.load().map(LocalHistory.keyOf), ['archive|300|3']);
    final eventFiles = await _eventsDirectory(newRoot)
        .list()
        .where((entry) => entry is File)
        .cast<File>()
        .where((file) => path.basename(file.path).endsWith('.jsonl'))
        .toList();
    expect(eventFiles, hasLength(1));
  });

  test('retains local projection when bootstrap publication fails', () async {
    final seed = _item(oid: 301, cid: 3, viewAt: 31);
    await LocalHistory.record(seed);
    final writerFiles = await _eventsDirectory(sharedRoot)
        .list()
        .where((entry) => entry is File)
        .cast<File>()
        .where((file) => path.basename(file.path).endsWith('.jsonl'))
        .toList();
    expect(writerFiles, hasLength(1));
    final writerName = path.basename(writerFiles.single.path);

    await LocalHistorySync.configure('');
    await LocalHistory.clear();
    final first = _item(oid: 302, cid: 3, viewAt: 32);
    final second = _item(oid: 303, cid: 3, viewAt: 33);
    await LocalHistory.record(first);
    await LocalHistory.record(second);

    final newRoot = await Directory.systemTemp.createTemp(
      'piliplus-local-history-sync-bootstrap-failure-',
    );
    addTearDown(() async {
      if (newRoot.existsSync()) await newRoot.delete(recursive: true);
    });
    final newEvents = _eventsDirectory(newRoot);
    await newEvents.create(recursive: true);
    final blockedWriter = Directory(path.join(newEvents.path, writerName));
    await blockedWriter.create();

    await LocalHistorySync.configure(newRoot.path);
    expect(
      LocalHistory.load().map(LocalHistory.keyOf),
      containsAll(<String>['archive|302|3', 'archive|303|3']),
    );
    final pending = GStorage.localHistory.get(LocalHistoryBoxKey.syncOutbox);
    expect(pending, isA<List>().having((value) => value, 'events', isNotEmpty));

    await blockedWriter.delete();
    await LocalHistorySync.sync();
    expect(GStorage.localHistory.get(LocalHistoryBoxKey.syncOutbox), isEmpty);
    expect(
      LocalHistory.load().map(LocalHistory.keyOf),
      containsAll(<String>['archive|302|3', 'archive|303|3']),
    );
  });

  test('recreates a missing event directory during retry', () async {
    await _eventsDirectory(sharedRoot).delete(recursive: true);
    final item = _item(oid: 350, cid: 3, viewAt: 35);

    await LocalHistory.record(item);

    expect(GStorage.localHistory.get(LocalHistoryBoxKey.syncOutbox), isEmpty);
    final eventFiles = await _eventsDirectory(sharedRoot)
        .list()
        .where((entry) => entry is File)
        .cast<File>()
        .where((file) => path.basename(file.path).endsWith('.jsonl'))
        .toList();
    expect(eventFiles, hasLength(1));
  });

  test('retains outbox after append failure and drains after retry', () async {
    await LocalHistorySync.configure('');
    final blocked = File(path.join(sharedRoot.path, 'blocked'));
    await blocked.writeAsString('not-a-directory');
    await GStorage.setting.put(
      SettingBoxKey.localHistorySyncDirectory,
      blocked.path,
    );

    final item = _item(oid: 400, cid: 4, viewAt: 40);
    await LocalHistory.record(item);
    expect(LocalHistory.load().map(LocalHistory.keyOf), ['archive|400|4']);
    final pending = GStorage.localHistory.get(LocalHistoryBoxKey.syncOutbox);
    expect(pending, isA<List>().having((value) => value, 'events', isNotEmpty));

    final validRoot = await Directory.systemTemp.createTemp(
      'piliplus-local-history-sync-retry-',
    );
    addTearDown(() async {
      if (validRoot.existsSync()) await validRoot.delete(recursive: true);
    });
    await LocalHistorySync.configure(validRoot.path);
    expect(GStorage.localHistory.get(LocalHistoryBoxKey.syncOutbox), isEmpty);
    final eventFiles = await _eventsDirectory(validRoot)
        .list()
        .where((entry) => entry is File)
        .cast<File>()
        .where((file) => path.basename(file.path).endsWith('.jsonl'))
        .toList();
    expect(eventFiles, hasLength(1));
  });

  Future<List<String>> readLines() async => [
    for (final f in await _eventsDirectory(
      sharedRoot,
    ).list().where((entry) => entry is File).cast<File>().toList())
      ...await f.readAsLines(),
  ];

  test('suppresses same-key republish within the publish interval', () async {
    await LocalHistory.record(_item(oid: 600, cid: 1, viewAt: 1));
    await LocalHistory.record(_item(oid: 600, cid: 1, viewAt: 99));
    final lines = await readLines();
    expect(lines, hasLength(1));
    final decoded = LocalHistorySyncEvent.decode(jsonDecode(lines.single));
    expect(decoded?.item?.viewAt, 1);
  });

  test('force and completed publishes bypass the sparse gate', () async {
    await LocalHistory.record(_item(oid: 700, cid: 1, viewAt: 1));
    await LocalHistory.record(
      _item(oid: 700, cid: 1, viewAt: 2),
      forcePublish: true,
    );
    await LocalHistory.record(
      _item(oid: 700, cid: 1, viewAt: 4, progress: -1),
    );
    final lines = await readLines();
    final decoded = LocalHistorySyncEvent.decode(jsonDecode(lines.single));
    expect(decoded?.item?.progress, -1);
    expect(decoded?.item?.viewAt, 4);
  });

  test('truncates consecutive same-key lines on append', () async {
    await LocalHistory.record(_item(oid: 710, cid: 1, viewAt: 1));
    await LocalHistory.record(
      _item(oid: 710, cid: 1, viewAt: 2),
      forcePublish: true,
    );
    await LocalHistory.record(
      _item(oid: 710, cid: 1, viewAt: 3),
      forcePublish: true,
    );
    final lines = await readLines();
    expect(lines, hasLength(1));
    final decoded = LocalHistorySyncEvent.decode(jsonDecode(lines.single));
    expect(decoded?.item?.viewAt, 3);
  });

  test(
    'builds projection from slim v3 events with placeholder display fields',
    () async {
      final directory = _eventsDirectory(sharedRoot);
      final item = _item(oid: 800, cid: 1, viewAt: 10);
      await _writeEvents(
        directory,
        'writer-a',
        [_upsert(eventId: 80, nodeId: 80, physicalMs: 80, item: item)],
      );
      await LocalHistorySync.sync();
      expect(LocalHistory.load().map(LocalHistory.keyOf), ['archive|800|1']);
      final row = LocalHistory.load().single;
      expect(row.progress, 1);
      expect(row.title, isNull);
    },
  );

  test('fills display metadata from the cache during reconciliation', () async {
    const key = 'archive|800|1';
    await GStorage.localHistory.put(
      LocalHistoryBoxKey.videoMeta,
      {
        key: {'title': 'Cached Title', 'cover': 'http://cover'},
      },
    );
    final directory = _eventsDirectory(sharedRoot);
    final item = _item(oid: 800, cid: 1, viewAt: 10);
    await _writeEvents(
      directory,
      'writer-b',
      [_upsert(eventId: 81, nodeId: 81, physicalMs: 81, item: item)],
    );
    await LocalHistorySync.sync();
    final row = LocalHistory.load().single;
    expect(row.title, 'Cached Title');
    expect(row.cover, 'http://cover');
  });

  test('persists writer id across sessions so publishes reuse the same event file', () async {
    await LocalHistorySync.initialize(LocalHistory.sync);
    await LocalHistorySync.configure(sharedRoot.path);
    await LocalHistorySync.publishUpsert(
      _item(oid: 900, cid: 9, viewAt: 100),
      force: true,
    );
    final directory = _eventsDirectory(sharedRoot);
    Future<String> writerFileName() async {
      final files = await directory
          .list(followLinks: false)
          .where(
            (entry) =>
                entry is File &&
                path.basename(entry.path).startsWith('events-') &&
                entry.path.endsWith('.jsonl'),
          )
          .cast<File>()
          .toList();
      expect(files, hasLength(1));
      return path.basename(files.single.path);
    }

    final first = await writerFileName();
    await LocalHistorySync.close();
    await LocalHistorySync.initialize(LocalHistory.sync);
    await LocalHistorySync.configure(sharedRoot.path);
    await LocalHistorySync.publishUpsert(
      _item(oid: 901, cid: 9, viewAt: 200),
      force: true,
    );
    expect(await writerFileName(), first);
  });

  test('rotation on append failure persists the fresh writer id', () async {
    await LocalHistorySync.initialize(LocalHistory.sync);
    await LocalHistorySync.configure(sharedRoot.path);
    await LocalHistorySync.publishUpsert(
      _item(oid: 910, cid: 9, viewAt: 100),
      force: true,
    );
    final directory = _eventsDirectory(sharedRoot);
    final files = await directory
        .list(followLinks: false)
        .where(
          (entry) =>
              entry is File &&
              path.basename(entry.path).startsWith('events-') &&
              entry.path.endsWith('.jsonl'),
        )
        .cast<File>()
        .toList();
    expect(files, hasLength(1));
    final writerName = path.basename(files.single.path);

    // Sabotage the current writer path so appending fails.
    await files.single.delete();
    await Directory(path.join(directory.path, writerName)).create();

    Map<String, dynamic> metadata() => Map<String, dynamic>.from(
          GStorage.localHistory.get(LocalHistoryBoxKey.syncMetadata) as Map,
        );
    final writerIdBefore = metadata()['writer_id'];

    await expectLater(
      LocalHistorySync.publishUpsert(
        _item(oid: 911, cid: 9, viewAt: 200),
        force: true,
      ),
      throwsA(isA<Object>()),
    );
    final writerIdAfter = metadata()['writer_id'];
    expect(writerIdAfter, isNot(writerIdBefore));

    await Directory(path.join(directory.path, writerName)).delete();
    await LocalHistorySync.publishUpsert(
      _item(oid: 912, cid: 9, viewAt: 300),
      force: true,
    );
    expect(GStorage.localHistory.get(LocalHistoryBoxKey.syncOutbox), isEmpty);
    final after = await directory
        .list(followLinks: false)
        .where(
          (entry) =>
              entry is File &&
              path.basename(entry.path).startsWith('events-') &&
              entry.path.endsWith('.jsonl'),
        )
        .cast<File>()
        .toList();
    expect(after, hasLength(1));
    expect(path.basename(after.single.path), isNot(writerName));
  });
}
