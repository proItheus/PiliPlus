import 'dart:async' show unawaited;

import 'dart:io';

import 'package:PiliPlus/models_new/history/history.dart';
import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/utils/local_history.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

HistoryItemModel _item({
  required int oid,
  required int cid,
  required int progress,
}) => HistoryItemModel(
  title: 'Video $oid',
  history: History(oid: oid, cid: cid, business: 'archive'),
  viewAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
  progress: progress,
);

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'piliplus-local-history-test-',
    );
    Hive.init(tempDir.path);
    GStorage.regAdapter();
    GStorage.localHistory = await Hive.openBox('localHistory');
  });

  setUp(() async {
    await LocalHistory.clear();
  });

  tearDownAll(() async {
    await LocalHistory.flush();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('flush waits for every queued history record', () async {
    for (var index = 0; index < 10; index++) {
      unawaited(
        LocalHistory.record(
          _item(oid: index + 1, cid: index + 1, progress: index),
        ),
      );
    }

    await LocalHistory.flush();

    final loaded = LocalHistory.load();
    expect(loaded, hasLength(10));
    expect(
      loaded.map((item) => item.history.oid),
      containsAll(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
    );
  });
}
