part of 'dashboard_home.dart';

// ---------------------------------------------------------------------------
// Header: account tabs, all-configs dialog and top-bar actions.
// ---------------------------------------------------------------------------

class _AllConfigsDialog extends StatefulWidget {
  const _AllConfigsDialog({
    required this.controller,
    required this.scriptService,
    this.startInLinkMode = false,
  });

  final HomeDashboardController controller;
  final ScriptService scriptService;

  /// 打开时是否直接进入连接模式（配置卡片的链条按钮走这条路）。
  final bool startInLinkMode;

  @override
  State<_AllConfigsDialog> createState() => _AllConfigsDialogState();
}

class _AllConfigsDialogState extends State<_AllConfigsDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  /// 「仅看异常」筛选开关，只在存在卡死配置时可用。
  bool _onlyWarning = false;
  /// 已有生效的连接组时，进来就直接展示连接状态（勾选框可见）。
  late bool _linkMode = widget.startInLinkMode ||
      widget.controller.validLinkedScripts.length >= 2;

  @override
  void initState() {
    super.initState();
    if (_linkMode) {
      _ensureLinkEnabled();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// `setScriptLinked` 在连接模式关闭时会直接 return，改列表前必须先开启。
  void _ensureLinkEnabled() {
    if (!widget.controller.isLinkModeEnabled.value) {
      widget.controller.toggleLinkMode();
    }
  }

  /// 点链条按钮：进入连接模式 / 断开全部连接。
  void _toggleLinkMode() {
    if (_linkMode) {
      // 断开：关闭连接模式会一并清空勾选，勾选框随之隐藏。
      if (widget.controller.isLinkModeEnabled.value) {
        widget.controller.toggleLinkMode();
      }
      setState(() => _linkMode = false);
      return;
    }
    _ensureLinkEnabled();
    setState(() => _linkMode = true);
  }

  /// 启停某个配置：走和顶栏标签相同的级联逻辑（连接生效时一起启停）。
  Future<void> _togglePower(String name) async {
    final model = widget.scriptService.findScriptModel(name);
    if (model == null) {
      return;
    }
    await widget.controller.applyLinkedPowerToggle(
      sourceScript: name,
      enable: model.state.value != ScriptState.running,
    );
  }

  void _toggleLinked(String name, bool selected) {
    if (selected) {
      _ensureLinkEnabled();
    }
    widget.controller.setScriptLinked(name, selected);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final names = widget.scriptService.scriptOrderList;
      final activeName = widget.controller.activeScriptName.value.trim();
      final linked = widget.controller.linkedScriptList.toSet();
      final warningNames = <String>[
        for (final name in names)
          if (_stateOf(name) == ScriptState.warning) name,
      ];
      // 异常全部恢复后自动退出「仅看异常」，否则列表会突然变成空态。
      final onlyWarning = _onlyWarning && warningNames.isNotEmpty;
      final filtered = filterAllConfigs(
        names,
        query: _query,
        onlyWarning: onlyWarning,
        warnings: warningNames.toSet(),
      );
      var runningCount = 0;
      for (final name in names) {
        if (_stateOf(name) == ScriptState.running) {
          runningCount++;
        }
      }

      // 窗口较小时按可用空间收缩，避免弹窗溢出。
      final size = MediaQuery.sizeOf(context);
      final panelWidth = (size.width - 96).clamp(260.0, 520.0);
      final panelHeight = (size.height - 240).clamp(200.0, 380.0);

      return AlertDialog(
        title: Row(
          children: [
            const Text('全部配置'),
            const SizedBox(width: 8),
            Text(
              '共 ${names.length} 个 · 运行中 $runningCount',
              style: TextStyle(fontSize: 12, color: AppColors.text3),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _toggleLinkMode,
              icon: Icon(
                _linkMode ? Icons.link_off_rounded : Icons.link_rounded,
                size: 15,
                color: _linkMode ? AppColors.yellow : AppColors.teal,
              ),
              label: Text(
                _linkMode ? '断开连接' : '连接',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: _linkMode ? AppColors.yellow : AppColors.teal,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: panelWidth,
          height: panelHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  hintText: '搜索配置名…',
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded, size: 18),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              if (warningNames.isNotEmpty) ...[
                const SizedBox(height: AppGap.m),
                _WarningBannerRow(
                  names: warningNames,
                  onlyWarning: onlyWarning,
                  onToggleFilter: () =>
                      setState(() => _onlyWarning = !_onlyWarning),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                _linkMode
                    ? '勾选即连接：勾上的配置会一起启停、一起执行任务；点「断开连接」可解除全部。'
                    : '点右上角「连接」后，每个配置前会出现勾选框。',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: AppColors.text3,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          '没有匹配的配置',
                          style: TextStyle(fontSize: 12.5, color: AppColors.text3),
                        ),
                      )
                    : GridView.builder(
                        padding: EdgeInsets.zero,
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 168,
                          mainAxisExtent: 42,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final name = filtered[index];
                          final isLinked = linked.contains(name);
                          return Obx(
                            () => _AllConfigsTile(
                              name: name,
                              linkMode: _linkMode,
                              active: name == activeName,
                              selected: isLinked,
                              state: _stateOf(name),
                              linked: isLinked,
                              onSwitch: () {
                                widget.controller.setActiveScript(name);
                                Navigator.of(context).pop();
                              },
                              onToggleLink: () =>
                                  _toggleLinked(name, !isLinked),
                              onTogglePower: () => _togglePower(name),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }

  ScriptState _stateOf(String name) {
    return widget.scriptService.findScriptModel(name)?.state.value ??
        ScriptState.inactive;
  }
}

/// 弹窗顶部那条黄色提示：有几个配置卡死、分别是哪些，右侧是「仅看异常」开关。
///
/// 只在存在卡死配置时渲染，平时完全不占高度，不会把下方网格挤少一行。
class _WarningBannerRow extends StatelessWidget {
  const _WarningBannerRow({
    required this.names,
    required this.onlyWarning,
    required this.onToggleFilter,
  });

  final List<String> names;
  final bool onlyWarning;
  final VoidCallback onToggleFilter;

  @override
  Widget build(BuildContext context) {
    final yellow = AppColors.yellow;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: yellow.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: yellow.withValues(alpha: 0.38)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 15, color: yellow),
          const SizedBox(width: AppGap.s),
          Expanded(
            child: Text(
              '${names.length} ${I18n.homeAllConfigsWarningBanner.tr}'
              ' · ${names.join(' / ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: AppColors.text2,
              ),
            ),
          ),
          const SizedBox(width: AppGap.s),
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: onToggleFilter,
            child: Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: onlyWarning
                    ? yellow.withValues(alpha: 0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: onlyWarning
                      ? yellow.withValues(alpha: 0.7)
                      : AppColors.border,
                ),
              ),
              child: Text(
                '${I18n.homeAllConfigsOnlyWarning.tr} ${names.length}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: onlyWarning ? yellow : AppColors.text2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 网格里的单个配置项。
///
/// - 浏览模式：整格点击 = 切换配置；右侧小勾表示已连接
/// - 连接模式：左侧勾选框 = 加入/移出连接，右侧名字 = 切换配置
class _AllConfigsTile extends StatelessWidget {
  const _AllConfigsTile({
    required this.name,
    required this.linkMode,
    required this.active,
    required this.selected,
    required this.state,
    required this.linked,
    required this.onSwitch,
    required this.onToggleLink,
    required this.onTogglePower,
  });

  final String name;
  final bool linkMode;
  final bool active;
  final bool selected;
  final ScriptState state;
  final bool linked;

  /// 切换到这个配置（会关闭面板）。
  final VoidCallback onSwitch;

  /// 加入 / 移出连接组。
  final VoidCallback onToggleLink;

  /// 启动 / 停止这个配置。
  final VoidCallback onTogglePower;

  /// 运行中=绿，卡死/异常=黄，更新中=蓝，未启动=灰（与标签条一致）。
  Color get _accent {
    return switch (state) {
      ScriptState.running => AppColors.green,
      ScriptState.warning => AppColors.yellow,
      ScriptState.updating => AppColors.blue,
      ScriptState.inactive => AppColors.text3,
    };
  }

  @override
  Widget build(BuildContext context) {
    final highlight = linkMode ? selected : active;
    final background = BoxDecoration(
      color: highlight ? AppColors.tealDim : AppColors.surface2,
      borderRadius: BorderRadius.circular(AppRadius.button),
      border: Border.all(
        color: highlight
            ? AppColors.teal.withValues(alpha: 0.55)
            : AppColors.border,
      ),
    );

    final running = state == ScriptState.running;
    final warning = state == ScriptState.warning;
    // 和顶栏配置标签上的启停按钮保持同一套样式与图标。
    final powerButton = Tooltip(
      message: running
          ? I18n.homeConfigStopTip.tr
          : (warning
              ? I18n.homeConfigRestartTip.tr
              : I18n.homeConfigStartTip.tr),
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.button),
        onTap: _dismissingTooltipTap(onTogglePower),
        child: Container(
          // 26 在标签里偏小，稍微放大一点，配合左右留白避免误触「切换配置」。
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: running || warning
                ? _accent.withValues(alpha: 0.14)
                : AppColors.surface3,
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(
              color: running || warning
                  ? _accent.withValues(alpha: 0.6)
                  : AppColors.border,
            ),
          ),
          child: Icon(
            Icons.power_settings_new_rounded,
            size: 14,
            color: running || warning ? _accent : AppColors.text3,
          ),
        ),
      ),
    );

    final nameText = Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12.5,
        color: highlight ? AppColors.teal : AppColors.text,
        fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
      ),
    );

    if (!linkMode) {
      return InkWell(
        borderRadius: BorderRadius.circular(AppRadius.button),
        onTap: onSwitch,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: background,
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration:
                    BoxDecoration(color: _accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(child: nameText),
              if (linked) ...[
                Icon(Icons.link_rounded, size: 12, color: AppColors.teal),
                const SizedBox(width: 2),
              ],
              // 电源键和整格「切换配置」之间留 4px 死区。
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: powerButton,
              ),
            ],
          ),
        ),
      );
    }

    // 连接模式：勾选框 + 名字 = 打勾/取消打勾；名字后面的空白 = 切换到该配置。
    return Container(
      decoration: background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 面板最窄时每个格子只有 ~126px，名字区必须按实际宽度让位，
          // 否则勾选框 + 名字 + 电源键直接把 Row 撑爆。
          // 勾选区末尾留 10px 死区、电源键左侧留 5px，都是为了把「勾选 /
          // 切换 / 启停」三种意图在物理上分开——原来三者零间隙，点偏就
          // 切走配置且面板会立刻关闭。
          const fixedWidth = 32 + 10 + 5 + 28 + 4;
          const minSwitchWidth = 12.0;
          final nameMaxWidth = (constraints.maxWidth -
                  fixedWidth -
                  minSwitchWidth)
              .clamp(24.0, 88.0)
              .toDouble();
          return Row(
            children: [
              Tooltip(
                message: selected ? '取消连接' : '加入连接',
                waitDuration: const Duration(milliseconds: 350),
                child: InkWell(
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(8),
                  ),
                  onTap: _dismissingTooltipTap(onToggleLink),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 32,
                        height: 42,
                        child: Center(
                          child: Icon(
                            selected
                                ? Icons.check_box_rounded
                                : Icons.check_box_outline_blank_rounded,
                            size: 16,
                            color: selected ? AppColors.teal : AppColors.text3,
                          ),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: nameMaxWidth),
                        child: nameText,
                      ),
                      // 死区：勾选区覆盖到这里为止，再往右才是「切换」。
                      const SizedBox(width: AppGap.m),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Tooltip(
                  message: '切换到该配置',
                  waitDuration: const Duration(milliseconds: 350),
                  child: InkWell(
                    onTap: _dismissingTooltipTap(onSwitch),
                    child: const SizedBox(height: 42),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 5, right: 4),
                child: powerButton,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header: account tabs + device/time status
// ---------------------------------------------------------------------------
class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.controller,
    required this.scriptService,
    required this.script,
    required this.now,
    required this.onAddScriptTap,
    required this.onOpenScriptConfig,
    required this.onOpenGlobalConfig,
  });

  final HomeDashboardController controller;
  final ScriptService scriptService;
  final ScriptModel? script;
  final DateTime now;
  final VoidCallback onAddScriptTap;
  final Future<void> Function()? onOpenScriptConfig;
  final VoidCallback? onOpenGlobalConfig;

  @override
  Widget build(BuildContext context) {
    final names = scriptService.scriptOrderList;
    final activeName = controller.activeScriptName.value.trim();
    final compact = MediaQuery.of(context).size.width < 700;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final name in names)
                    Padding(
                      key: ValueKey<String>('account-tab-$name'),
                      // 只留右边距：标签 34px 与右侧「全部 N」按钮同高，
                      // 交给 Row 的居中让两者基线齐平（之前多一个 top: 6，
                      // 会让标签整体下沉 3px，窄屏下和「全部」按钮看着错位）。
                      padding: const EdgeInsets.only(right: 8),
                      // 每个标签独立订阅自己配置的 state，否则点击非当前
                      // 配置的启停开关时，那个标签的启停状态不会刷新。
                      child: Obx(
                        () => _AccountTab(
                          name: name,
                          active: name == activeName,
                          state: _stateOf(name),
                          linked: controller.hasActiveLinkFor(name),
                          onTap: () => controller.setActiveScript(name),
                          onTogglePower: () => _togglePower(name),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          // 配置多时用它一览全部（带搜索与状态点），手机界面同样保留。
          //
          // 必须包一层 Obx：`_AllConfigsButton` 拿到的是普通 List，某个配置
          // 从 running 翻成 warning 时只有在这里读 Rx 才会触发重建。
          Obx(
            () => AllConfigsButton(
              count: names.length,
              warningNames: <String>[
                for (final name in names)
                  if (_stateOf(name) == ScriptState.warning) name,
              ],
              onTap: () => showAllConfigsDialog(
                context,
                controller: controller,
                scriptService: scriptService,
              ),
            ),
          ),
          // 手机界面只保留配置标签，+/− 及其右侧的所有按钮都隐藏。
          if (!compact) ...[
          const SizedBox(width: 6),
          _SquareButton(
            tooltip: '新增脚本',
            onTap: onAddScriptTap,
            child: Icon(
              Icons.add_rounded,
              size: 16,
              color: AppColors.text2,
            ),
          ),
          const SizedBox(width: 6),
          _SquareButton(
            tooltip: I18n.delete.tr,
            onTap: activeName.isEmpty ? null : () => _deleteActive(activeName),
            child: Icon(
              Icons.remove_rounded,
              size: 16,
              color: AppColors.text2,
            ),
          ),
          const SizedBox(width: 8),
          _SquareButton(
            tooltip: AppColors.isDark ? '切换到白天' : '切换到黑夜',
            onTap: () {
              if (Get.isRegistered<ThemeService>()) {
                Get.find<ThemeService>().switchTheme();
              }
            },
            child: Icon(
              AppColors.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              size: 15,
              color: AppColors.text2,
            ),
          ),
          const SizedBox(width: 8),
          _SquareButton(
            // 这个分支只面向模拟器：固定图标与文案，不再区分桌面版。
            tooltip: '模拟器配置',
            onTap: onOpenScriptConfig,
            child: Icon(
              Icons.phone_android_rounded,
              size: 15,
              color: AppColors.text2,
            ),
          ),
          const SizedBox(width: 8),
          _SquareButton(
            tooltip: '全局配置',
            onTap: onOpenGlobalConfig,
            child: Icon(
              Icons.public_rounded,
              size: 15,
              color: AppColors.text2,
            ),
          ),
          const SizedBox(width: 8),
          // 只有连接异常时才出现；正常运行时不再占位。
          _HeaderStatusChip(
            controller: controller,
            scriptService: scriptService,
          ),
          Text(
            formatHhMm(now),
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.text2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          ],
        ],
      ),
    );
  }

  ScriptState _stateOf(String name) {
    final model = scriptService.findScriptModel(name);
    return model?.state.value ?? ScriptState.inactive;
  }

  /// Starts or stops one config directly from its tab.
  Future<void> _togglePower(String name) async {
    final model = scriptService.findScriptModel(name);
    if (model == null) {
      return;
    }
    await controller.applyLinkedPowerToggle(
      sourceScript: name,
      enable: model.state.value != ScriptState.running,
    );
  }

  Future<void> _deleteActive(String name) async {
    await ConfigActions.showDeleteDialog(
      scriptService: scriptService,
      name: name,
    );
  }
}

/// 连接异常时的提示胶囊：正常连接后完全隐藏。
class _HeaderStatusChip extends StatelessWidget {
  const _HeaderStatusChip({
    required this.controller,
    required this.scriptService,
  });

  final HomeDashboardController controller;
  final ScriptService scriptService;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final checking = controller.isStartupChecking.value;
      final connected = !checking &&
          !controller.isStartupConnectionFailed.value &&
          scriptService.scriptOrderList.isNotEmpty;
      if (connected) {
        return const SizedBox.shrink();
      }
      final color = checking ? AppColors.yellow : AppColors.red;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Tooltip(
          message: '点击重试连接',
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.button),
            onTap: checking
                ? null
                : _dismissingTooltipTap(
                    () => controller.retryStartupConnection(),
                  ),
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(AppRadius.button),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    checking ? '连接中…' : '未连接 · 点击重试',
                    style: TextStyle(fontSize: 12, color: AppColors.text2),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Compact page selector for phone layouts (one page at a time).
class _MobilePageTabs extends StatelessWidget {
  const _MobilePageTabs({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    const labels = <String>['任务', '总览', '日志', '统计'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: i == labels.length - 1 ? 0 : 8,
              ),
              child: _MobileTabChip(
                label: labels[i],
                selected: i == index,
                onTap: () => onSelect(i),
              ),
            ),
          ),
      ],
    );
  }
}

class _MobileTabChip extends StatelessWidget {
  const _MobileTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.button),
      onTap: onTap,
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.tealDim : AppColors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.button),
          border: Border.all(
            color: selected ? AppColors.teal.withValues(alpha: 0.45) : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.teal : AppColors.text2,
          ),
        ),
      ),
    );
  }
}

class _AccountTab extends StatelessWidget {
  const _AccountTab({
    required this.name,
    required this.active,
    required this.state,
    required this.onTap,
    this.linked = false,
    this.onTogglePower,
  });

  final String name;
  final bool active;
  final ScriptState state;
  final VoidCallback onTap;

  /// 该配置当前被连接器勾选（参与同步）。
  final bool linked;

  final VoidCallback? onTogglePower;

  bool get _running => state == ScriptState.running;
  bool get _warning => state == ScriptState.warning;

  /// 运行中=绿，卡死/异常=黄，更新中=蓝，未启动=灰（与原版一致）。
  Color get _accent {
    return switch (state) {
      ScriptState.running => AppColors.green,
      ScriptState.warning => AppColors.yellow,
      ScriptState.updating => AppColors.blue,
      ScriptState.inactive => AppColors.text3,
    };
  }

  String get _powerTip {
    if (_running) {
      return I18n.homeConfigStopTip.tr;
    }
    if (_warning) {
      return I18n.homeConfigRestartTip.tr;
    }
    return I18n.homeConfigStartTip.tr;
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    // 裸 GestureDetector：不需要水波纹，标签的选中/运行状态本身就是反馈。
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          // 连接中的配置即使没被选中，也给一层淡青底 + 青色描边。
          color: active
              ? AppColors.tealDim
              : (linked
                  ? AppColors.tealDim.withValues(alpha: 0.55)
                  : AppColors.surface2),
          borderRadius: BorderRadius.circular(AppRadius.menu),
          border: Border.all(
            color: active
                ? AppColors.teal.withValues(alpha: 0.55)
                : (linked
                    ? AppColors.teal.withValues(alpha: 0.45)
                    : AppColors.border),
            width: active || linked ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active || linked ? FontWeight.w600 : FontWeight.w400,
                color: active || linked ? AppColors.teal : AppColors.text2,
              ),
            ),
            if (linked) ...[
              const SizedBox(width: 4),
              Icon(Icons.link_rounded, size: 12, color: AppColors.teal),
            ],
            if (onTogglePower != null) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: _powerTip,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  onTap: _dismissingTooltipTap(onTogglePower),
                  child: Container(
                    width: AppSize.iconButton,
                    height: AppSize.iconButton,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _running || _warning
                          ? accent.withValues(alpha: 0.14)
                          : AppColors.surface3,
                      borderRadius: BorderRadius.circular(AppRadius.button),
                      border: Border.all(
                        color: _running || _warning
                            ? accent.withValues(alpha: 0.6)
                            : AppColors.border,
                      ),
                    ),
                    child: Icon(
                      Icons.power_settings_new_rounded,
                      size: 14,
                      color: _running || _warning ? accent : AppColors.text3,
                    ),
                  ),
                ),
              ),
            ],
          ],
          ),
        ),
      ),
    );
  }
}

/// 点击后立刻收起悬停提示。
///
/// Material 的 Tooltip 在鼠标停留期间会一直显示，点击后仍然挂着会挡视线；
/// 这里在触发点击前先收掉。提示本身不会失效——鼠标移开再移回来仍会重新显示。
VoidCallback? _dismissingTooltipTap(VoidCallback? onTap) {
  if (onTap == null) {
    return null;
  }
  return () {
    Tooltip.dismissAllToolTips();
    onTap();
  };
}

/// 顶栏「全部 N」按钮：点开配置网格面板。
///
/// [warningNames] 非空时按钮转成警示态（描边与文字转黄），并在四格图标右上角
/// 挂一个数量角标，让「有配置卡死」这件事不用逐个切标签就能看见。
///
/// 角标贴在**图标**上而不是按钮右上角：它是「这个按钮里有一批配置出问题」的
/// 标记，压在图标上才读得出归属；挂在按钮最右侧时视线要横穿整行文字才落到
/// 角标上，而且很容易和右边相邻的方形按钮混成一组。
class AllConfigsButton extends StatelessWidget {
  const AllConfigsButton({
    super.key,
    required this.count,
    required this.warningNames,
    required this.onTap,
  });

  final int count;
  final List<String> warningNames;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final warned = warningNames.isNotEmpty;
    final fg = warned ? AppColors.yellow : AppColors.text2;
    return Tooltip(
      // 只报数量，不列名字：异常配置可能十几个，逐一罗列会让浮层长得没边。
      message: warned
          ? '${warningNames.length} ${I18n.homeAllConfigsWarningTip.tr}'
          : '全部配置',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.button),
        onTap: _dismissingTooltipTap(onTap),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.surface3,
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(
              color: warned
                  ? AppColors.yellow.withValues(alpha: 0.55)
                  : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 角标紧贴图标右侧（只压住 1px），四格图标保持完整可辨；
              // 间距跟着让开，两位数（"12"）也不会碰到「全」字。
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(Icons.grid_view_rounded, size: 13, color: fg),
                  if (warned)
                    Positioned(
                      top: -5,
                      left: 12,
                      child: AppWarningBadge(count: warningNames.length),
                    ),
                ],
              ),
              SizedBox(width: warned ? 20 : AppGap.xs),
              Text(
                '全部 $count',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.child,
    required this.tooltip,
    this.onTap,
  });

  final Widget child;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.button),
        onTap: _dismissingTooltipTap(onTap),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.surface3,
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(color: AppColors.border),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}
