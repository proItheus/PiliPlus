import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_sliver_safe_area.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/dynamics/result.dart';
import 'package:PiliPlus/pages/dynamics/widgets/dynamic_panel.dart';
import 'package:PiliPlus/pages/local_subscription_feed/controller.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/waterfall.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:waterfall_flow/waterfall_flow.dart'
    hide SliverWaterfallFlowDelegateWithMaxCrossAxisExtent;

class LocalSubscriptionFeedPage extends StatefulWidget {
  const LocalSubscriptionFeedPage({super.key});

  @override
  State<LocalSubscriptionFeedPage> createState() =>
      _LocalSubscriptionFeedPageState();
}

class _LocalSubscriptionFeedPageState extends State<LocalSubscriptionFeedPage>
    with DynMixin {
  late final LocalSubscriptionFeedController _controller;

  @override
  void initState() {
    super.initState();
    _controller = Get.put(LocalSubscriptionFeedController());
  }

  @override
  void dispose() {
    Get.delete<LocalSubscriptionFeedController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SimpleScaffold(
      appBar: AppBar(
        title: const Text('本地订阅动态'),
        actions: [
          IconButton(
            tooltip: '管理本地订阅',
            onPressed: _openManagement,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: refreshIndicator(
        onRefresh: _controller.onRefresh,
        child: CustomScrollView(
          controller: _controller.scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            ViewSliverSafeArea(
              sliver: Obx(
                () => _buildContent(_controller.loadingState.value),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(LoadingState<List<DynamicItemModel>?> state) {
    return switch (state) {
      Loading() => dynSkeleton,
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: _controller.onReload,
      ),
      Success(:final response) => _buildSuccess(response),
    };
  }

  Widget _buildSuccess(List<DynamicItemModel>? response) {
    if (_controller.isLocalListEmpty.value) {
      return _buildMessage(
        title: '还没有本地订阅',
        description: '添加常用 UP 主后，这里会聚合他们的最新动态。',
        actionText: '管理本地订阅',
        onAction: _openManagement,
      );
    }
    if (response == null || response.isEmpty) {
      final emptyState = _buildMessage(
        title: '暂无可用动态',
        description: '已保存的 UP 主暂时没有可显示的动态。',
        actionText: '刷新',
        onAction: _controller.onReload,
        secondaryActionText: '管理本地订阅',
        onSecondaryAction: _openManagement,
      );
      return _controller.failedSources.isEmpty
          ? emptyState
          : SliverMainAxisGroup(
              slivers: [
                _buildPartialWarning(),
                emptyState,
              ],
            );
    }

    final slivers = <Widget>[];
    if (_controller.failedSources.isNotEmpty) {
      slivers.add(_buildPartialWarning());
    }
    final content = GlobalData().dynamicsWaterfallFlow
        ? SliverWaterfallFlow(
            gridDelegate: dynGridDelegate,
            delegate: SliverChildBuilderDelegate(
              (_, index) => _itemBuilder(response, index),
              childCount: response.length,
            ),
          )
        : SliverList.builder(
            itemBuilder: (_, index) => _itemBuilder(response, index),
            itemCount: response.length,
          );
    slivers.add(buildPage(content));
    return SliverMainAxisGroup(slivers: slivers);
  }

  Widget _buildPartialWarning() {
    final colorScheme = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Material(
        color: colorScheme.errorContainer,
        child: ListTile(
          dense: true,
          leading: Icon(
            Icons.warning_amber_rounded,
            color: colorScheme.onErrorContainer,
          ),
          title: Text(
            '部分本地订阅加载失败',
            style: TextStyle(color: colorScheme.onErrorContainer),
          ),
          trailing: TextButton(
            onPressed: _controller.onReload,
            child: const Text('重试'),
          ),
        ),
      ),
    );
  }

  Widget _buildMessage({
    required String title,
    required String description,
    required String actionText,
    required VoidCallback onAction,
    String? secondaryActionText,
    VoidCallback? onSecondaryAction,
  }) {
    final theme = Theme.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(description, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionText),
              ),
              if (secondaryActionText != null && onSecondaryAction != null)
                TextButton(
                  onPressed: onSecondaryAction,
                  child: Text(secondaryActionText),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _itemBuilder(List<DynamicItemModel> list, int index) {
    if (index == list.length - 1) {
      _controller.onLoadMore();
    }
    return DynamicPanel(item: list[index]);
  }

  Future<void> _openManagement() async {
    await Get.toNamed('/localSubscription');
    if (mounted) {
      await _controller.onRefresh();
    }
  }
}
