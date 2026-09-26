import 'dart:io';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/dynamics/result.dart';
import 'package:PiliPlus/models_new/local_subscription.dart';
import 'package:PiliPlus/pages/local_subscription_feed/controller.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-local-feed-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox<dynamic>('setting');
    GStorage.localCache = await Hive.openBox<dynamic>('localCache');
    GStorage.video = await Hive.openBox<dynamic>('video');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('merges sources by timestamp and advances each cursor once', () async {
    final pages = <int, List<DynamicsDataModel>>{
      1: [
        _page([
          _item('a', 100, 1),
          _item('duplicate', 80, 1),
        ], offset: 'a2'),
        _page([_item('c', 60, 1)], offset: '-1', hasMore: false),
      ],
      2: [
        _page([
          _item('b', 90, 2),
          _item('duplicate', 70, 2),
        ], offset: 'b2'),
        _page([_item('d', 50, 2)], offset: '-1', hasMore: false),
      ],
    };
    final calls = <String>[];
    final controller = LocalSubscriptionFeedController(
      subscriptions: const [
        LocalSubscription(mid: 1),
        LocalSubscription(mid: 2),
      ],
      batchSize: 3,
      fetcher: ({required mid, offset}) async {
        calls.add('$mid:${offset ?? ''}');
        return Success(pages[mid]!.removeAt(0));
      },
    );

    await controller.queryData();
    expect(_ids(controller), ['a', 'b', 'duplicate']);
    await controller.onLoadMore();
    expect(_ids(controller), ['a', 'b', 'duplicate', 'c', 'd']);
    expect(calls, [
      '1:',
      '2:',
      '1:a2',
      '2:b2',
    ]);
    expect(controller.isEnd, isTrue);
  });

  test('keeps successful content when one source fails', () async {
    final controller = LocalSubscriptionFeedController(
      subscriptions: const [
        LocalSubscription(mid: 1),
        LocalSubscription(mid: 2),
      ],
      fetcher: ({required mid, offset}) async => mid == 1
          ? Success(_page([_item('ok', 10, 1)], hasMore: false))
          : const Error('offline'),
    );

    await controller.queryData();
    expect(_ids(controller), ['ok']);
    expect(controller.failedSources.single.mid, 2);
  });

  test('keeps successful content when another fetcher throws', () async {
    final controller = LocalSubscriptionFeedController(
      subscriptions: const [
        LocalSubscription(mid: 1),
        LocalSubscription(mid: 2),
      ],
      fetcher: ({required mid, offset}) async {
        if (mid == 2) throw StateError('offline');
        return Success(_page([_item('ok', 10, 1)], hasMore: false));
      },
    );

    await controller.queryData();
    expect(_ids(controller), ['ok']);
    expect(controller.failedSources.single.mid, 2);
  });

  test('reports a source that fails while filling a batch', () async {
    final controller = LocalSubscriptionFeedController(
      subscriptions: const [
        LocalSubscription(mid: 1),
        LocalSubscription(mid: 2),
      ],
      batchSize: 3,
      fetcher: ({required mid, offset}) async {
        if (mid == 1 && offset != null) throw StateError('offline');
        return mid == 1
            ? Success(_page([_item('a', 20, 1)], offset: 'a2'))
            : Success(_page([_item('b', 10, 2)], hasMore: false));
      },
    );

    await controller.queryData();
    expect(_ids(controller), ['a', 'b']);
    expect(controller.failedSources.single.mid, 1);
  });

  test('uses saved creator order when timestamps tie', () async {
    final controller = LocalSubscriptionFeedController(
      subscriptions: const [
        LocalSubscription(mid: 10),
        LocalSubscription(mid: 20),
      ],
      fetcher: ({required mid, offset}) async => Success(
        _page([
          _item(mid == 10 ? 'first' : 'second', 100, mid),
        ], hasMore: false),
      ),
    );

    await controller.queryData();
    expect(_ids(controller), ['first', 'second']);
  });

  test('uses the normal error state when every source fails', () async {
    final controller = LocalSubscriptionFeedController(
      subscriptions: const [LocalSubscription(mid: 1)],
      fetcher: ({required mid, offset}) async => const Error('offline'),
    );

    await controller.queryData();
    expect(controller.loadingState.value, isA<Error>());
    expect(controller.failedSources.single.mid, 1);
  });

  test('advances through empty pages and retains null IDs', () async {
    final calls = <String>[];
    final controller = LocalSubscriptionFeedController(
      subscriptions: const [LocalSubscription(mid: 1)],
      batchSize: 2,
      fetcher: ({required mid, offset}) async {
        calls.add('$mid:${offset ?? ''}');
        return offset == null
            ? Success(_page(const [], offset: 'next'))
            : Success(
                _page([_item(null, 10, 1)], offset: '-1', hasMore: false),
              );
      },
    );

    await controller.queryData();

    expect(_idValues(controller), [null]);
    expect(calls, ['1:', '1:next']);
    expect(controller.isEnd, isTrue);
  });
}

List<String> _ids(LocalSubscriptionFeedController controller) {
  final state = controller.loadingState.value;
  return state is Success<List<DynamicItemModel>?>
      ? state.response!.map((item) => item.idStr as String).toList()
      : <String>[];
}

List<Object?> _idValues(LocalSubscriptionFeedController controller) {
  final state = controller.loadingState.value;
  return state is Success<List<DynamicItemModel>?>
      ? state.response!.map<Object?>((item) => item.idStr).toList()
      : <Object?>[];
}

DynamicsDataModel _page(
  List<Map<String, dynamic>> items, {
  String? offset,
  bool hasMore = true,
}) {
  return DynamicsDataModel.fromJson({
    'has_more': hasMore,
    'offset': offset,
    'items': items,
  });
}

Map<String, dynamic> _item(Object? id, int timestamp, int mid) => {
  'id_str': id,
  'modules': {
    'module_author': {
      'mid': mid,
      'name': 'creator $mid',
      'pub_ts': timestamp,
    },
  },
};
