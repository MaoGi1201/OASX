import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/modules/home/config_actions.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';
import 'package:oasx/modules/home/models/config_model.dart';
import 'package:oasx/modules/home/models/dashboard_task_helpers.dart';
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
bool get _isDark => Get.isDarkMode;

// Dark-only surface values kept as named constants so bulk replacements of the
// inline `const Color(0x...)` usages below do not rewrite these definitions.
const _darkSurface2 = Color(0xFF1B2129);
const _darkSurface3 = Color(0xFF141820);
const _darkSelectedBg = Color(0xFF1C232C);
const _darkSelectedBorder = Color(0xFF2B3540);

// Surfaces
Color get _kBg => _isDark ? const Color(0xFF0A0C0F) : const Color(0xFFF3F4F7);
Color get _kPanel =>
    _isDark ? const Color(0xFF12151A) : const Color(0xFFFFFFFF);
Color get _kCard =>
    _isDark ? const Color(0xFF1A1F26) : const Color(0xFFF7F8FA);
Color get _kSurface2 =>
    _isDark ? _darkSurface2 : const Color(0xFFEDEFF3);
Color get _kSurface3 =>
    _isDark ? _darkSurface3 : const Color(0xFFF0F2F5);
Color get _kSelectedBg =>
    _isDark ? _darkSelectedBg : const Color(0xFFEAF6F2);
Color get _kSelectedBorder =>
    _isDark ? _darkSelectedBorder : const Color(0xFFBEE8DC);
Color get _kBorder =>
    _isDark ? const Color(0xFF232932) : const Color(0xFFE1E5EB);

// Text
Color get _kText =>
    _isDark ? const Color(0xFFE8EAED) : const Color(0xFF1B1F24);
Color get _kText2 =>
    _isDark ? const Color(0xFF9AA3AF) : const Color(0xFF5A6472);
Color get _kText3 =>
    _isDark ? const Color(0xFF6B7280) : const Color(0xFF8B94A3);

// Accents
Color get _kTeal =>
    _isDark ? const Color(0xFF2FD6A5) : const Color(0xFF0E9E7A);
Color get _kTealDim =>
    _isDark ? const Color(0xFF123B34) : const Color(0xFFDFF5EE);
Color get _kGreen =>
    _isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
Color get _kYellow =>
    _isDark ? const Color(0xFFF0B429) : const Color(0xFFD97706);
Color get _kRed =>
    _isDark ? const Color(0xFFE5484D) : const Color(0xFFDC2626);
Color get _kBlue =>
    _isDark ? const Color(0xFF5B8DEF) : const Color(0xFF2563EB);

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
  Future<void> _loadDeviceMode(String scriptName) async {
    if (scriptName.isEmpty) {
      if (mounted) {
        setState(() => _isDesktopMode = false);
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
      if (!mounted) {
        return;
      }
      setState(() => _isDesktopMode = control == 'desktop');
    } catch (_) {
      // Keep the previous mode on failure.
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _kBg,
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
                          await _loadDeviceMode(script.name);
                        },
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
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
            _ => _StatisticsColumn(theme: _statsTheme),
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
  });

  final HomeDashboardController controller;
  final ScriptService scriptService;
  final ScriptModel? script;
  final bool isDesktopMode;
  final DateTime now;
  final VoidCallback onAddScriptTap;
  final Future<void> Function()? onOpenScriptConfig;

  @override
  Widget build(BuildContext context) {
    final names = scriptService.scriptOrderList;
    final activeName = controller.activeScriptName.value.trim();
    final compact = MediaQuery.of(context).size.width < 700;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ...names.map(
                    (name) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      // 每个标签独立订阅自己配置的 state，否则点击非当前
                      // 配置的启停开关时，那个标签的启停状态不会刷新。
                      child: Obx(
                        () => _AccountTab(
                          name: name,
                          active: name == activeName,
                          state: _stateOf(name),
                          onTap: () => controller.setActiveScript(name),
                          onTogglePower: () => _togglePower(name),
                        ),
                      ),
                    ),
                  ),
                  _SquareButton(
                    tooltip: '新增脚本',
                    onTap: onAddScriptTap,
                    child: Icon(
                      Icons.add_rounded,
                      size: 16,
                      color: _kText2,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _SquareButton(
                    tooltip: I18n.delete.tr,
                    onTap: activeName.isEmpty
                        ? null
                        : () => _deleteActive(activeName),
                    child: Icon(
                      Icons.remove_rounded,
                      size: 16,
                      color: _kText2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SquareButton(
            tooltip: _isDark ? '切换到白天' : '切换到黑夜',
            onTap: () {
              if (Get.isRegistered<ThemeService>()) {
                Get.find<ThemeService>().switchTheme();
              }
            },
            child: Icon(
              _isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              size: 15,
              color: _kText2,
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
              color: _kText2,
            ),
          ),
          const SizedBox(width: 8),
          if (!compact) ...[
            _HeaderStatusChip(
              controller: controller,
              scriptService: scriptService,
              script: script,
            ),
            const SizedBox(width: 8),
          ],
          Text(
            formatHhMm(now),
            style: TextStyle(
              fontSize: 12.5,
              color: _kText2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
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
    if (model.state.value == ScriptState.running) {
      await scriptService.stopScript(name);
      scriptService.wsService.send(name, 'get_schedule');
    } else {
      await scriptService.startScript(name);
    }
  }

  Future<void> _deleteActive(String name) async {
    await ConfigActions.showDeleteDialog(
      scriptService: scriptService,
      name: name,
    );
  }
}

/// 右上角的连接/运行状态胶囊。
///
/// 单独抽成组件是为了让它自己 `Obx` 订阅当前配置的 `state`——父级 header
/// 的 build 不在任何 Obx 的追踪范围内，直接读 rx 不会触发重建。
class _HeaderStatusChip extends StatelessWidget {
  const _HeaderStatusChip({
    required this.controller,
    required this.scriptService,
    required this.script,
  });

  final HomeDashboardController controller;
  final ScriptService scriptService;
  final ScriptModel? script;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final checking = controller.isStartupChecking.value;
      final connected = !checking &&
          !controller.isStartupConnectionFailed.value &&
          scriptService.scriptOrderList.isNotEmpty;
      final scriptState = script?.state.value;
      String statusText;
      Color statusColor;
      if (!connected) {
        statusText = checking ? '连接中…' : '未连接 · 点击重试';
        statusColor = checking ? _kYellow : _kRed;
      } else {
        statusText = switch (scriptState) {
          ScriptState.running => '运行中',
          ScriptState.warning => '卡死/异常',
          ScriptState.updating => '更新中',
          _ => '未启动',
        };
        statusColor = switch (scriptState) {
          ScriptState.running => _kGreen,
          // 原版用黄色表示脚本卡死（SystemExit → WARNING），不是红色。
          ScriptState.warning => _kYellow,
          ScriptState.updating => _kBlue,
          _ => _kText3,
        };
      }
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: connected || checking
            ? null
            : () => controller.retryStartupConnection(),
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _kSurface3,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                statusText,
                style: TextStyle(fontSize: 12, color: _kText2),
              ),
            ],
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
          color: selected ? _kTealDim : _kSurface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? _kTeal.withValues(alpha: 0.45) : _kBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? _kTeal : _kText2,
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
    this.onTogglePower,
  });

  final String name;
  final bool active;
  final ScriptState state;
  final VoidCallback onTap;
  final VoidCallback? onTogglePower;

  bool get _running => state == ScriptState.running;
  bool get _warning => state == ScriptState.warning;

  /// 运行中=绿，卡死/异常=黄，更新中=蓝，未启动=灰（与原版一致）。
  Color get _accent {
    return switch (state) {
      ScriptState.running => _kGreen,
      ScriptState.warning => _kYellow,
      ScriptState.updating => _kBlue,
      ScriptState.inactive => _kText3,
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
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active ? _kTealDim : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? _kTeal.withValues(alpha: 0.55)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              name,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? _kTeal : _kText2,
              ),
            ),
            if (onTogglePower != null) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: _powerTip,
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: onTogglePower,
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _running || _warning
                          ? accent.withValues(alpha: 0.14)
                          : _kSurface2,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _running || _warning
                            ? accent.withValues(alpha: 0.6)
                            : _kBorder,
                      ),
                    ),
                    child: Icon(
                      Icons.power_settings_new_rounded,
                      size: 13,
                      color: _running || _warning ? accent : _kText3,
                    ),
                  ),
                ),
              ),
            ],
          ],
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
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: _kSurface3,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: _kBorder),
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
  final Map<String, _QuickAction> _appliedActions =
      <String, _QuickAction>{};

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
    final ok = await widget.controller.quickToggleTaskEnabled(
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
                                  appliedAction:
                                      _appliedActions[entries[index].name],
                                  onRun: script == null
                                      ? null
                                      : () async {
                                          final taskName = entries[index].name;
                                          final ok = await widget.controller
                                              .quickScheduleTask(
                                            scriptName: script.name,
                                            taskName: taskName,
                                            runNow: true,
                                          );
                                          if (ok) {
                                            setState(() {
                                              _appliedActions[taskName] =
                                                  _QuickAction.run;
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
                                              .quickScheduleTask(
                                            scriptName: script.name,
                                            taskName: taskName,
                                            runNow: false,
                                          );
                                          if (ok) {
                                            setState(() {
                                              _appliedActions[taskName] =
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
                  style: TextStyle(fontSize: 12, color: _kText3),
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
                      color: _kSurface2,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: _kBorder),
                    ),
                    child: Icon(
                      Icons.refresh_rounded,
                      size: 16,
                      color: _kText2,
                    ),
                  ),
                ),
            ],
          ),
          if (_hasSearch) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 34,
                    decoration: BoxDecoration(
                      color: _kSurface2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _kBorder),
                    ),
                    child: TextField(
                      controller: searchController,
                      style: TextStyle(fontSize: 12.5, color: _kText),
                      textAlignVertical: TextAlignVertical.center,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 10),
                        hintText: '搜索任务',
                        hintStyle: TextStyle(
                          fontSize: 12.5,
                          color: _kText3,
                        ),
                      ),
                      onSubmitted: (_) => onSearch?.call(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onSearch,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _kSurface2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _kBorder),
                    ),
                    child: Icon(
                      Icons.search_rounded,
                      size: 17,
                      color: _kText2,
                    ),
                  ),
                ),
              ],
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
          color: selected ? _kTealDim : _kSurface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? _kTeal.withValues(alpha: 0.45) : _kBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? _kTeal : _kText2,
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
    required this.runningTaskName,
    this.onToggleEnabled,
    this.onQuickRun,
    this.onQuickWait,
    this.onEdit,
  });

  final Map<String, List<String>> menu;
  final String searchQuery;
  final Set<String> enabledTaskNames;
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
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final expanded = _expanded.contains(entry.key);
        return _CatalogCard(
          title: entry.key.tr,
          count: entry.value.length,
          expanded: expanded,
          onToggle: () => setState(() {
            if (expanded) {
              _expanded.remove(entry.key);
            } else {
              _expanded.add(entry.key);
            }
          }),
          children: expanded
              ? entry.value
                  .map(
                    (task) => _CatalogTaskRow(
                      name: task.tr,
                      enabled: _isEnabled(task),
                      locked: _isLocked(task),
                      appliedAction: _applied[task],
                      onToggleEnabled:
                          !_isSchedulable(task) ||
                                  widget.onToggleEnabled == null
                              ? null
                              : () => _toggleEnabled(task, !_isEnabled(task)),
                      onRun: !_isSchedulable(task) || widget.onQuickRun == null
                          ? null
                          : () async {
                              await widget.onQuickRun!(task);
                              if (mounted) {
                                setState(
                                  () => _applied[task] = _QuickAction.run,
                                );
                              }
                            },
                      onWait: !_isSchedulable(task) ||
                              widget.onQuickWait == null
                          ? null
                          : () async {
                              await widget.onQuickWait!(task);
                              if (mounted) {
                                setState(
                                  () => _applied[task] = _QuickAction.wait,
                                );
                              }
                            },
                      onEdit: widget.onEdit == null
                          ? null
                          : () => widget.onEdit!(task),
                    ),
                  )
                  .toList(growable: false)
              : const <Widget>[],
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
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final task = matches[index];
        return _CatalogTaskRow(
          name: task.tr,
          enabled: _isEnabled(task),
          locked: _isLocked(task),
          appliedAction: _applied[task],
          onToggleEnabled: !_isSchedulable(task) || widget.onToggleEnabled == null
              ? null
              : () => _toggleEnabled(task, !_isEnabled(task)),
          onRun: !_isSchedulable(task) || widget.onQuickRun == null
              ? null
              : () async {
                  await widget.onQuickRun!(task);
                  if (mounted) {
                    setState(() => _applied[task] = _QuickAction.run);
                  }
                },
          onWait: !_isSchedulable(task) || widget.onQuickWait == null
              ? null
              : () async {
                  await widget.onQuickWait!(task);
                  if (mounted) {
                    setState(() => _applied[task] = _QuickAction.wait);
                  }
                },
          onEdit: widget.onEdit == null ? null : () => widget.onEdit!(task),
        );
      },
    );
  }
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({
    required this.title,
    required this.count,
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  final String title;
  final int count;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.drag_indicator_rounded,
                    size: 18,
                    color: _kText3,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _kText,
                      ),
                    ),
                  ),
                  Text(
                    '$count',
                    style: TextStyle(fontSize: 13, color: _kText2),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: _kText3,
                  ),
                ],
              ),
            ),
          ),
          if (children.isNotEmpty) ...[
            Divider(height: 1, color: _kBorder),
            ...children,
          ],
        ],
      ),
    );
  }
}

class _CatalogTaskRow extends StatelessWidget {
  const _CatalogTaskRow({
    required this.name,
    required this.enabled,
    this.locked = false,
    this.onToggleEnabled,
    this.onRun,
    this.onWait,
    this.onEdit,
    this.appliedAction,
  });

  final String name;
  final bool enabled;
  final bool locked;
  final VoidCallback? onToggleEnabled;
  final VoidCallback? onRun;
  final VoidCallback? onWait;
  final VoidCallback? onEdit;
  final _QuickAction? appliedAction;

  /// Grey used for actions that cannot be used because the task is disabled.
  Color get _kDisabled =>
      _isDark ? _kText3.withValues(alpha: 0.3) : const Color(0xFFB4B4B4);

  @override
  Widget build(BuildContext context) {
    final canRun = enabled && onRun != null;
    final canWait = enabled && onWait != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          // 勾选圆圈：勾上=该任务在当前配置的调度里启用。
          if (onToggleEnabled != null)
            Tooltip(
              message: locked
                  ? '任务执行中，无法取消'
                  : (enabled ? '已启用（点击取消）' : '未启用（点击启用）'),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onToggleEnabled,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    enabled
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 16,
                    color: locked
                        ? _kGreen
                        : enabled
                            ? _kTeal
                            : _kText3,
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 20, height: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: enabled ? _kText2 : _kText3,
              ),
            ),
          ),
          if (onRun != null)
            _RowIconButton(
              icon: Icons.flash_on_rounded,
              tooltip: enabled ? I18n.homeQuickRun.tr : '任务未启用',
              color: !enabled
                  ? _kDisabled
                  : appliedAction == _QuickAction.run
                      ? _kTeal
                      : _kText3,
              onTap: canRun ? onRun : null,
            ),
          if (onWait != null)
            _RowIconButton(
              icon: Icons.schedule_rounded,
              tooltip: enabled ? I18n.homeQuickWait.tr : '任务未启用',
              color: !enabled
                  ? _kDisabled
                  : appliedAction == _QuickAction.wait
                      ? _kBlue
                      : _kText3,
              onTap: canWait ? onWait : null,
            ),
          _RowIconButton(
            icon: Icons.tune_rounded,
            tooltip: I18n.homeOpenTaskParams.tr,
            onTap: onEdit,
          ),
        ],
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
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
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
                  color: _kText,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '未来7天',
                style: TextStyle(fontSize: 12, color: _kText3),
              ),
              const Spacer(),
              Text(
                '共$total项',
                style: TextStyle(fontSize: 12, color: _kText3),
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
                            color: index == selectedIndex ? _kTeal : _kText3,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: index == selectedIndex
                                ? _kTealDim
                                : _kSurface2,
                            borderRadius: BorderRadius.circular(9),
                            border: index == selectedIndex
                                ? Border.all(
                                    color: _kTeal.withValues(alpha: 0.35),
                                  )
                                : null,
                          ),
                          child: Text(
                            '${days[index].count}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: index == selectedIndex ? _kTeal : _kText2,
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
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? _kSelectedBg : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? _kSelectedBorder : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          if (selected)
            Container(
              width: 2,
              height: 16,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _kTeal,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          Tooltip(
            message: locked ? '任务执行中，无法取消' : '已启用（点击取消）',
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onToggleEnabled,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: locked ? _kGreen : _kTeal,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 42,
            child: Text(
              entry.timeText,
              style: TextStyle(
                fontSize: 12.5,
                color: _kText2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              entry.name.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: _kText),
            ),
          ),
          _RowIconButton(
            icon: _typeIcon(entry.type),
            tooltip: '状态',
            color: _typeColor(entry.type),
            onTap: null,
          ),
          _RowIconButton(
            icon: Icons.flash_on_rounded,
            tooltip: I18n.homeQuickRun.tr,
            color: appliedAction == _QuickAction.run ? _kTeal : _kText3,
            onTap: onRun,
          ),
          _RowIconButton(
            icon: Icons.schedule_rounded,
            tooltip: I18n.homeQuickWait.tr,
            color: appliedAction == _QuickAction.wait ? _kBlue : _kText3,
            onTap: onWait,
          ),
          _RowIconButton(
            icon: Icons.tune_rounded,
            tooltip: I18n.homeOpenTaskParams.tr,
            onTap: onEdit,
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
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: SizedBox(
          width: 24,
          height: 24,
          child: Icon(icon, size: 13, color: color ?? _kText3),
        ),
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
    final ok = await widget.controller.quickToggleTaskEnabled(
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
      final enabledTaskNames =
          script == null ? const <String>{} : controller.enabledTaskNamesFor(script);
      return Column(
        children: [
          _CurrentConfigCard(
            configName: script?.name ?? '',
            currentTaskName: runningTaskName,
            running: isRunning,
            bulkMode: controller.bulkQuickScheduleMode.value,
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
                    countText: '共 $_catalogCount 项',
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
                              final ok = await controller.quickScheduleTask(
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
                              final ok = await controller.quickScheduleTask(
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
    if (model.state.value == ScriptState.running) {
      await widget.scriptService.stopScript(name);
      // Re-sync the schedule so the just-stopped task stays visible instead of
      // vanishing when the backend drops it from the running slot.
      widget.scriptService.wsService.send(name, 'get_schedule');
    } else {
      await widget.scriptService.startScript(name);
    }
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
          : Theme(
              data: _logTheme,
              child: LogCenterPanel(scriptName: scriptName),
            ),
    );
  }
}

/// Dark theme that aligns the log center's buttons with the dashboard style.
ThemeData get _logTheme {
  final brightness = _isDark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: _kTeal,
    brightness: brightness,
  ).copyWith(
    surface: _kPanel,
    onSurface: _kText,
    outlineVariant: _kBorder,
  );
  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: _kPanel,
    dividerColor: _kBorder,
    iconTheme: IconThemeData(color: _kText2),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _kTealDim;
          }
          return _kSurface2;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _kTeal;
          }
          return _kText2;
        }),
        side: WidgetStateProperty.all(BorderSide(color: _kBorder)),
      ),
    ),
  );
}

/// Theme that makes the statistics panel (and its chart) follow the dashboard
/// palette instead of the bare Material defaults.
ThemeData get _statsTheme {
  final brightness = _isDark ? Brightness.dark : Brightness.light;
  final base = ThemeData(brightness: brightness);
  final scheme = ColorScheme.fromSeed(
    seedColor: _kTeal,
    brightness: brightness,
  ).copyWith(
    primary: _kTeal,
    onPrimary: _isDark ? const Color(0xFF04140F) : Colors.white,
    surface: _kPanel,
    onSurface: _kText,
    onSurfaceVariant: _kText2,
    outline: _kBorder,
    outlineVariant: _kBorder,
    surfaceContainerHighest: _kSurface2,
    surfaceContainerHigh: _kSurface3,
    surfaceContainer: _kSurface2,
    surfaceContainerLow: _kSurface2,
    error: _kRed,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: _kPanel,
    canvasColor: _kPanel,
    cardColor: _kCard,
    dividerColor: _kBorder,
    shadowColor: Colors.transparent,
    textTheme: base.textTheme.apply(
      bodyColor: _kText,
      displayColor: _kText,
    ),
    iconTheme: IconThemeData(color: _kText2),
    dividerTheme: DividerThemeData(color: _kBorder, thickness: 1, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: _kTeal),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.all(_kText2),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: _kSurface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: TextStyle(fontSize: 13, color: _kText),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: _kSurface3,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kBorder),
      ),
      textStyle: TextStyle(fontSize: 12, color: _kText),
    ),
  );
}

/// Top card of the middle column: shows the selected config name and a green
/// power button that starts / stops that config.
class _CurrentConfigCard extends StatelessWidget {
  const _CurrentConfigCard({
    required this.configName,
    required this.currentTaskName,
    required this.running,
    required this.bulkMode,
    this.onStartStop,
    this.onAdjust,
    this.onRunAll,
    this.onWaitAll,
  });

  final String configName;
  final String currentTaskName;
  final bool running;
  final HomeBulkQuickScheduleMode bulkMode;
  final VoidCallback? onStartStop;
  final VoidCallback? onAdjust;
  final VoidCallback? onRunAll;
  final VoidCallback? onWaitAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 114,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: config name + start/stop button.
          Row(
            children: [
              Expanded(
                child: Text(
                  configName.isEmpty ? '未选择配置' : configName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _kText,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _BulkIconButton(
                icon: Icons.bolt_rounded,
                tooltip: '全部立即运行',
                loading: bulkMode == HomeBulkQuickScheduleMode.runNow,
                onTap: onRunAll,
              ),
              const SizedBox(width: 6),
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
          // Row 2: currently running task + adjust-plan button.
          Row(
            children: [
              Expanded(
                child: Text(
                  currentTaskName.isEmpty
                      ? '暂无执行任务'
                      : currentTaskName.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: _kText2),
                ),
              ),
              const SizedBox(width: 10),
              _PillButton(
                label: '调整计划',
                primary: false,
                onTap: onAdjust,
              ),
            ],
          ),
        ],
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
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _kSurface2,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: _kBorder),
          ),
          child: loading
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _kTeal,
                  ),
                )
              : _DoubleIcon(icon: icon, color: enabled ? _kTeal : _kText3),
        ),
      ),
    );
  }
}

/// Renders two offset copies of [icon] to convey an "all" action.
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
        ? _kSurface2
        : (running ? _kRed : _kTeal);
    final foreground = !enabled
        ? _kText3
        : (running
            ? Colors.white
            : (_isDark ? const Color(0xFF04140F) : Colors.white));
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled ? background : _kBorder,
          ),
        ),
        child: Text(
          running ? '停止运行' : '立即运行',
          style: TextStyle(
            fontSize: 12,
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
          color: primary ? _kTeal : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: primary ? _kTeal : _kBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
            color: primary
                ? (_isDark ? const Color(0xFF04140F) : Colors.white)
                : _kText2,
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
              : _StatisticsColumn(theme: _statsTheme),
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
  const _StatisticsColumn({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Theme(
        data: theme,
        child: const ScriptStatisticsPanel(),
      ),
    );
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
        color: _kPanel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
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
        style: TextStyle(fontSize: 12.5, color: _kText3),
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
      DashboardTaskType.running => _kGreen,
      DashboardTaskType.pending => _kYellow,
      DashboardTaskType.waiting => _kText2,
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
