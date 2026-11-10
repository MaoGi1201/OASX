part of 'dashboard_home.dart';

// ---------------------------------------------------------------------------
// Overview column: current-config card and its action buttons.
// ---------------------------------------------------------------------------

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
  Timer? _statsTimer;

  /// 递增的请求序号：切配置后旧请求的返回值必须丢弃。
  int _statsRequestId = 0;

  /// 请求进行中又被要求刷新（例如切了配置），等当前请求收尾后补一次。
  bool _statsPending = false;

  static const int _kTodayStatsRefreshSeconds = 60;

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

  /// 拉取当前配置「今日」的统计数字（卡片上的运行时长 / 任务次数 / 战斗场次）。
  ///
  /// 由定时器和配置切换触发，不再在 build 里调用：
  /// - 失败时不写 `_statsFetchedAt`，下一轮定时器会自然重试；
  /// - 成功才记录时间戳，避免"请求失败要等满 60 秒"。
  Future<void> _refreshTodayStats({bool force = false}) async {
    final name = widget.script?.name.trim() ?? '';
    if (name.isEmpty) {
      return;
    }
    if (_statsLoading) {
      // 上一次请求还在飞（多为刚切走的配置）：直接 return 会让新配置一直
      // 停在「--」直到 60 秒定时器，所以标记一下、等它收尾后补拉。
      _statsPending = true;
      return;
    }
    final fetchedAt = _statsFetchedAt;
    if (!force &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) <
            const Duration(seconds: _kTodayStatsRefreshSeconds)) {
      return;
    }
    _statsLoading = true;
    final requestId = ++_statsRequestId;
    try {
      final day = await ApiClient().getScriptStatisticsDay(name, _todayKey());
      if (!mounted ||
          requestId != _statsRequestId ||
          widget.script?.name.trim() != name) {
        return;
      }
      setState(() {
        _todayStats = day;
        _statsFetchedAt = DateTime.now();
      });
    } catch (error) {
      logger.e('今日统计刷新失败（$name）: $error');
    } finally {
      _statsLoading = false;
      if (mounted && _statsPending) {
        _statsPending = false;
        // 用微任务排队，避免在 finally 里递归调用。
        Future.microtask(() => _refreshTodayStats(force: true));
      }
    }
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
    _refreshTodayStats();
    _statsTimer = Timer.periodic(
      const Duration(seconds: _kTodayStatsRefreshSeconds),
      (_) => _refreshTodayStats(),
    );
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
    _statsTimer?.cancel();
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
      // 上一个配置的搜索词留在这里只会显示「未找到匹配任务」。
      if (_searchController.text.isNotEmpty) {
        _searchController.clear();
        _searchQuery = '';
      }
      _refreshTodayStats(force: true);
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

  /// 「全部立即运行 / 等待」的统一入口。
  ///
  /// 批量写入会在 5 秒后先解锁 UI，底层任务还在一个个写。这里在入口处挡掉
  /// 并发的第二批，并给用户一句反馈 —— 否则点了没反应，会被当成按钮坏了。
  Future<void> _runBulkQuickSchedule(
    HomeDashboardController controller,
    String scriptName, {
    required bool runNow,
  }) async {
    if (controller.isBulkQuickScheduleBusy) {
      showToast(I18n.tip.tr, I18n.homeBulkQuickScheduleBusy.tr);
      return;
    }
    final result = await controller.bulkQuickScheduleTasks(
      scriptName: scriptName,
      runNow: runNow,
    );
    if (!mounted) {
      return;
    }
    if (result == HomeBulkQuickScheduleResult.timedOut) {
      showToast(I18n.tip.tr, I18n.homeBulkQuickScheduleTimedOut.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final script = widget.script;    // Rebuild when the schedule or the script state changes.
    return Obx(() {
      final entries = _collectTasks(script);
      // Only the script process state tells us whether it is really running.
      // The schedule's `running` entry is stale for inactive configs, so it
      // must not be used here or every config shows a red "停止" button.
      final isRunning = script?.state.value == ScriptState.running;
      // 卡死状态要单独显示，否则胶囊和顶栏标签一个说「启动」一个说「卡死」。
      final isWarning = script?.state.value == ScriptState.warning;
      final runningTaskName = isRunning
          ? (script?.runningTask.value.taskName.value.trim() ?? '')
          : '';
      final adjustTarget = runningTaskName.isNotEmpty
          ? runningTaskName
          : (entries.isEmpty ? null : entries.first.name);
      final canToggle = script != null && script.name.trim().isNotEmpty;
      final nextTaskText = _nextTaskText(entries, runningTaskName);
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
            warning: isWarning,
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
                      scriptService: widget.scriptService,
                      sourceScript: script.name,
                    ),
            canRename: !isRunning,
            onRename: isRunning ? null : _renameScript,
            onStartStop: canToggle ? () => _toggleScript(script) : null,
            onRunAll: script == null
                ? null
                : () => _runBulkQuickSchedule(
                      controller,
                      script.name,
                      runNow: true,
                    ),
            onWaitAll: script == null
                ? null
                : () => _runBulkQuickSchedule(
                      controller,
                      script.name,
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
                      scriptName: script?.name ?? '',
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
                              showToast(
                                ok ? '立即执行' : '操作失败',
                                ok ? task.tr : '$task 未能立即执行',
                              );
                              return ok;
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
                              showToast(
                                ok ? '已延后' : '操作失败',
                                ok ? task.tr : '$task 未能延后',
                              );
                              return ok;
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

/// Top card of the middle column: shows the selected config name and a green
/// power button that starts / stops that config.
class _CurrentConfigCard extends StatelessWidget {
  const _CurrentConfigCard({
    required this.configName,
    required this.nextTaskText,
    required this.running,
    required this.warning,
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

  /// 配置进程是否在运行（决定按钮是「停止」还是「启动」）。
  final bool running;

  /// 配置是否卡死（后端 state = warning）：按钮显示黄色「重启」，与顶栏一致。
  final bool warning;

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
        borderRadius: BorderRadius.circular(AppRadius.card),
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
                              borderRadius: BorderRadius.circular(AppRadius.button),
                              onTap: canRename
                                  ? _dismissingTooltipTap(onRename)
                                  : null,
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
                      _RunButton(
                        running: running,
                        warning: warning,
                        onTap: onStartStop,
                      ),
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

/// Green rounded "启动" button: starts the config when idle, stops it when
/// running. 不叫「立即运行」——那是任务级的操作，这里是配置的启停。
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
        borderRadius: BorderRadius.circular(AppRadius.button),
        onTap: enabled ? _dismissingTooltipTap(onTap) : null,
        child: Container(
          width: AppSize.iconButton,
          height: AppSize.iconButton,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(AppRadius.button),
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
        borderRadius: BorderRadius.circular(AppRadius.button),
        onTap: _dismissingTooltipTap(onTap),
        child: Container(
          width: AppSize.iconButton,
          height: AppSize.iconButton,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: linked ? AppColors.tealDim : AppColors.surface2,
            borderRadius: BorderRadius.circular(AppRadius.button),
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

/// 配置卡右下两个按钮共用同一尺寸。
///
/// 「启动配置/停止配置/重启配置」在行 1 末尾，「调整计划」在行 2 末尾，
/// 文案都是 4 个字；两行右边界相同，再固定成同一宽高后按钮就竖直对齐了。
/// 78 = 4 字 × 12.5 + 左右各 14 的内边距，和原来的按钮内边距观感一致。
const double _kConfigActionWidth = 78;
const double _kConfigActionHeight = 30;

class _RunButton extends StatelessWidget {
  const _RunButton({
    required this.running,
    this.warning = false,
    this.onTap,
  });

  final bool running;

  /// 配置卡死（后端 state = warning）。按钮显示黄色「重启」，和顶栏配置
  /// 标签上的电源按钮同一套语义：点下去是 stop + start，不是普通启动。
  final bool warning;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    // Three states: idle = green "启动", running = red "停止",
    // warning = yellow "重启".
    final Color background;
    final Color foreground;
    if (!enabled) {
      background = AppColors.surface2;
      foreground = AppColors.text3;
    } else if (running) {
      // 深色下不用亮红 + 近黑字（两者亮度差太极端，按钮像贴上去的警示牌）；
      // 换成更深的红 + 暖白字，见 AppColors.dangerFillFor。
      background = AppColors.dangerFill;
      foreground = AppColors.onDangerFill;
    } else if (warning) {
      background = AppColors.yellow;
      // 黄色底在深浅两套主题下都用近黑字：白字对比只有 3:1 左右。
      foreground = AppColors.onWarning;
    } else {
      background = AppColors.teal;
      foreground = AppColors.onAccent;
    }
    final String label;
    if (running) {
      label = I18n.homeConfigStopLabel.tr;
    } else if (warning && enabled) {
      label = I18n.homeConfigRestartLabel.tr;
    } else {
      label = I18n.homeConfigStartLabel.tr;
    }
    // 文案已经是「启动配置/停止配置/重启配置」，语义自明，不再挂悬浮提示。
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.button),
      onTap: enabled ? onTap : null,
      child: Container(
        width: _kConfigActionWidth,
        height: _kConfigActionHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.button),
          border: Border.all(
            color: enabled ? background : AppColors.border,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
      borderRadius: BorderRadius.circular(AppRadius.button),
      onTap: onTap,
      child: Container(
        width: _kConfigActionWidth,
        height: _kConfigActionHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? AppColors.teal : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.button),
          border: Border.all(
            color: primary ? AppColors.teal : AppColors.border,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
            color: primary
                ? (AppColors.onAccent)
                : AppColors.text2,
          ),
        ),
      ),
    );
  }
}
