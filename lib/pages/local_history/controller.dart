import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/pages/common/multi_select/base.dart';
import 'package:PiliPlus/utils/local_history.dart';
import 'package:get/get.dart';

class LocalHistoryController extends GetxController
    with BaseMultiSelectMixin<HistoryItemModel> {
  late final RxList<HistoryItemModel> items = LocalHistory.load().obs;

  @override
  RxObjectMixin get state => items;

  @override
  List<HistoryItemModel> get list => items;

  void refreshList() {
    items.value = LocalHistory.load();
  }

  @override
  void onRemove() {
    final checked = items.where((e) => e.checked).toList();
    if (checked.isEmpty) return;
    Future.wait(checked.map(LocalHistory.remove)).then((_) {
      if (!isClosed) refreshList();
    });
    handleSelect();
  }
}
