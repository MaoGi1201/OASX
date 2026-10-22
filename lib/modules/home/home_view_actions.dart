part of 'index.dart';

extension _HomeViewActions on _HomeViewState {
  Widget _buildDashboardBody() {
    return Obx(() {
      if (controller.startupLoadingMessage.value.isNotEmpty) {
        return const SizedBox.expand();
      }
      if (controller.isStartupConnectionFailed.value &&
          scriptService.scriptOrderList.isEmpty) {
        return _buildConnectionFailedView();
      }
      return DashboardHome(
        controller: controller,
        scriptService: scriptService,
        onAddScriptTap: _onAddScriptCardTap,
      );
    });
  }

  Widget _buildConnectionFailedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Obx(() {
              if (controller.isStartupChecking.value) {
                return const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(strokeWidth: 2.6),
                );
              }
              return Icon(
                Icons.cloud_off_rounded,
                size: 34,
                color: Theme.of(context).colorScheme.outline,
              );
            }),
            const SizedBox(height: 12),
            Text(
              I18n.homeConnectionRetryHint.tr,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              '当前地址：${ApiClient().address}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Get.toNamed('/settings'),
                  icon: const Icon(Icons.settings_rounded, size: 18),
                  label: const Text('打开设置'),
                ),
                FilledButton.icon(
                  onPressed: () => controller.retryStartupConnection(),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重试'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onAddScriptCardTap() async {
    if (_isAddingScript) {
      return;
    }
    final createdConfig = await showAddConfigDialog(
      context,
      onSubmitting: () => _setAddingScript(true),
      onSubmitDone: () {
        _setAddingScript(false);
        controller.syncWorkspaceState();
      },
    );
    if (createdConfig == null || createdConfig.isEmpty) {
      return;
    }
    controller.setActiveScript(createdConfig);
  }
}
