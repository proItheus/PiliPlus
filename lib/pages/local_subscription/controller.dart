import 'package:PiliPlus/models_new/local_subscription.dart';
import 'package:PiliPlus/utils/local_subscriptions.dart';
import 'package:get/get.dart';

class LocalSubscriptionController extends GetxController {
  final RxList<LocalSubscription> items = LocalSubscriptions.load().obs;

  void refreshList() {
    items.assignAll(LocalSubscriptions.load());
  }

  Future<void> remove(LocalSubscription item) async {
    await LocalSubscriptions.remove(item.mid);
    if (!isClosed) refreshList();
  }

  Future<void> clear() async {
    await LocalSubscriptions.clear();
    if (!isClosed) refreshList();
  }
}
