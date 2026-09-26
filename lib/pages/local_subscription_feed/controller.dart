import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/member.dart';
import 'package:PiliPlus/models/dynamics/result.dart';
import 'package:PiliPlus/models_new/local_subscription.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:PiliPlus/utils/local_subscriptions.dart';
import 'package:get/get.dart';

/// Fetches one page of a creator's dynamic timeline.
///
/// The named arguments intentionally match [MemberHttp.memberDynamic], which
/// keeps the production seam a direct adapter and makes fake pages convenient
/// to provide in controller tests.
typedef LocalSubscriptionDynamicFetcher =
    Future<LoadingState<DynamicsDataModel>> Function({
      required int mid,
      String? offset,
    });

class LocalSubscriptionFeedController
    extends CommonListController<LocalSubscriptionFeedBatch, DynamicItemModel> {
  LocalSubscriptionFeedController({
    LocalSubscriptionDynamicFetcher? fetcher,
    this.subscriptions,
    List<LocalSubscription> Function()? subscriptionsLoader,
    this.batchSize = 20,
  }) : assert(batchSize > 0),
       _fetcher = fetcher ?? MemberHttp.memberDynamic,
       _subscriptionsLoader = subscriptionsLoader ?? LocalSubscriptions.load;

  final LocalSubscriptionDynamicFetcher _fetcher;
  final List<LocalSubscription>? subscriptions;
  final List<LocalSubscription> Function() _subscriptionsLoader;
  final int batchSize;

  /// True when the saved list is empty. This is separate from an empty feed:
  /// the latter means saved creators exist but have no available dynamics.
  final RxBool isLocalListEmpty = false.obs;

  /// Creators that failed during the current refresh/pagination session.
  final RxList<LocalSubscription> failedSources = <LocalSubscription>[].obs;

  List<_FeedSource> _sources = <_FeedSource>[];
  final Set<Object> _emittedIds = <Object>{};
  bool _hasProducedContent = false;

  bool get hasPartialFailure => failedSources.isNotEmpty;

  @override
  void onInit() {
    super.onInit();
    queryData();
  }

  @override
  Future<void> queryData([bool isRefresh = true]) {
    if (isRefresh) {
      if (isLoading) return Future<void>.value();
      _resetSources();
    }
    return super.queryData(isRefresh);
  }

  @override
  Future<void> onRefresh() => queryData();

  @override
  List<DynamicItemModel>? getDataList(LocalSubscriptionFeedBatch response) =>
      response.items;

  @override
  bool customHandleResponse(
    bool isRefresh,
    Success<LocalSubscriptionFeedBatch> response,
  ) {
    final batch = response.response;
    failedSources.assignAll(batch.failedSources);
    isEnd = !batch.hasMore;
    return false;
  }

  @override
  Future<LoadingState<LocalSubscriptionFeedBatch>> customGetData() async {
    if (_sources.isEmpty) {
      isLocalListEmpty.value = true;
      return const Success(LocalSubscriptionFeedBatch.empty());
    }

    await _ensureCandidates();
    final failed = _sources
        .where((source) => source.unavailable)
        .map((source) => source.subscription)
        .toList(growable: false);
    failedSources.assignAll(failed);

    // An error state is reserved for the case where every creator request
    // failed. An empty successful response from one source is not a request
    // failure and therefore remains a usable no-content state.
    if (failed.length == _sources.length && !_hasProducedContent) {
      return Error(_errorMessage(failed));
    }

    final items = await _takeMergedItems();
    final failedAfterMerge = _sources
        .where((source) => source.unavailable)
        .map((source) => source.subscription)
        .toList(growable: false);
    failedSources.assignAll(failedAfterMerge);
    final hasMore = _sources.any(
      (source) =>
          !source.unavailable && (source.hasMore || source.hasBufferedItems),
    );
    return Success(
      LocalSubscriptionFeedBatch(
        items: items,
        hasMore: hasMore,
        failedSources: failedAfterMerge,
      ),
    );
  }

  void _resetSources() {
    final saved = subscriptions ?? _subscriptionsLoader();
    final seen = <int>{};
    _sources = <_FeedSource>[];
    for (final subscription in saved) {
      if (seen.add(subscription.mid)) {
        _sources.add(_FeedSource(subscription, _sources.length));
      }
    }
    isLocalListEmpty.value = _sources.isEmpty;
    failedSources.clear();
    _emittedIds.clear();
    _hasProducedContent = false;
    page = 1;
    isEnd = false;
  }

  Future<void> _ensureCandidates() async {
    while (true) {
      final toFetch = _sources
          .where(
            (source) =>
                !source.unavailable &&
                !source.hasBufferedItems &&
                source.hasMore,
          )
          .toList(growable: false);
      if (toFetch.isEmpty) return;
      await Future.wait(toFetch.map(_fetchPage));
      if (toFetch.every((source) => !source.hasBufferedItems)) {
        // _fetchPage changes hasMore when a page has no usable continuation,
        // so this loop only repeats for a page that yielded no items but did
        // provide a valid next cursor.
        continue;
      }
      return;
    }
  }

  Future<void> _fetchPage(_FeedSource source) async {
    if (source.unavailable || !source.hasMore) return;
    final requestedOffset = source.offset;
    try {
      final result = await _fetcher(
        mid: source.subscription.mid,
        offset: requestedOffset,
      );
      switch (result) {
        case Success(:final response):
          final nextOffset = response.offset;
          final canContinue =
              response.hasMore != false &&
              nextOffset != null &&
              nextOffset.isNotEmpty &&
              nextOffset != '-1' &&
              nextOffset != requestedOffset;
          source
            ..offset = nextOffset
            ..hasMore = canContinue;
          final items = response.items;
          if (items != null && items.isNotEmpty) {
            source.buffer.addAll(items);
          }
        case Error():
          source.unavailable = true;
        case Loading():
          source.unavailable = true;
      }
    } on Object {
      source.unavailable = true;
    }
  }

  Future<List<DynamicItemModel>> _takeMergedItems() async {
    final result = <DynamicItemModel>[];
    while (result.length < batchSize) {
      await _ensureCandidates();
      _FeedSource? selected;
      for (final source in _sources) {
        if (!source.hasBufferedItems) continue;
        if (selected == null || _compareHeads(source, selected) < 0) {
          selected = source;
        }
      }
      if (selected == null) break;
      final item = selected.take()!;
      final id = item.idStr;
      if (id != null && !_emittedIds.add(id)) continue;
      result.add(item);
      _hasProducedContent = true;
    }
    return result;
  }

  int _compareHeads(_FeedSource left, _FeedSource right) {
    final leftTs = left.peek()!.modules.moduleAuthor?.pubTs ?? 0;
    final rightTs = right.peek()!.modules.moduleAuthor?.pubTs ?? 0;
    if (leftTs != rightTs) return rightTs.compareTo(leftTs);
    if (left.order != right.order) return left.order.compareTo(right.order);
    return left.bufferIndex.compareTo(right.bufferIndex);
  }

  String _errorMessage(List<LocalSubscription> failed) {
    if (failed.isEmpty) return '本地订阅动态加载失败';
    return '本地订阅动态加载失败，请重试';
  }
}

class _FeedSource {
  _FeedSource(this.subscription, this.order);

  final LocalSubscription subscription;
  final int order;
  String? offset;
  bool hasMore = true;
  bool unavailable = false;
  final List<DynamicItemModel> buffer = <DynamicItemModel>[];
  int bufferIndex = 0;

  bool get hasBufferedItems => bufferIndex < buffer.length;

  DynamicItemModel? peek() => hasBufferedItems ? buffer[bufferIndex] : null;

  DynamicItemModel? take() => hasBufferedItems ? buffer[bufferIndex++] : null;
}

class LocalSubscriptionFeedBatch {
  const LocalSubscriptionFeedBatch({
    required this.items,
    required this.hasMore,
    this.failedSources = const <LocalSubscription>[],
  });

  const LocalSubscriptionFeedBatch.empty()
    : items = const <DynamicItemModel>[],
      hasMore = false,
      failedSources = const <LocalSubscription>[];

  final List<DynamicItemModel> items;
  final bool hasMore;
  final List<LocalSubscription> failedSources;
}
