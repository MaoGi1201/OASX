part of 'dashboard_home.dart';

// ---------------------------------------------------------------------------
// Right column: logs / statistics switch, panel chrome and empty hint.
// ---------------------------------------------------------------------------

/// Log center view of the right column.
class _LogsColumn extends StatelessWidget {
  const _LogsColumn({required this.scriptName});

  final String scriptName;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: scriptName.isEmpty
          // ignore: prefer_const_constructors
          ? _Panel(child: const _EmptyHint(label: '请选择脚本'))
          : LogCenterPanel(scriptName: scriptName),
    );
  }
}

// ---------------------------------------------------------------------------
// Column 3: log / statistics switch
// ---------------------------------------------------------------------------
/// Right column: the log center and the statistics view share this space,
/// switched by the two chips on top.
///
/// 选中项由父级 `_DashboardHomeState` 持有，而不是本组件的 State：
/// 主题切换时内容区外面那层 `KeyedSubtree` 会换 key 重挂载整棵树，
/// 状态放在这里会被丢掉，页面就自己跳回日志。
class _RightColumn extends StatelessWidget {
  const _RightColumn({
    required this.scriptName,
    required this.tab,
    required this.onSelectTab,
  });

  final String scriptName;

  /// 0 = 日志，1 = 统计。
  final int tab;

  final ValueChanged<int> onSelectTab;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            _TaskViewChip(
              label: '日志',
              selected: tab == 0,
              onTap: () => onSelectTab(0),
            ),
            const SizedBox(width: 8),
            _TaskViewChip(
              label: '统计',
              selected: tab == 1,
              onTap: () => onSelectTab(1),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: tab == 0
              ? _LogsColumn(scriptName: scriptName)
              : _StatisticsColumn(Theme.of(context).brightness),
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
  const _StatisticsColumn(this.brightness);

  /// 只用于让本组件在深/浅色切换时重建（内部大量取色是静态的）。
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    // 不用 const：主题切换后需要重新构建，_Panel 才会取到新配色。
    // ignore: prefer_const_constructors
    return _Panel(child: const ScriptStatisticsPanel());
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
        borderRadius: BorderRadius.circular(AppRadius.card),
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
