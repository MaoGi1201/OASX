part of 'dashboard_home.dart';

// ---------------------------------------------------------------------------
// Tasks column: day distribution, task catalog and task rows.
// ---------------------------------------------------------------------------

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

  /// 工具栏刷新：重新拉一次 schedule，WS 推送延迟时也能手动同步任务列表。
  void _refreshSchedule() {
    final script = widget.script;
    if (script == null) {
      return;
    }
    Get.find<ScriptService>().wsService.send(script.name, 'get_schedule');
    showToast('已刷新', '任务列表');
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
      // 刚被取消的任务先从列表里拿掉：取消配置里最后一个启用任务后，
      // 后端的 get_next() 会抛 RequestHumanTakeover 把 WS 连接掐断，
      // 前端再也收不到新的 schedule，只能按本地操作结果即时生效。
      // 记录放在 controller 里，任务目录的勾选状态用的是同一份数据。
      final disabledTasks = script == null
          ? const <String>{}
          : widget.controller.locallyDisabledTaskNames[script.name] ??
              const <String>{};
      // 后端若又把它排进 pending/waiting，说明确实重新启用了，恢复显示。
      final liveNames = <String>{
        ...?script?.pendingTaskList.map((task) => task.taskName.value.trim()),
        ...?script?.waitingTaskList.map((task) => task.taskName.value.trim()),
      };
      final allEntries = _collectTasks(script)
          .where(
            (entry) =>
                !disabledTasks.contains(entry.name) ||
                liveNames.contains(entry.name),
          )
          .toList(growable: false);
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
                    onRefresh: script == null ? null : _refreshSchedule,
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
                                          if (!mounted) return;
                                          if (!ok) {
                                            showToast(
                                              '操作失败',
                                              '$taskName 未能立即执行',
                                            );
                                            return;
                                          }
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
                                          if (!mounted) return;
                                          if (!ok) {
                                            showToast(
                                              '操作失败',
                                              '$taskName 未能延后',
                                            );
                                            return;
                                          }
                                          setState(() {
                                            _appliedActions[
                                                    _appliedKey(taskName)] =
                                                _QuickAction.wait;
                                          });
                                          showToast(
                                            '已延后',
                                            taskName.tr,
                                          );
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
              const SizedBox(width: AppGap.m),
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
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  onTap: onRefresh,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(AppRadius.button),
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
                borderRadius: BorderRadius.circular(AppRadius.button),
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
      borderRadius: BorderRadius.circular(AppRadius.button),
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
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
    this.scriptName = '',
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

  /// 当前配置名；切换配置时「立即执行 / 已延后」标记属于上一个配置，必须清掉。
  final String scriptName;
  final Future<void> Function(String task, bool enable)? onToggleEnabled;
  final Future<bool> Function(String task)? onQuickRun;
  final Future<bool> Function(String task)? onQuickWait;
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
    // 配置停下或换了一个配置后，之前的「立即执行 / 已延后」高亮都失效了。
    if ((oldWidget.scriptRunning && !widget.scriptRunning) ||
        oldWidget.scriptName != widget.scriptName) {
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
              final ok = await widget.onQuickRun!(task);
              if (!mounted) return;
              // 只有真的执行成功才染绿，否则会和任务列表的行为不一致。
              setState(() {
                if (ok) {
                  _applied[task] = _QuickAction.run;
                } else {
                  _applied.remove(task);
                }
              });
            },
      onWait: !schedulable || widget.onQuickWait == null
          ? null
          : () async {
              final ok = await widget.onQuickWait!(task);
              if (!mounted) return;
              setState(() {
                if (ok) {
                  _applied[task] = _QuickAction.wait;
                } else {
                  _applied.remove(task);
                }
              });
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
      borderRadius: BorderRadius.circular(AppRadius.button),
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
      borderRadius: BorderRadius.circular(AppRadius.button),
      onTap: onOpen,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: enabled ? AppColors.teal.withValues(alpha: 0.10) : AppColors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.button),
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
                  onTap: _dismissingTooltipTap(onToggleEnabled),
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
            const SizedBox(width: AppGap.xs),
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
          onTap: _dismissingTooltipTap(onTap),
          // 18×18 的可点区夹在「整格 = 打开参数」里面，偏几像素就会弹出
          // 参数窗。用 padding 把命中区撑到 26×26，两个图标也因此隔开。
          child: Padding(
            padding: const EdgeInsets.all(6.5),
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
        borderRadius: BorderRadius.circular(AppRadius.card),
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
                    borderRadius: BorderRadius.circular(AppRadius.button),
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
                            borderRadius: BorderRadius.circular(AppRadius.button),
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
      decoration: BoxDecoration(
        color: selected ? AppColors.selectedBg : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.menu),
        border: Border.all(
          color: selected ? AppColors.selectedBorder : Colors.transparent,
        ),
      ),
      // 选中色条用 Stack 叠在左侧留白上，不参与 Row 的布局：
      // 之前它是条件插入的 SizedBox(width: 2 + right: 8)，一选中整行内容
      // 就往右跳 10px，勾选圆点、时间、任务名全都跟着移位。
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Tooltip(
                  message: locked ? '任务执行中，无法取消' : '已启用（点击取消）',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: _dismissingTooltipTap(onToggleEnabled),
                    // 图标只有 15px，直接当命中区意味着偏 1-2px 就完全没
                    // 反应；padding 把可点范围撑到 25×25 而不改图标大小。
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 15,
                        color: locked ? AppColors.green : AppColors.teal,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 3),
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
                            style: TextStyle(
                              fontSize: 10.5,
                              color: AppColors.green,
                            ),
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
                  color: appliedAction == _QuickAction.run
                      ? AppColors.teal
                      : AppColors.text3,
                  onTap: onRun,
                  filled: true,
                ),
                _RowIconButton(
                  icon: Icons.schedule_rounded,
                  tooltip: I18n.homeQuickWait.tr,
                  color: appliedAction == _QuickAction.wait
                      ? AppColors.blue
                      : AppColors.text3,
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
          ),
          if (selected)
            Positioned(
              left: 4,
              top: 13,
              child: Container(
                width: 2,
                height: 18,
                decoration: BoxDecoration(
                  color: AppColors.teal,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
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
        borderRadius: BorderRadius.circular(AppRadius.button),
        onTap: _dismissingTooltipTap(onTap),
        child: filled
            ? Container(
                width: AppSize.iconButton,
                height: AppSize.iconButton,
                margin: const EdgeInsets.only(left: 3),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
                child: iconWidget,
              )
            : SizedBox(width: 22, height: 22, child: iconWidget),
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
