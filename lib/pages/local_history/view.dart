import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:PiliPlus/common/widgets/appbar/appbar.dart';
import 'package:PiliPlus/common/widgets/dialog/export_import.dart';
import 'package:PiliPlus/common/widgets/flutter/pop_scope.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/pages/history/widgets/item.dart';
import 'package:PiliPlus/pages/local_history/controller.dart';
import 'package:PiliPlus/pages/setting/widgets/select_dialog.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/local_history.dart';
import 'package:PiliPlus/utils/local_history_sync.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class LocalHistoryPage extends StatefulWidget {
  const LocalHistoryPage({super.key});

  @override
  State<LocalHistoryPage> createState() => _LocalHistoryPageState();
}

class _LocalHistoryPageState extends State<LocalHistoryPage> with GridMixin {
  late final LocalHistoryController _controller;

  @override
  void initState() {
    super.initState();
    _controller = Get.put(LocalHistoryController());
  }

  @override
  void dispose() {
    Get.delete<LocalHistoryController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final enableMultiSelect = _controller.enableMultiSelect.value;
      return popScope(
        canPop: !enableMultiSelect,
        onPopInvokedWithResult: (didPop, result) {
          if (enableMultiSelect) _controller.handleSelect();
        },
        child: SimpleScaffold(
          appBar: MultiSelectAppBarWidget(
            visible: enableMultiSelect,
            ctr: _controller,
            child: _buildAppBar,
          ),
          body: Obx(() {
            final items = _controller.items;
            if (items.isEmpty) {
              return Center(
                child: Text(
                  '暂无本地观看记录',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              );
            }
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.only(
                    top: 7,
                    bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
                  ),
                  sliver: SliverGrid.builder(
                    gridDelegate: gridDelegate,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return HistoryItem(
                        item: item,
                        ctr: _controller,
                        onDelete: (kid, business) => _deleteItem(item),
                      );
                    },
                    itemCount: items.length,
                  ),
                ),
              ],
            );
          }),
        ),
      );
    });
  }

  AppBar get _buildAppBar => AppBar(
    title: const Text('本地观看记录'),
    actions: [
      PopupMenuButton(
        itemBuilder: (_) => [
          PopupMenuItem(
            onTap: _exportToFile,
            child: const Text('导出文件至本地'),
          ),
          PopupMenuItem(
            onTap: _exportToClipboard,
            child: const Text('导出至剪贴板'),
          ),
          PopupMenuItem(
            onTap: _importFromFile,
            child: const Text('从本地文件导入'),
          ),
          PopupMenuItem(
            onTap: _importFromClipboard,
            child: const Text('从剪贴板导入'),
          ),
          if (LocalHistorySync.supported)
            PopupMenuItem(
              onTap: _configureSync,
              child: Text(
                Pref.localHistorySyncDirectory.isEmpty
                    ? '启用自动同步'
                    : '自动同步：${Pref.localHistorySyncDirectory}',
              ),
            ),
          PopupMenuItem(
            onTap: _clearAll,
            child: const Text('清空本地历史'),
          ),
        ],
      ),
      const SizedBox(width: 6),
    ],
  );

  void _exportToFile() {
    exportToLocalFile(
      onExport: _exportJson,
      localFileName: () => 'local_history',
    );
  }

  void _exportToClipboard() {
    exportToClipBoard(onExport: _exportJson);
  }

  ValueGetter<String> get _exportJson =>
      () => jsonEncode(
        _controller.items.map((e) => e.toJson()).toList(),
      );

  Future<void> _importFromFile() async {
    final result = await FilePicker.pickFile(
      type: .custom,
      allowedExtensions: const ['json', 'txt'],
    );
    if (result == null) return;
    await _applyImport(await result.xFile.readAsString());
  }

  Future<void> _importFromClipboard() async {
    final text = (await Clipboard.getData('text/plain'))?.text;
    if (text?.isNotEmpty != true) {
      SmartDialog.showToast('剪贴板无数据');
      return;
    }
    await _applyImport(text!);
  }

  Future<void> _applyImport(String text) async {
    final List<HistoryItemModel> items;
    try {
      items = (jsonDecode(text) as List<dynamic>)
          .map((e) => HistoryItemModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      SmartDialog.showToast('解析失败：$e');
      return;
    }
    if (items.isEmpty) {
      SmartDialog.showToast('文件中没有有效记录');
      return;
    }
    final merge = await showDialog<bool>(
      context: context,
      builder: (context) => const SelectDialog<bool>(
        title: '导入方式',
        value: true, // 默认合并
        values: [
          (true, '合并（保留现有记录，重复项以较新数据为准）'),
          (false, '替换（清空现有记录后导入）'),
        ],
      ),
    );
    if (merge == null) return;
    final count = await LocalHistory.import(items, merge: merge);
    await _controller.refreshAndWait();
    SmartDialog.showToast('导入成功，共 $count 条');
  }

  Future<void> _configureSync() async {
    final current = Pref.localHistorySyncDirectory;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('本地历史自动同步'),
        content: Text(current.isEmpty ? '选择共享文件夹' : '当前文件夹：$current'),
        actions: [
          if (current.isNotEmpty)
            TextButton(
              onPressed: () => Get.back(result: ''),
              child: const Text('禁用'),
            ),
          TextButton(
            onPressed: () => Get.back(result: 'select'),
            child: const Text('选择文件夹'),
          ),
          TextButton(onPressed: Get.back, child: const Text('取消')),
        ],
      ),
    );
    if (choice == null) return;
    try {
      final root = choice.isEmpty
          ? ''
          : await FilePicker.getDirectoryPath(
              initialDirectory: current.isEmpty ? null : current,
            );
      if (root == null) return;
      await LocalHistorySync.configure(root);
      await _controller.refreshAndWait();
    } catch (error) {
      SmartDialog.showToast('同步配置失败：$error');
    }
  }

  Future<void> _deleteItem(HistoryItemModel item) async {
    await LocalHistory.remove(item);
    await _controller.refreshAndWait();
    SmartDialog.showToast('已删除');
  }

  void _clearAll() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确定清空本地观看历史吗？'),
        actions: [
          TextButton(
            onPressed: Get.back,
            child: Text(
              '取消',
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Get.back();
              await LocalHistory.clear();
              await _controller.refreshAndWait();
              SmartDialog.showToast('已清空');
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
