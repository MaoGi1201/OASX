import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/config/app_colors.dart';
import 'package:oasx/config/app_metrics.dart';
import 'package:oasx/modules/common/widgets/app_warning_badge.dart';
import 'package:oasx/modules/home/config_actions.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';
import 'package:oasx/modules/home/models/all_configs_filter.dart';
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
import 'package:oasx/utils/logger.dart';

part 'dashboard_home_header.dart';
part 'dashboard_home_tasks.dart';
part 'dashboard_home_overview.dart';
part 'dashboard_home_logs.dart';

// ---------------------------------------------------------------------------
// Palette: light (day) and dark (night) variants selected by the app theme.
// ---------------------------------------------------------------------------
/// 从配置卡片的链条按钮打开「全部配置」面板：只做一件事——默认勾上当前配置。
///
/// 关闭时若只勾了一个配置，等同于「不连接」，会自动断开（见 [showAllConfigsDialog]）。
Future<void> showConnectorDialog(
  BuildContext context, {
  required HomeDashboardController controller,
  required ScriptService scriptService,
  required String sourceScript,
}) {
  if (controller.validLinkedScripts.isEmpty) {
    if (!controller.isLinkModeEnabled.value) {
      controller.toggleLinkMode();
    }
    controller.setScriptLinked(sourceScript, true);
  }

  return showAllConfigsDialog(
    context,
    controller: controller,
    scriptService: scriptService,
    startInLinkMode: true,
  );
}

/// 打开「全部配置」面板：网格一览所有配置，带搜索与状态点。
///
/// [startInLinkMode] 为 true 时直接进入连接模式（显示勾选框）。
/// 关闭时统一收尾：勾选的配置不足两个就视为「不连接」，自动断开。
Future<void> showAllConfigsDialog(
  BuildContext context, {
  required HomeDashboardController controller,
  required ScriptService scriptService,
  bool startInLinkMode = false,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _AllConfigsDialog(
      controller: controller,
      scriptService: scriptService,
      startInLinkMode: startInLinkMode,
    ),
  );

  if (controller.validLinkedScripts.length < 2 &&
      controller.isLinkModeEnabled.value) {
    controller.toggleLinkMode();
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

  /// 右栏选中项（0 日志 / 1 统计）。放在这里而不是 `_RightColumn` 内部，
  /// 因为主题切换会重挂载内容区，组件内部状态会被重置。
  int _rightTab = 0;

  /// 上一次的宽窄屏判定，用于在跨越 900px 时同步统计面板的可见性。
  bool? _lastCompact;

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
    // 统计页（窄屏最后一页 / 宽屏右栏「统计」）离开仪表盘时要关掉可见性，
    // 否则统计 controller 会在后台一直轮询。
    _controller.setStatsPanelVisible(false);
    _scriptWorker?.dispose();
    _clockTimer?.cancel();
    super.dispose();
  }

  /// 切换右栏的日志 / 统计。统计 controller 只在面板可见时拉数据。
  void _selectRightTab(int index) {
    if (_rightTab == index) {
      return;
    }
    setState(() => _rightTab = index);
    _controller.setStatsPanelVisible(index == 1);
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
      if (args == null) {
        return;
      }
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
    // 读 Theme 而不是 AppColors：AppColors 是全局静态取色，不产生依赖，
    // 主题切换时整块仪表盘（日志、统计等大量用 AppColors/Get.isDarkMode 的
    // 子组件）不会重建，就会停留在旧配色上。
    final brightness = Theme.of(context).brightness;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Obx(() {
        final script = _controller.activeScriptModel;
        final scriptName = _controller.activeScriptName.value.trim();
        // Material / Card 内部对颜色做 200ms 补间，主题切换时会先闪一下旧色。
        // 只让「内容区」换 key 重挂载（header 保持常驻，否则悬停中的 Tooltip
        // 会变成孤儿浮层一直停在屏幕上）。
        return LayoutBuilder(
          builder: (context, constraints) {
            // Phones / narrow windows show one page at a time.
            final compact = constraints.maxWidth < 900;
            // 宽屏看右栏 tab、窄屏看页签，跨过 900px 时统计页是否可见会变。
            // 不能在 build 里直接写 Rx，推到帧后补一次同步。
            if (_lastCompact != compact) {
              _lastCompact = compact;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) {
                  return;
                }
                _controller.setStatsPanelVisible(
                  compact ? _mobilePageIndex == 3 : _rightTab == 1,
                );
              });
            }
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
                  child: KeyedSubtree(
                    key: ValueKey<Brightness>(brightness),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                      child: compact
                          ? _buildCompactBody(script, scriptName)
                          : _buildWideBody(script, scriptName),
                    ),
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
        const SizedBox(width: AppGap.m),
        // 中：任务日期分布 + 任务列表
        Expanded(flex: 11, child: _buildTasksColumn(script)),
        const SizedBox(width: AppGap.m),
        // 右：日志 / 统计（点击切换）
        Expanded(
          flex: 10,
          child: _RightColumn(
            scriptName: scriptName,
            tab: _rightTab,
            onSelectTab: _selectRightTab,
          ),
        ),
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
            _ => _StatisticsColumn(Theme.of(context).brightness),
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
