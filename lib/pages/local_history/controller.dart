import 'dart:async' show StreamSubscription, unawaited;

import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/pages/common/multi_select/base.dart';
import 'package:PiliPlus/utils/local_history.dart';
import 'package:PiliPlus/utils/local_history_sync.dart';
import 'package:get/get.dart';

class LocalHistoryController extends GetxController
    with BaseMultiSelectMixin<HistoryItemModel> {
  late final RxList<HistoryItemModel> items = <HistoryItemModel>[].obs;
  late final StreamSubscription<void> _changes;

  @override
  void onInit() {
    super.onInit();
    unawaited(_load());
    _changes = LocalHistorySync.changes.listen((_) {
      if (!isClosed) items.value = LocalHistory.load();
    });
  }

  Future<void> _load() async {
    await LocalHistory.sync();
    if (!isClosed) items.value = LocalHistory.load();
  }

  @override
  RxObjectMixin get state => items;

  @override
  List<HistoryItemModel> get list => items;

  void refreshList() => unawaited(_refreshList());

  Future<void> _refreshList() async {
    await LocalHistory.sync();
    if (!isClosed) items.value = LocalHistory.load();
  }

  Future<void> refreshAndWait() => _refreshList();

  @override
  void onRemove() {
    final checked = items.where((e) => e.checked).toList();
    if (checked.isEmpty) return;
    Future.wait(checked.map(LocalHistory.remove)).then((_) {
      if (!isClosed) refreshList();
    });
    handleSelect();
  }

  @override
  void onClose() {
    unawaited(_changes.cancel());
    super.onClose();
  }
}
