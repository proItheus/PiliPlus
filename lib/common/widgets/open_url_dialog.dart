import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class OpenUrlDialog extends StatefulWidget {
  const OpenUrlDialog({super.key});

  @override
  State<OpenUrlDialog> createState() => _OpenUrlDialogState();
}

class _OpenUrlDialogState extends State<OpenUrlDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Get.back();
    _handleUrl(value);
  }

  void _handleUrl(String url) {
    try {
      PiliScheme.routePushFromUrl(url).then((handled) {
        if (!handled) {
          SmartDialog.showToast('无法处理此链接');
        }
      });
    } catch (e) {
      Utils.reportError(e);
      SmartDialog.showToast('无法处理此链接');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      constraints: Style.dialogFixedConstraints,
      title: const Text('打开链接'),
      content: TextField(
        autofocus: true,
        controller: _controller,
        decoration: const InputDecoration(
          hintText: '输入或粘贴链接（如 bilibili.com/...）',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('打开'),
        ),
      ],
    );
  }
}

void showOpenUrlDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => const OpenUrlDialog(),
  );
}
