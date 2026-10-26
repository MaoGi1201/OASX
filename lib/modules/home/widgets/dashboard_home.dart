import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/config/app_colors.dart';
import 'package:oasx/modules/home/config_actions.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';
import 'package:oasx/modules/home/models/config_model.dart';
import 'package:oasx/modules/home/models/dashboard_task_helpers.dart';
import 'package:oasx/modules/home/models/script_statistics_models.dart';
import 'package:oasx/modules/home/widgets/log_center_panel.dart';
import 'package:oasx/modules/home/widgets/statistics_panel.dart';
import 'package:oasx/modules/home/widgets/task_config_dialog.dart';
import 'package:oasx/service/script_service.dart';
import 'package:oasx/service/theme_service.dart';
import 'package:oasx/translation/i18n_content.dart';
import 'package:oasx/utils/app_toast.dart';

// ---------------------------------------------------------------------------
// Palette: light (day) and dark (night) variants selected by the app theme.
// ---------------------------------------------------------------------------
/// Opens the connector dialog: pick other configs to mirror this one's
/// start/stop and task actions.
Future<void> showConnectorDialog(
  BuildContext context, {
  required HomeDashboardController controller,
  required String sourceScript,
}) {
  // 首次打开时默认把当前配置勾上（仍可取消），方便直接再勾别的配置。
  if (controller.validLinkedScripts.isEmpty) {
    if (!controller.isLinkModeEnabled.value) {
      controller.toggleLinkMode();
    }
    controller.setScriptLinked(sourceScript, true);
  }
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _ConnectorDialog(
      controller: controller,
      sourceScript: sourceScript,
    ),
  );
}

class _ConnectorDialog extends StatelessWidget {
  const _ConnectorDialog({
    required this.controller,
    required this.sourceScript,
  });

  final HomeDashboardController controller;
  final String sourceScript;

  void _toggle(String name, bool selected) {
    if (selected && !controller.isLinkModeEnabled.value) {
      controller.toggleLinkMode();
    }
    // 取消勾选只是把这一项移出列表：不关闭连接模式，也不关闭弹窗。
    controller.setScriptLinked(name, selected);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final candidates = controller.linkCandidatesFor(sourceScript);
      final linked = controller.linkedScriptList.toSet();
      // 当前配置永远排在第一行、默认勾选且不可取消。
      final allNames = <String>[sourceScript, ...candidates];
      return AlertDialog(
        title: const Text('连接器'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '勾选后，这些配置会跟随「$sourceScript」一起启停、一起执行任务。',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: AppColors.text2,
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: allNames.length,
                  itemBuilder: (context, index) {
                    final name = allNames[index];
                    final isSource = name == sourceScript;
                    final selected = linked.contains(name);
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _toggle(name, !selected),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Checkbox(
                              value: selected,
                              onChanged: (value) =>
                                  _toggle(name, value ?? false),
                            ),
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: selected
                                      ? AppColors.teal
                                      : AppColors.text,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                            if (isSource)
                              Text(
                                '当前',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.text3,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (candidates.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        for (final name in allNames) {
                          _toggle(name, true);
                        }
                      },
                      child: const Text('全选'),
                    ),
                    TextButton(
                      onPressed: () {
                        for (final name in allNames) {
                          _toggle(name, false);
                        }
                      },
                      child: const Text('清空'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (controller.validLinkedScripts.isEmpty &&
                  controller.isLinkModeEnabled.value) {
                controller.toggleLinkMode();
              }
              Navigator.of(context).pop();
            },
            child: const Text('完成'),
          ),
        ],
      );
    });
  }
}

/// Full-width dashboard home: account tabs on top, then a three-column
/// tasks / logs / assets layout.
class DashboardHome extends StatefulWidget {
  const DashboardHome({
    super.key,
    required this.controller,
    required this.scriptService,
    required this.onAddScriptTap,
  });

  final HomeDashboardController controller;
  final ScriptService scriptService;
  final VoidCallback onAddScriptTap;

  @override
  State<DashboardHome> createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<DashboardHome> {
  late DateTime _now;
  Timer? _clockTimer;
  Worker? _scriptWorker;
  int _selectedDayIndex = 0;
  int _mobilePageIndex = 0;
  bool _isDesktopMode = false;

  /// 每个配置的运行环境（桌面端 / 模拟器），避免每次切标签都发一次请求。
  final Map<String, bool> _deviceModeCache = <String, bool>{};

  HomeDashboardController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
    _scriptWorker = ever<String>(
      _controller.activeScriptName,
      (name) => _loadDeviceMode(name.trim()),
    );
    final initialScript = _controller.activeScriptName.value.trim();
    _loadDeviceMode(initialScript);
  }

  @override
  void dispose() {
    _scriptWorker?.dispose();
    _clockTimer?.cancel();
    super.dispose();
  }

  /// Reads `device.emulator_control` from the Script config to decide whether
  /// the current config runs on an emulator or the desktop client.
  Future<void> _loadDeviceMode(String scriptName, {bool force = false}) async {
    if (scriptName.isEmpty) {
      if (mounted) {
        setState(() => _isDesktopMode = false);
      }
      return;
    }
    final cached = _deviceModeCache[scriptName];
    if (!force && cached != null) {
      if (mounted && _isDesktopMode != cached) {
        setState(() => _isDesktopMode = cached);
      }
      return;
    }
    try {
      final args = await ApiClient().getScriptTask(scriptName, 'Script');
      final device = args['device'];
      String? control;
      if (device is List) {
        for (final item in device) {
          if (item is Map && item['name'] == 'emulator_control') {
            control = item['value']?.toString();
            break;
          }
        }
      }
      final isDesktop = control == 'desktop';
      _deviceModeCache[scriptName] = isDesktop;
      if (!mounted) {
        return;
      }
      setState(() => _isDesktopMode = isDesktop);
    } catch (_) {
      // Keep the previous mode on failure.
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bg,
      child: Obx(() {
        final script = _controller.activeScriptModel;
        final scriptName = _controller.activeScriptName.value.trim();
        return LayoutBuilder(
          builder: (context, constraints) {
            // Phones / narrow windows show one page at a time.
            final compact = constraints.maxWidth < 900;
            return Column(
              children: [
                _DashboardHeader(
                  controller: _controller,
                  scriptService: widget.scriptService,
                  script: script,
                  isDesktopMode: _isDesktopMode,
                  now: _now,
                  onAddScriptTap: widget.onAddScriptTap,
                  onOpenScriptConfig: script == null
                      ? null
                      : () async {
                          await showTaskConfigDialog(
                            context,
                            controller: _controller,
                            scriptName: script.name,
                            taskName: 'Script',
                          );
                          await _loadDeviceMode(script.name, force: true);
                        },
                  onOpenGlobalConfig: script == null
                      ? null
                      : () => showTaskConfigDialog(
                            context,
                            controller: _controller,
                            scriptName: script.name,
                            taskName: 'GlobalGame',
                          ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    child: compact
                        ? _buildCompactBody(script, scriptName)
                        : _buildWideBody(script, scriptName),
                  ),
                ),
              ],
            );
          },
        );
      }),
    );
  }

  Widget _buildWideBody(ScriptModel? script, String scriptName) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左：当前配置卡片 + 总览
        Expanded(flex: 10, child: _buildOverviewColumn(script)),
        const SizedBox(width: 10),
        // 中：任务日期分布 + 任务列表
        Expanded(flex: 11, child: _buildTasksColumn(script)),
        const SizedBox(width: 10),
        // 右：日志 / 统计（点击切换）
        Expanded(flex: 10, child: _RightColumn(scriptName: scriptName)),
      ],
    );
  }

  Widget _buildCompactBody(ScriptModel? script, String scriptName) {
    return Column(
      children: [
        _MobilePageTabs(
          index: _mobilePageIndex,
          onSelect: (index) {
            setState(() => _mobilePageIndex = index);
            // Page 3 is the statistics tab; it only loads while visible.
            _controller.setStatsPanelVisible(index == 3);
          },
        ),
        const SizedBox(height: 10),
        Expanded(
          child: switch (_mobilePageIndex) {
            0 => _buildTasksColumn(script),
            1 => _buildOverviewColumn(script),
            2 => _LogsColumn(scriptName: scriptName),
            _ => const _StatisticsColumn(),
          },
        ),
      ],
    );
  }

  Widget _buildOverviewColumn(ScriptModel? script) {
    return _OverviewColumn(
      controller: _controller,
      scriptService: widget.scriptService,
      script: script,
    );
  }

  Widget _buildTasksColumn(ScriptModel? script) {
    return _TasksColumn(
      controller: _controller,
      script: script,
      selectedDayIndex: _selectedDayIndex,
      onSelectDay: (index) => setState(() => _selectedDayIndex = index),
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
    required this.isDesktopMode,
    required this.now,
    required this.onAddScriptTap,
    required this.onOpenScriptConfig,
    required this.onOpenGlobalConfig,
  });

  final HomeDashboardController controller;
  final ScriptService scriptService;
  final ScriptModel? script;
  final bool isDesktopMode;
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
                      padding: const EdgeInsets.only(right: 8, top: 6),
                      // 每个标签独立订阅自己配置的 state，否则点击非当前
                      // 配置的启停开关时，那个标签的启停状态不会刷新。
                      child: Obx(
                        () => _AccountTab(
                          name: name,
                          active: name == activeName,
                          state: _stateOf(name),
                          linked: controller.isLinkModeEnabled.value &&
                              controller.isScriptLinked(name),
                          onTap: () => controller.setActiveScript(name),
                          onTogglePower: () => _togglePower(name),
                        ),
                      ),
                    ),
                ],
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
            tooltip: isDesktopMode ? '桌面版配置' : '模拟器配置',
            onTap: onOpenScriptConfig,
            child: Icon(
              isDesktopMode
                  ? Icons.computer_rounded
                  : Icons.phone_android_rounded,
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
            borderRadius: BorderRadius.circular(8),
            onTap: checking ? null : () => controller.retryStartupConnection(),
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(8),
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
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.tealDim : AppColors.surface2,
          borderRadius: BorderRadius.circular(8),
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
      return '停止该配置';
    }
    if (_warning) {
      return '配置已卡死，点击重新启动';
    }
    return '启动该配置';
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
          borderRadius: BorderRadius.circular(10),
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
                  borderRadius: BorderRadius.circular(8),
                  onTap: onTogglePower,
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _running || _warning
                          ? accent.withValues(alpha: 0.14)
                          : AppColors.surface3,
                      borderRadius: BorderRadius.circular(8),
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
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.surface3,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.border),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Column 1: tasks
// ---------------------------------------------------------------------------
class _TasksColumn extends StatefulWidget {
  const _TasksColumn({
    required this.controller,
    required this.script,
    required this.selectedDayIndex,
    required this.onSelectDay,
  });

  final HomeDashboardController controller;
  final ScriptModel? script;
  final int selectedDayIndex;
  final ValueChanged<int> onSelectDay;

  @override
  State<_TasksColumn> createState() => _TasksColumnState();
}

class _TasksColumnState extends State<_TasksColumn> {
  /// 「立即执行 / 已延后」的绿色标记。键里带日期下标，
  /// 否则在「今天」点过的任务切到其它日期后会继续显示绿色。
  final Map<String, _QuickAction> _appliedActions =
      <String, _QuickAction>{};

  String _appliedKey(String taskName, {int? dayIndex}) =>
      '${dayIndex ?? widget.selectedDayIndex}|$taskName';

  Worker? _stateWorker;

  @override
  void initState() {
    super.initState();
    _bindScriptState();
  }

  @override
  void didUpdateWidget(covariant _TasksColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.script?.name != widget.script?.name) {
      _appliedActions.clear();
      _bindScriptState();
    }
  }

  @override
  void dispose() {
    _stateWorker?.dispose();
    super.dispose();
  }

  /// 配置停止（或异常）后，「立即执行 / 已延后」的标记就不再有意义，直接清空。
  void _bindScriptState() {
    _stateWorker?.dispose();
    final script = widget.script;
    if (script == null) {
      return;
    }
    _stateWorker = ever<ScriptState>(script.state, (state) {
      if (!mounted || _appliedActions.isEmpty) {
        return;
      }
      if (state != ScriptState.running) {
        setState(_appliedActions.clear);
      }
    });
  }

  /// Cancels one task in the current config's schedule.
  /// The task that is executing right now is protected: removing it would
  /// make the row vanish while the script keeps running it.
  Future<void> _toggleTaskEnabled(
    String scriptName,
    String taskName,
    bool enable,
  ) async {
    final model = widget.script;
    if (!enable && _isTaskCurrentlyRunning(model, taskName)) {
      showToast('无法取消', '$taskName 正在执行中');
      return;
    }
    final ok = await widget.controller.quickToggleTaskEnabledAcrossLink(
      scriptName: scriptName,
      taskName: taskName,
      enable: enable,
    );
    if (!ok) {
      showToast('操作失败', '$taskName 未能${enable ? '启用' : '取消'}');
      return;
    }
    Get.find<ScriptService>().wsService.send(scriptName, 'get_schedule');
    if (!enable) {
      showToast('已取消', taskName.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Subscribe to the model's reactive task lists so websocket schedule
    // updates rebuild the list (the parent Obx only reads the model object).
    return Obx(() {
      final script = widget.script;
      final allEntries = _collectTasks(script);
      final todayEntries = _filterEntriesForDay(
        allEntries,
        widget.selectedDayIndex,
      );
      final entries = todayEntries;
      return Column(
        children: [
          _DateDistributionCard(
            entries: allEntries,
            selectedIndex: widget.selectedDayIndex,
            onSelect: widget.onSelectDay,
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _Panel(
              child: Column(
                children: [
                  _PanelToolbar(
                    label: '任务',
                    countText: '共 ${entries.length} 项',
                  ),
                  Expanded(
                    child: entries.isEmpty
                        ? const _EmptyHint(label: '当日暂无任务')
                        : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                                itemCount: entries.length,
                                itemBuilder: (context, index) => _TaskRowTile(
                                  entry: entries[index],
                                  selected: index == 0,
                                  locked: _isTaskCurrentlyRunning(
                                    script,
                                    entries[index].name,
                                  ),
                                  onToggleEnabled: script == null
                                      ? null
                                      : () => _toggleTaskEnabled(
                                            script.name,
                                            entries[index].name,
                                            false,
                                          ),
                                  appliedAction: _appliedActions[
                                      _appliedKey(entries[index].name)],
                                  onRun: script == null
                                      ? null
                                      : () async {
                                          final taskName = entries[index].name;
                                          final ok = await widget.controller
                                              .quickScheduleTaskAcrossLink(
                                            scriptName: script.name,
                                            taskName: taskName,
                                            runNow: true,
                                          );
                                          if (ok) {
                                            setState(() {
                                              // 立即执行会把任务挪到今天并自动切到
                                              // 「今天」页，标记也要写在今天上。
                                              _appliedActions[_appliedKey(
                                                taskName,
                                                dayIndex: 0,
                                              )] = _QuickAction.run;
                                            });
                                            showToast(
                                              '立即执行',
                                              taskName.tr,
                                            );
                                          }
                                          if (widget.selectedDayIndex != 0) {
                                            widget.onSelectDay(0);
                                          }
                                        },
                                  onWait: script == null
                                      ? null
                                      : () async {
                                          final taskName = entries[index].name;
                                          final ok = await widget.controller
                                              .quickScheduleTaskAcrossLink(
                                            scriptName: script.name,
                                            taskName: taskName,
                                            runNow: false,
                                          );
                                          if (ok) {
                                            setState(() {
                                              _appliedActions[
                                                  _appliedKey(taskName)] =
                                                  _QuickAction.wait;
                                            });
                                            showToast(
                                              '已延后',
                                              taskName.tr,
                                            );
                                          }
                                        },
                                  onEdit: script == null
                                      ? null
                                      : () => showTaskConfigDialog(
                                            context,
                                            controller: widget.controller,
                                            scriptName: script.name,
                                            taskName: entries[index].name,
                                          ),
                                ),
                              ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}

/// Panel toolbar used by both the task panel and the catalog ("总览") panel:
/// a static label chip + item count + optional refresh + search field.
class _PanelToolbar extends StatelessWidget {
  const _PanelToolbar({
    required this.label,
    required this.countText,
    this.searchController,
    this.onSearch,
    this.onRefresh,
  });

  final String label;
  final String countText;
  final TextEditingController? searchController;
  final VoidCallback? onSearch;
  final VoidCallback? onRefresh;

  bool get _hasSearch => searchController != null && onSearch != null;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        children: [
          Row(
            children: [
              _TaskViewChip(label: label, selected: true, onTap: null),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  countText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppColors.text3),
                ),
              ),
              if (onRefresh != null)
                InkWell(
                  borderRadius: BorderRadius.circular(7),
                  onTap: onRefresh,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Icon(
                      Icons.refresh_rounded,
                      size: 16,
                      color: AppColors.text2,
                    ),
                  ),
                ),
            ],
          ),
          if (_hasSearch) ...[
            const SizedBox(height: 8),
            Container(
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: searchController,
                style: TextStyle(fontSize: 12.5, color: AppColors.text),
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 16,
                    color: AppColors.text3,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  hintText: '搜索任务',
                  hintStyle: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.text3,
                  ),
                ),
                onSubmitted: (_) => onSearch?.call(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskViewChip extends StatelessWidget {
  const _TaskViewChip({
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.tealDim : AppColors.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.teal.withValues(alpha: 0.45) : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.teal : AppColors.text2,
          ),
        ),
      ),
    );
  }
}

/// Tasks that only expose settings (no scheduler), so run/wait are hidden.
const Set<String> _kNonSchedulableTasks = <String>{'Script', 'GlobalGame'};

/// Whether [taskName] is the task the config is executing right now.
/// A running task must not be cancelled — it would vanish from the list
/// although the script keeps executing it.
bool _isTaskCurrentlyRunning(ScriptModel? script, String taskName) {
  if (script == null || script.state.value != ScriptState.running) {
    return false;
  }
  return script.runningTask.value.taskName.value.trim() == taskName.trim();
}

/// "总览" list: task catalog grouped by category, matching the original design.
class _DashboardTaskCatalog extends StatefulWidget {
  const _DashboardTaskCatalog({
    required this.menu,
    required this.searchQuery,
    required this.enabledTaskNames,
    required this.scriptRunning,
    required this.runningTaskName,
    this.onToggleEnabled,
    this.onQuickRun,
    this.onQuickWait,
    this.onEdit,
  });

  final Map<String, List<String>> menu;
  final String searchQuery;
  final Set<String> enabledTaskNames;

  /// 配置是否在运行；停止后要清掉「立即执行 / 已延后」的标记。
  final bool scriptRunning;
  final String runningTaskName;
  final Future<void> Function(String task, bool enable)? onToggleEnabled;
  final Future<void> Function(String task)? onQuickRun;
  final Future<void> Function(String task)? onQuickWait;
  final Future<void> Function(String task)? onEdit;

  @override
  State<_DashboardTaskCatalog> createState() => _DashboardTaskCatalogState();
}

class _DashboardTaskCatalogState extends State<_DashboardTaskCatalog> {
  final Set<String> _expanded = <String>{};
  final Map<String, _QuickAction> _applied = <String, _QuickAction>{};

  @override
  void didUpdateWidget(covariant _DashboardTaskCatalog oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 配置停下后，之前的「立即执行 / 已延后」高亮就失效了。
    if (oldWidget.scriptRunning && !widget.scriptRunning) {
      _applied.clear();
    }
  }

  bool _isSchedulable(String task) =>
      !_kNonSchedulableTasks.contains(task.trim());

  bool _isEnabled(String task) => widget.enabledTaskNames.contains(task);

  bool _isLocked(String task) =>
      widget.runningTaskName.isNotEmpty &&
      widget.runningTaskName == task.trim();

  /// Toggles the task in the config's schedule (checkbox in front of the row).
  Future<void> _toggleEnabled(String task, bool enable) async {
    final handler = widget.onToggleEnabled;
    if (handler == null) {
      return;
    }
    await handler(task, enable);
    if (mounted) {
      setState(() => _applied.remove(task));
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      return _buildSearchResults(query);
    }
    return _buildSections();
  }

  Widget _buildSections() {
    final entries = widget.menu.entries
        .where((entry) => entry.value.isNotEmpty)
        .toList(growable: false);
    if (entries.isEmpty) {
      return const _EmptyHint(label: '暂无任务目录');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final expanded = _expanded.contains(entry.key);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CatalogGroupHeader(
              title: entry.key.tr,
              count: entry.value.length,
              expanded: expanded,
              onTap: () => setState(() {
                if (expanded) {
                  _expanded.remove(entry.key);
                } else {
                  _expanded.add(entry.key);
                }
              }),
            ),
            if (expanded) _grid(entry.value),
            const SizedBox(height: 4),
          ],
        );
      },
    );
  }

  Widget _buildSearchResults(String query) {
    final matches = <String>[];
    for (final tasks in widget.menu.values) {
      for (final task in tasks) {
        final localized = task.tr.toLowerCase();
        if (localized.contains(query) || task.toLowerCase().contains(query)) {
          matches.add(task);
        }
      }
    }
    if (matches.isEmpty) {
      return const _EmptyHint(label: '未找到匹配任务');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      children: [_grid(matches)],
    );
  }

  /// Two-column grid of compact task chips: one screen shows twice the tasks
  /// of the old single-column list.
  Widget _grid(List<String> tasks) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 32,
        crossAxisSpacing: 5,
        mainAxisSpacing: 5,
      ),
      itemCount: tasks.length,
      itemBuilder: (context, index) => _chipFor(tasks[index]),
    );
  }

  Widget _chipFor(String task) {
    final enabled = _isEnabled(task);
    final schedulable = _isSchedulable(task);
    return _CatalogTaskChip(
      name: task.tr,
      enabled: enabled,
      locked: _isLocked(task),
      appliedAction: _applied[task],
      onToggleEnabled: !schedulable || widget.onToggleEnabled == null
          ? null
          : () => _toggleEnabled(task, !enabled),
      onRun: !schedulable || widget.onQuickRun == null
          ? null
          : () async {
              await widget.onQuickRun!(task);
              if (mounted) {
                setState(() => _applied[task] = _QuickAction.run);
              }
            },
      onWait: !schedulable || widget.onQuickWait == null
          ? null
          : () async {
              await widget.onQuickWait!(task);
              if (mounted) {
                setState(() => _applied[task] = _QuickAction.wait);
              }
            },
      onOpen: widget.onEdit == null ? null : () => widget.onEdit!(task),
    );
  }
}

/// Category header row of the catalog grid.
class _CatalogGroupHeader extends StatelessWidget {
  const _CatalogGroupHeader({
    required this.title,
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final String title;
  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: Row(
          children: [
            Icon(
              expanded
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_right_rounded,
              size: 15,
              color: AppColors.text3,
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: AppColors.text3),
              ),
            ),
            Text('$count', style: TextStyle(fontSize: 11.5, color: AppColors.text3)),
          ],
        ),
      ),
    );
  }
}

/// Compact task chip used by the catalog grid.
class _CatalogTaskChip extends StatelessWidget {
  const _CatalogTaskChip({
    required this.name,
    required this.enabled,
    required this.locked,
    this.appliedAction,
    this.onToggleEnabled,
    this.onRun,
    this.onWait,
    this.onOpen,
  });

  final String name;
  final bool enabled;
  final bool locked;
  final _QuickAction? appliedAction;
  final VoidCallback? onToggleEnabled;
  final VoidCallback? onRun;
  final VoidCallback? onWait;
  final VoidCallback? onOpen;

  /// Grey used for actions that cannot be used because the task is disabled.
  Color get _kDisabled =>
      AppColors.isDark ? AppColors.text3.withValues(alpha: 0.3) : const Color(0xFFB4B4B4);

  @override
  Widget build(BuildContext context) {
    final canRun = enabled && onRun != null;
    final canWait = enabled && onWait != null;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onOpen,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: enabled ? AppColors.teal.withValues(alpha: 0.10) : AppColors.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled
                ? AppColors.teal.withValues(alpha: 0.30)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            if (onToggleEnabled != null)
              Tooltip(
                message: locked
                    ? '任务执行中，无法取消'
                    : (enabled ? '已启用（点击取消）' : '未启用（点击启用）'),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: onToggleEnabled,
                  child: Icon(
                    enabled
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 13,
                    color: locked
                        ? AppColors.green
                        : enabled
                            ? AppColors.teal
                            : AppColors.text3,
                  ),
                ),
              )
            else
              const SizedBox(width: 13),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: enabled ? AppColors.text : AppColors.text3,
                ),
              ),
            ),
            if (onRun != null)
              _chipIcon(
                Icons.flash_on_rounded,
                canRun
                    ? (appliedAction == _QuickAction.run ? AppColors.teal : AppColors.text3)
                    : _kDisabled,
                canRun ? onRun : null,
                enabled ? '立即执行' : '任务未启用',
              ),
            if (onWait != null)
              _chipIcon(
                Icons.schedule_rounded,
                canWait
                    ? (appliedAction == _QuickAction.wait ? AppColors.blue : AppColors.text3)
                    : _kDisabled,
                canWait ? onWait : null,
                enabled ? '延后执行' : '任务未启用',
              ),
          ],
        ),
      ),
    );
  }

  Widget _chipIcon(
    IconData icon,
    Color color,
    VoidCallback? onTap,
    String tooltip,
  ) {
    return Tooltip(
      message: tooltip,
      // 不可用时用 AbsorbPointer 吞掉点击，否则会冒泡到整格的 onTap（打开参数弹窗）。
      child: AbsorbPointer(
        absorbing: onTap == null,
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: onTap,
          child: SizedBox(
            width: 18,
            height: 18,
            child: Icon(icon, size: 13, color: color),
          ),
        ),
      ),
    );
  }
}

class _DateDistributionCard extends StatelessWidget {
  const _DateDistributionCard({
    required this.entries,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<DashboardTaskEntry> entries;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final days = buildDashboardDayCounts(entries);
    final total = days.fold<int>(0, (sum, day) => sum + day.count);
    return Container(
      height: 114,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '任务日期分布',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '未来7天',
                style: TextStyle(fontSize: 12, color: AppColors.text3),
              ),
              const Spacer(),
              Text(
                '共$total项',
                style: TextStyle(fontSize: 12, color: AppColors.text3),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var index = 0; index < days.length; index++)
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: () => onSelect(index),
                    child: Column(
                      children: [
                        Text(
                          days[index].label,
                          style: TextStyle(
                            fontSize: 11,
                            color: index == selectedIndex ? AppColors.teal : AppColors.text3,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: index == selectedIndex
                                ? AppColors.tealDim
                                : AppColors.surface2,
                            borderRadius: BorderRadius.circular(9),
                            border: index == selectedIndex
                                ? Border.all(
                                    color: AppColors.teal.withValues(alpha: 0.35),
                                  )
                                : null,
                          ),
                          child: Text(
                            '${days[index].count}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: index == selectedIndex ? AppColors.teal : AppColors.text2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskRowTile extends StatelessWidget {
  const _TaskRowTile({
    required this.entry,
    required this.selected,
    this.locked = false,
    this.onToggleEnabled,
    this.onRun,
    this.onWait,
    this.onEdit,
    this.appliedAction,
  });

  final DashboardTaskEntry entry;
  final bool selected;

  /// True for the task the script is executing right now: it cannot be
  /// cancelled, otherwise the row would disappear while still running.
  final bool locked;
  final VoidCallback? onToggleEnabled;
  final VoidCallback? onRun;
  final VoidCallback? onWait;
  final VoidCallback? onEdit;
  final _QuickAction? appliedAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: selected ? AppColors.selectedBg : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? AppColors.selectedBorder : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          if (selected)
            Container(
              width: 2,
              height: 18,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: AppColors.teal,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          Tooltip(
            message: locked ? '任务执行中，无法取消' : '已启用（点击取消）',
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onToggleEnabled,
              child: Icon(
                Icons.check_circle_rounded,
                size: 15,
                color: locked ? AppColors.green : AppColors.teal,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text(
              entry.timeText,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.text3,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    entry.name.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: AppColors.text),
                  ),
                ),
                if (locked)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '执行中',
                      style: TextStyle(fontSize: 10.5, color: AppColors.green),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _RowIconButton(
            icon: _typeIcon(entry.type),
            tooltip: '状态',
            color: _typeColor(entry.type),
            onTap: null,
          ),
          _RowIconButton(
            icon: Icons.flash_on_rounded,
            tooltip: I18n.homeQuickRun.tr,
            color: appliedAction == _QuickAction.run ? AppColors.teal : AppColors.text3,
            onTap: onRun,
            filled: true,
          ),
          _RowIconButton(
            icon: Icons.schedule_rounded,
            tooltip: I18n.homeQuickWait.tr,
            color: appliedAction == _QuickAction.wait ? AppColors.blue : AppColors.text3,
            onTap: onWait,
            filled: true,
          ),
          _RowIconButton(
            icon: Icons.tune_rounded,
            tooltip: I18n.homeOpenTaskParams.tr,
            onTap: onEdit,
            filled: true,
          ),
        ],
      ),
    );
  }
}

class _RowIconButton extends StatelessWidget {
  const _RowIconButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.color,
    this.filled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;

  /// Filled buttons get a 26px tinted square so they read as real buttons.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: 13, color: color ?? AppColors.text3);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: filled
            ? Container(
                width: 26,
                height: 26,
                margin: const EdgeInsets.only(left: 3),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: iconWidget,
              )
            : SizedBox(width: 22, height: 22, child: iconWidget),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Column 1: current config card + task catalog ("总览")
// ---------------------------------------------------------------------------
/// Left column: current config card on top, task catalog ("总览") below it.
class _OverviewColumn extends StatefulWidget {
  const _OverviewColumn({
    required this.controller,
    required this.scriptService,
    required this.script,
  });

  final HomeDashboardController controller;
  final ScriptService scriptService;
  final ScriptModel? script;

  @override
  State<_OverviewColumn> createState() => _OverviewColumnState();
}

class _OverviewColumnState extends State<_OverviewColumn> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Map<String, List<String>> _menu = const <String, List<String>>{};

  /// Today's totals for the active config, shown in the config card.
  ScriptStatisticsDay? _todayStats;
  DateTime? _statsFetchedAt;
  bool _statsLoading = false;

  /// Today's date key (`yyyy-MM-dd`) used by the statistics endpoints.
  static String _todayKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  /// Label of the next task to run: the running one if any, else the earliest
  /// pending entry.
  String _nextTaskText(List<DashboardTaskEntry> entries, String runningName) {
    if (runningName.isNotEmpty) {
      return runningName;
    }
    if (entries.isEmpty) {
      return '';
    }
    final first = entries.first;
    return '${first.timeText} ${first.name.tr}';
  }

  /// Refreshes today's totals at most once per 60 seconds.
  ///
  /// Triggered by rebuilds (schedule pushes + the dashboard clock tick), so no
  /// extra timer is needed.
  void _maybeRefreshTodayStats() {
    final script = widget.script;
    if (script == null || _statsLoading) {
      return;
    }
    final name = script.name.trim();
    if (name.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final fetchedAt = _statsFetchedAt;
    if (fetchedAt != null &&
        now.difference(fetchedAt) < const Duration(seconds: 60)) {
      return;
    }
    _statsFetchedAt = now;
    _statsLoading = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final day = await ApiClient().getScriptStatisticsDay(name, _todayKey());
        if (!mounted || widget.script?.name.trim() != name) {
          return;
        }
        setState(() => _todayStats = day);
      } catch (_) {
        // Keep the previous numbers; the next schedule event retries.
      } finally {
        _statsLoading = false;
      }
    });
  }

  /// Renames the active config from the card title.
  Future<void> _renameScript() async {
    final script = widget.script;
    if (script == null) {
      return;
    }
    final oldName = script.name.trim();
    if (oldName.isEmpty) {
      return;
    }
    // 记住「重命名的是不是当前选中的配置」。改名过程中配置列表会刷新，
    // 旧名字消失会让 controller 兜底选中第一个配置，所以必须在这里先记下来。
    final wasActive =
        widget.controller.activeScriptName.value.trim() == oldName;

    final renamed = await ConfigActions.showRenameDialog(
      scriptService: widget.scriptService,
      oldName: oldName,
    );
    if (!mounted || renamed == null) {
      return;
    }
    if (wasActive) {
      widget.controller.setActiveScript(renamed);
    }
    widget.controller.syncWorkspaceState();
  }

  @override
  void initState() {
    super.initState();
    _loadMenu();
  }

  Future<bool> _loadMenu() async {
    try {
      final menu = await ApiClient().getScriptMenu();
      if (!mounted) {
        return false;
      }
      setState(() => _menu = menu);
      return true;
    } catch (_) {
      // Keep the empty catalog placeholder on failure.
      return false;
    }
  }

  /// Toolbar refresh: reloads the catalog and re-syncs the schedule so the
  /// click always has a visible effect.
  Future<void> _refreshCatalog() async {
    final ok = await _loadMenu();
    final script = widget.script;
    if (script != null) {
      widget.scriptService.wsService.send(script.name, 'get_schedule');
    }
    if (!mounted) {
      return;
    }
    showToast(
      ok ? '已刷新' : '刷新失败',
      ok ? '任务目录 $_catalogCount 项' : '无法读取任务目录',
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Task catalog differs per config, so reload when the active one changes.
  @override
  void didUpdateWidget(covariant _OverviewColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.script?.name != widget.script?.name) {
      _loadMenu();
      _todayStats = null;
      _statsFetchedAt = null;
    }
  }

  void _applySearch() {
    setState(() => _searchQuery = _searchController.text.trim());
  }

  /// Enables / disables one task in the current config's schedule.
  Future<void> _toggleTaskEnabled(
    String scriptName,
    String taskName,
    bool enable,
  ) async {
    if (!enable && _isTaskCurrentlyRunning(widget.script, taskName)) {
      showToast('无法取消', '$taskName 正在执行中');
      return;
    }
    final ok = await widget.controller.quickToggleTaskEnabledAcrossLink(
      scriptName: scriptName,
      taskName: taskName,
      enable: enable,
    );
    if (!ok) {
      showToast('操作失败', '$taskName 未能${enable ? '启用' : '取消'}');
      return;
    }
    // Re-sync the schedule so the checkbox reflects the backend's state.
    widget.scriptService.wsService.send(scriptName, 'get_schedule');
  }

  int get _catalogCount =>
      _menu.values.fold<int>(0, (sum, tasks) => sum + tasks.length);

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final script = widget.script;
    // Rebuild when the schedule or the script state changes.
    return Obx(() {
      final entries = _collectTasks(script);
      // Only the script process state tells us whether it is really running.
      // The schedule's `running` entry is stale for inactive configs, so it
      // must not be used here or every config shows a red "停止运行" button.
      final isRunning = script?.state.value == ScriptState.running;
      final runningTaskName = isRunning
          ? (script?.runningTask.value.taskName.value.trim() ?? '')
          : '';
      final adjustTarget = runningTaskName.isNotEmpty
          ? runningTaskName
          : (entries.isEmpty ? null : entries.first.name);
      final canToggle = script != null && script.name.trim().isNotEmpty;
      final nextTaskText = _nextTaskText(entries, runningTaskName);
      _maybeRefreshTodayStats();
      final enabledTaskNames =
          script == null ? const <String>{} : controller.enabledTaskNamesFor(script);
      var enabledInCatalog = 0;
      for (final tasks in _menu.values) {
        for (final task in tasks) {
          if (enabledTaskNames.contains(task)) {
            enabledInCatalog++;
          }
        }
      }
      return Column(
        children: [
          _CurrentConfigCard(
            configName: script?.name ?? '',
            nextTaskText: nextTaskText,
            running: isRunning,
            hasRunningTask: runningTaskName.isNotEmpty,
            bulkMode: controller.bulkQuickScheduleMode.value,
            todayRuntimeSeconds: _todayStats?.totalRuntimeSeconds,
            todayRunCount: _todayStats?.totalTaskRunCount,
            todayBattleCount: _todayStats?.totalBattleCount,
            linked: controller.hasActiveLinkFor(script?.name ?? ''),
            onOpenConnector: script == null
                ? null
                : () => showConnectorDialog(
                      context,
                      controller: controller,
                      sourceScript: script.name,
                    ),
            canRename: !isRunning,
            onRename: isRunning ? null : _renameScript,
            onStartStop: canToggle ? () => _toggleScript(script) : null,
            onRunAll: script == null
                ? null
                : () => controller.bulkQuickScheduleTasks(
                      scriptName: script.name,
                      runNow: true,
                    ),
            onWaitAll: script == null
                ? null
                : () => controller.bulkQuickScheduleTasks(
                      scriptName: script.name,
                      runNow: false,
                    ),
            onAdjust: adjustTarget == null || script == null
                ? null
                : () => showTaskConfigDialog(
                      context,
                      controller: controller,
                      scriptName: script.name,
                      taskName: adjustTarget,
                    ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _Panel(
              child: Column(
                children: [
                  _PanelToolbar(
                    label: '总览',
                    countText: '共 $_catalogCount 项 · 已启用 $enabledInCatalog',
                    searchController: _searchController,
                    onSearch: _applySearch,
                    onRefresh: _refreshCatalog,
                  ),
                  Expanded(
                    child: _DashboardTaskCatalog(
                      menu: _menu,
                      searchQuery: _searchQuery,
                      enabledTaskNames: enabledTaskNames,
                      runningTaskName: runningTaskName,
                      scriptRunning: isRunning,
                      onToggleEnabled: script == null
                          ? null
                          : (task, enable) => _toggleTaskEnabled(
                                script.name,
                                task,
                                enable,
                              ),
                      onQuickRun: script == null
                          ? null
                          : (task) async {
                              final ok =
                                  await controller.quickScheduleTaskAcrossLink(
                                scriptName: script.name,
                                taskName: task,
                                runNow: true,
                              );
                              if (ok) {
                                showToast('立即执行', task.tr);
                              }
                            },
                      onQuickWait: script == null
                          ? null
                          : (task) async {
                              final ok =
                                  await controller.quickScheduleTaskAcrossLink(
                                scriptName: script.name,
                                taskName: task,
                                runNow: false,
                              );
                              if (ok) {
                                showToast('已延后', task.tr);
                              }
                            },
                      onEdit: script == null
                          ? null
                          : (task) async {
                              await showTaskConfigDialog(
                                context,
                                controller: controller,
                                scriptName: script.name,
                                taskName: task,
                              );
                            },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  /// Starts the selected config when idle, stops it when already running.
  Future<void> _toggleScript(ScriptModel model) async {
    final name = model.name.trim();
    if (name.isEmpty) {
      return;
    }
    // 连接器勾选后，启停会同步到同一组配置。
    await widget.controller.applyLinkedPowerToggle(
      sourceScript: name,
      enable: model.state.value != ScriptState.running,
    );
  }
}

/// Log center view of the right column.
class _LogsColumn extends StatelessWidget {
  const _LogsColumn({required this.scriptName});

  final String scriptName;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: scriptName.isEmpty
          ? const _Panel(child: _EmptyHint(label: '请选择脚本'))
          : LogCenterPanel(scriptName: scriptName),
    );
  }
}

/// Top card of the middle column: shows the selected config name and a green
/// power button that starts / stops that config.
class _CurrentConfigCard extends StatelessWidget {
  const _CurrentConfigCard({
    required this.configName,
    required this.nextTaskText,
    required this.running,
    required this.hasRunningTask,
    required this.bulkMode,
    required this.todayRuntimeSeconds,
    required this.todayRunCount,
    required this.todayBattleCount,
    required this.linked,
    this.onOpenConnector,
    this.onRename,
    this.canRename = true,
    this.onStartStop,
    this.onAdjust,
    this.onRunAll,
    this.onWaitAll,
  });

  final String configName;
  final String nextTaskText;

  /// 配置进程是否在运行（决定按钮是「停止运行」还是「立即运行」）。
  final bool running;

  /// 是否真的有任务正在执行（决定行首显示「当前」还是「下一个」）。
  final bool hasRunningTask;
  final HomeBulkQuickScheduleMode bulkMode;

  /// Today's totals from `/stats/{config}?date=today`; null until loaded.
  final double? todayRuntimeSeconds;
  final int? todayRunCount;
  final int? todayBattleCount;

  /// 连接器是否生效（勾选了其它配置）。决定按钮是青色还是灰色。
  final bool linked;

  /// Opens the connector dialog.
  final VoidCallback? onOpenConnector;

  /// Opens the rename dialog; disabled while the config is running.
  final VoidCallback? onRename;
  final bool canRename;

  final VoidCallback? onStartStop;
  final VoidCallback? onAdjust;
  final VoidCallback? onRunAll;
  final VoidCallback? onWaitAll;

  String get _runtimeText {
    final seconds = todayRuntimeSeconds;
    if (seconds == null) {
      return '--';
    }
    if (seconds <= 0) {
      return '0m';
    }
    final duration = Duration(seconds: seconds.round());
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    }
    if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m';
    }
    return '${duration.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 152,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Row 1: config name + bulk actions + start/stop button.
                  Row(
                    children: [
                      Expanded(
                        // 只有名字本身可点，空白区域不再触发重命名。
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Tooltip(
                            message:
                                canRename ? '点击重命名' : '运行中的配置不可重命名',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(7),
                              onTap: canRename ? onRename : null,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                  horizontal: 4,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        configName.isEmpty
                                            ? '未选择配置'
                                            : configName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.text,
                                        ),
                                      ),
                                    ),
                                    if (canRename) ...[
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.edit_rounded,
                                        size: 13,
                                        color: AppColors.text3,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ConnectorButton(
                        linked: linked,
                        onTap: onOpenConnector,
                      ),
                      const SizedBox(width: 4),
                      _BulkIconButton(
                        icon: Icons.bolt_rounded,
                        tooltip: '全部立即运行',
                        loading: bulkMode == HomeBulkQuickScheduleMode.runNow,
                        onTap: onRunAll,
                      ),
                      const SizedBox(width: 4),
                      _BulkIconButton(
                        icon: Icons.schedule_rounded,
                        tooltip: '全部立即等待',
                        loading: bulkMode == HomeBulkQuickScheduleMode.waitNow,
                        onTap: onWaitAll,
                      ),
                      const SizedBox(width: 8),
                      _RunButton(running: running, onTap: onStartStop),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Row 2: currently running task, or the next scheduled one.
                  Row(
                    children: [
                      Text(
                        hasRunningTask ? '当前' : '下一个',
                        style: TextStyle(
                          fontSize: 12,
                          color: hasRunningTask
                              ? AppColors.green
                              : AppColors.text3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          nextTaskText.isEmpty ? '暂无执行任务' : nextTaskText.tr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: hasRunningTask
                                ? FontWeight.w500
                                : FontWeight.w400,
                            color: nextTaskText.isEmpty
                                ? AppColors.text3
                                : (hasRunningTask
                                    ? AppColors.text
                                    : AppColors.text2),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _PillButton(
                        label: '调整计划',
                        primary: false,
                        onTap: onAdjust,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Row 3: today's totals.
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                _StatCell(label: '今日运行', value: _runtimeText),
                Container(width: 1, height: 26, color: AppColors.border),
                _StatCell(
                  label: '任务次数',
                  value: todayRunCount == null ? '--' : '$todayRunCount',
                ),
                Container(width: 1, height: 26, color: AppColors.border),
                _StatCell(
                  label: '战斗场次',
                  value: todayBattleCount == null ? '--' : '$todayBattleCount',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One cell of the config card's today-totals strip.
class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: AppColors.text3),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Green rounded "立即运行" button: starts the config when idle, stops it when
/// running.
/// Small square button used for the bulk "run all / wait all" actions.
class _BulkIconButton extends StatelessWidget {
  const _BulkIconButton({
    required this.icon,
    required this.tooltip,
    required this.loading,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !loading;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: enabled ? onTap : null,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: loading
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.teal,
                  ),
                )
              : _DoubleIcon(icon: icon, color: enabled ? AppColors.teal : AppColors.text3),
        ),
      ),
    );
  }
}

/// Renders two offset copies of [icon] to convey an "all" action.
/// 配置卡片上的连接器按钮：连接生效时青色，未连接时灰色。
class _ConnectorButton extends StatelessWidget {
  const _ConnectorButton({required this.linked, this.onTap});

  final bool linked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: linked ? '连接器（已连接）' : '连接器',
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: linked ? AppColors.tealDim : AppColors.surface2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: linked
                  ? AppColors.teal.withValues(alpha: 0.5)
                  : AppColors.border,
            ),
          ),
          child: Icon(
            Icons.link_rounded,
            size: 15,
            color: linked ? AppColors.teal : AppColors.text3,
          ),
        ),
      ),
    );
  }
}

class _DoubleIcon extends StatelessWidget {
  const _DoubleIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 18,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            child: Icon(
              icon,
              size: 13,
              color: color.withValues(alpha: 0.5),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: Icon(icon, size: 14, color: color),
          ),
        ],
      ),
    );
  }
}

class _RunButton extends StatelessWidget {
  const _RunButton({required this.running, this.onTap});

  final bool running;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    // Two distinct states: idle = green "立即运行", running = red "停止运行".
    final background = !enabled
        ? AppColors.surface2
        : (running ? AppColors.red : AppColors.teal);
    final foreground = !enabled
        ? AppColors.text3
        : (running
            ? Colors.white
            : (AppColors.isDark ? const Color(0xFF04140F) : Colors.white));
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled ? background : AppColors.border,
          ),
        ),
        child: Text(
          running ? '停止运行' : '立即运行',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: foreground,
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.primary,
    this.onTap,
  });

  final String label;
  final bool primary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? AppColors.teal : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: primary ? AppColors.teal : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
            color: primary
                ? (AppColors.isDark ? const Color(0xFF04140F) : Colors.white)
                : AppColors.text2,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Column 3: log / statistics switch
// ---------------------------------------------------------------------------
/// Right column: the log center and the statistics view share this space,
/// switched by the two chips on top.
class _RightColumn extends StatefulWidget {
  const _RightColumn({required this.scriptName});

  final String scriptName;

  @override
  State<_RightColumn> createState() => _RightColumnState();
}

class _RightColumnState extends State<_RightColumn> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // The statistics controller only loads data while its panel is visible.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncStatsVisible());
  }

  @override
  void dispose() {
    _setStatsVisible(false);
    super.dispose();
  }

  void _setStatsVisible(bool visible) {
    if (!Get.isRegistered<HomeDashboardController>()) {
      return;
    }
    Get.find<HomeDashboardController>().setStatsPanelVisible(visible);
  }

  void _syncStatsVisible() {
    if (!mounted) {
      return;
    }
    _setStatsVisible(_tab == 1);
  }

  void _selectTab(int index) {
    if (_tab == index) {
      return;
    }
    setState(() => _tab = index);
    _syncStatsVisible();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            _TaskViewChip(
              label: '日志',
              selected: _tab == 0,
              onTap: () => _selectTab(0),
            ),
            const SizedBox(width: 8),
            _TaskViewChip(
              label: '统计',
              selected: _tab == 1,
              onTap: () => _selectTab(1),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _tab == 0
              ? _LogsColumn(scriptName: widget.scriptName)
              : const _StatisticsColumn(),
        ),
      ],
    );
  }
}

/// Statistics tab content (the original home page's statistics panel).
///
/// The theme is passed in instead of read inside `build` on purpose: a
/// canonicalized `const` widget is skipped when the app theme flips, which
/// left the panel in the old palette after switching day / night mode.
class _StatisticsColumn extends StatelessWidget {
  const _StatisticsColumn();

  @override
  Widget build(BuildContext context) {
    return const _Panel(child: ScriptStatisticsPanel());
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------
class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        label,
        style: TextStyle(fontSize: 12.5, color: AppColors.text3),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Task helpers
// ---------------------------------------------------------------------------
/// Last quick action applied to a task, used to tint its action icons.
enum _QuickAction { run, wait }

IconData _typeIcon(DashboardTaskType type) => switch (type) {
      DashboardTaskType.running => Icons.bolt_rounded,
      DashboardTaskType.pending => Icons.layers_rounded,
      DashboardTaskType.waiting => Icons.hourglass_bottom_rounded,
    };

Color _typeColor(DashboardTaskType type) => switch (type) {
      DashboardTaskType.running => AppColors.green,
      DashboardTaskType.pending => AppColors.yellow,
      DashboardTaskType.waiting => AppColors.text2,
    };

List<DashboardTaskEntry> _collectTasks(ScriptModel? model) {
  if (model == null) {
    return const <DashboardTaskEntry>[];
  }
  final isRunning = model.state.value == ScriptState.running;
  final runningTask = model.runningTask.value;
  final runningName = runningTask.taskName.value.trim();
  // The backend always reports the earliest due task in the `running` slot.
  // When the script is idle that task is still due, so keep it visible as a
  // pending entry instead of dropping it (otherwise pre-today tasks vanish
  // until the script is started).
  final pendingTasks = [
    if (!isRunning && runningName.isNotEmpty) runningTask,
    ...model.pendingTaskList,
  ];
  return collectDashboardTasks(
    runningTaskName: isRunning ? runningName : '',
    pendingTasks: pendingTasks,
    waitingTasks: model.waitingTaskList,
  );
}

/// Returns the entries scheduled on the day at [dayIndex] (0 = today).
/// The running task (no time) is only shown for today.
List<DashboardTaskEntry> _filterEntriesForDay(
  List<DashboardTaskEntry> entries,
  int dayIndex,
) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final selectedDay = today.add(Duration(days: dayIndex));
  return entries.where((entry) {
    final time = entry.time;
    if (time == null) {
      return dayIndex == 0;
    }
    final day = DateTime(time.year, time.month, time.day);
    if (dayIndex == 0) {
      // Today also shows overdue tasks: quick-run sets next_run to yesterday
      // so the task stays visible instead of disappearing.
      return !day.isAfter(today);
    }
    return day == selectedDay;
  }).toList(growable: false);
}
