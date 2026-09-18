import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/pendant_avatar.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/models_new/local_subscription.dart';
import 'package:PiliPlus/pages/local_subscription/controller.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class LocalSubscriptionPage extends StatefulWidget {
  const LocalSubscriptionPage({super.key});

  @override
  State<LocalSubscriptionPage> createState() => _LocalSubscriptionPageState();
}

class _LocalSubscriptionPageState extends State<LocalSubscriptionPage> {
  late final LocalSubscriptionController _controller;

  @override
  void initState() {
    super.initState();
    _controller = Get.put(LocalSubscriptionController());
  }

  @override
  void dispose() {
    Get.delete<LocalSubscriptionController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SimpleScaffold(
      appBar: AppBar(
        title: const Text('本地订阅'),
        actions: [
          PopupMenuButton(
            itemBuilder: (_) => [
              PopupMenuItem(onTap: _clear, child: const Text('清空本地订阅')),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Obx(() {
        final items = _controller.items;
        if (items.isEmpty) {
          return Center(
            child: Text(
              '暂无本地订阅\n在 UP 主主页菜单中添加',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          );
        }
        return ListView.separated(
          padding: EdgeInsets.only(
            top: 8,
            bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
          ),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) => _buildItem(items[index]),
        );
      }),
    );
  }

  Widget _buildItem(LocalSubscription item) {
    final name = item.name?.isNotEmpty == true ? item.name! : 'UID ${item.mid}';
    final sign = item.sign?.trim();
    return ListTile(
      leading: PendantAvatar(item.face, size: 48),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        sign?.isNotEmpty == true ? sign! : 'UID: ${item.mid}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () =>
          Get.toNamed('/member?mid=${item.mid}')
              ?.whenComplete(_controller.refreshList),
      trailing: IconButton(
        tooltip: '移除本地订阅',
        onPressed: () => _remove(item),
        icon: const Icon(Icons.remove_circle_outline),
      ),
    );
  }

  Future<void> _remove(LocalSubscription item) async {
    final name = item.name?.isNotEmpty == true ? item.name! : 'UID ${item.mid}';
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text('移除 $name？'),
    );
    if (!confirmed) return;
    await _controller.remove(item);
    SmartDialog.showToast('已移除');
  }

  void _clear() {
    showConfirmDialog(
      context: context,
      title: const Text('清空本地订阅？'),
      content: const Text('只会清除本地列表，不会影响账号关注。'),
      onConfirm: () async {
        await _controller.clear();
        SmartDialog.showToast('已清空');
      },
    );
  }
}
