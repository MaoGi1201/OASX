import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/config/app_colors.dart';
import 'package:oasx/config/app_metrics.dart';
import 'package:oasx/modules/home/models/script_statistics_models.dart';
import 'package:oasx/modules/home/widgets/statistics_history_axis_layout.dart';
import 'package:oasx/modules/home/widgets/statistics_formatters.dart';
import 'package:oasx/translation/i18n_content.dart';

const _kHistoryLeadWidth = 3.0;
const _kHistoryLeadGap = 5.0;
const _kHistoryTaskLabelWidth = 90.0;
const _kHistoryTaskLabelSpacing = 8.0;
const _kHistoryAxisSpacing = 6.0;
const _kHistoryAxisHeaderHeight = 26.0;
const _kHistoryAxisLeadingWidth =
    _kHistoryLeadWidth + _kHistoryLeadGap + _kHistoryTaskLabelWidth + _kHistoryTaskLabelSpacing;
const _kHistoryRowHeight = 34.0;
const _kHistoryRowSpacing = 4.0;
const _kCollapsedTaskCount = 9;
const _kHistoryToggleHeight = 26.0;

/// Task comparison chart with a fixed top axis.
///
/// Only the first [_kCollapsedTaskCount] rows are drawn by default and the rest
/// fold behind one toggle: a 34px row list inside a narrow column is awkward to
/// scroll, and the tasks below the fold are usually the ones with almost no
/// runtime anyway.
class ScriptStatisticsHistoryChart extends StatefulWidget {
  /// Creates a task comparison chart.
  const ScriptStatisticsHistoryChart({
    super.key,
    required this.entries,
    required this.metric,
    required this.focusedTaskName,
    required this.onSelectTask,
    required this.flashingTaskName,
    required this.flashToken,
    required this.highlightRealtimeTask,
  });

  /// Task aggregates sorted by the selected metric.
  final List<MapEntry<String, ScriptTaskStatistics>> entries;

  /// Metric currently shown by the chart.
  final ScriptStatisticsChartMetric metric;

  /// Currently focused task name.
  final String focusedTaskName;

  /// Called when the user taps a task bar.
  final ValueChanged<String> onSelectTask;

  /// Task currently highlighted by a realtime update.
  final String flashingTaskName;

  /// Token used to restart the flash animation.
  final int flashToken;

  /// Whether realtime task highlighting is active.
  final bool highlightRealtimeTask;

  @override
  State<ScriptStatisticsHistoryChart> createState() =>
      _ScriptStatisticsHistoryChartState();
}

class _ScriptStatisticsHistoryChartState
    extends State<ScriptStatisticsHistoryChart> {
  /// Whether rows beyond the collapsed count are visible.
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant ScriptStatisticsHistoryChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 焦点任务被折叠起来时自动展开，否则点明细里选中的任务在图上找不到高亮。
    if (oldWidget.focusedTaskName != widget.focusedTaskName) {
      final index = widget.entries.indexWhere(
        (entry) => entry.key == widget.focusedTaskName,
      );
      if (index >= _kCollapsedTaskCount) {
        _expanded = true;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
    // 轴范围按全部任务计算，折叠/展开时柱长不跳动。
    final maxValue = entries.fold<double>(
      0,
      (current, entry) =>
          math.max(current, entry.value.metricValueFor(widget.metric)).toDouble(),
    );
    final interval = _resolveInterval(maxValue);
    final axisMax = _resolveAxisMax(maxValue, interval);
    final ticks = _buildTicks(axisMax, interval);
    final visibleEntries = _expanded
        ? entries
        : entries.take(_kCollapsedTaskCount).toList(growable: false);
    final hiddenCount = entries.length - visibleEntries.length;
    // 图表更新频繁，单独隔离重绘，避免连带整页重排。
    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HistoryAxisHeader(
            ticks: ticks,
            axisMax: axisMax,
            metric: widget.metric,
          ),
          const SizedBox(height: _kHistoryAxisSpacing),
          for (var index = 0; index < visibleEntries.length; index++) ...[
            if (index > 0) const SizedBox(height: _kHistoryRowSpacing),
            _HistoryBarRow(
              entry: visibleEntries[index],
              metric: widget.metric,
              axisMax: axisMax,
              focused: visibleEntries[index].key == widget.focusedTaskName,
              flashing: widget.highlightRealtimeTask &&
                  widget.flashingTaskName == visibleEntries[index].key,
              flashToken: widget.flashToken,
              onTap: () => widget.onSelectTask(visibleEntries[index].key),
            ),
          ],
          if (hiddenCount > 0 || _expanded)
            _HistoryToggle(
              label: _expanded
                  ? I18n.homeStatsCollapse.tr
                  : I18n.homeStatsExpandMoreTasks.tr.replaceFirst(
                      '%s',
                      '$hiddenCount',
                    ),
              onTap: () => setState(() => _expanded = !_expanded),
            ),
        ],
      ),
    );
  }

  /// Builds fixed axis ticks using the resolved interval.
  List<double> _buildTicks(double axisMax, double interval) {
    final ticks = <double>[0];
    var cursor = interval;
    while (cursor <= axisMax) {
      ticks.add(cursor);
      cursor += interval;
    }
    return ticks;
  }

  /// Resolves the chart max to the next interval step.
  double _resolveAxisMax(double maxValue, double interval) {
    if (interval <= 0) {
      return 1.0;
    }
    return math
        .max(interval, (maxValue / interval).ceil() * interval)
        .toDouble();
  }

  /// Resolves a stable axis interval for the current metric family.
  double _resolveInterval(double maxValue) {
    if (statisticsMetricUsesDuration(widget.metric)) {
      if (maxValue <= 600) {
        return 120.0;
      }
      if (maxValue <= 3600) {
        return 600.0;
      }
      if (maxValue <= 4 * 3600) {
        return 1800.0;
      }
      return 3600.0;
    }
    if (maxValue <= 10) {
      return 2.0;
    }
    if (maxValue <= 50) {
      return 10.0;
    }
    if (maxValue <= 100) {
      return 20.0;
    }
    return math.max((maxValue / 5).ceilToDouble(), 1.0).toDouble();
  }
}

class _HistoryToggle extends StatelessWidget {
  const _HistoryToggle({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.button),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.button),
        onTap: onTap,
        child: SizedBox(
          height: _kHistoryToggleHeight,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppColors.teal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryAxisHeader extends StatelessWidget {
  const _HistoryAxisHeader({
    required this.ticks,
    required this.axisMax,
    required this.metric,
  });

  final List<double> ticks;
  final double axisMax;
  final ScriptStatisticsChartMetric metric;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    return Row(
      children: [
        const SizedBox(width: _kHistoryAxisLeadingWidth),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final visibleTickLayouts = resolveStatisticsHistoryAxisLabels(
                ticks: ticks,
                labels: ticks
                    .map((tick) => formatStatisticsMetricByType(tick, metric))
                    .toList(growable: false),
                axisMax: axisMax,
                availableWidth: width,
                style: labelStyle,
                textDirection: Directionality.of(context),
              );
              return SizedBox(
                height: _kHistoryAxisHeaderHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 1,
                        color: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withValues(alpha: 0.7),
                      ),
                    ),
                    ...visibleTickLayouts.map((layout) {
                      return Positioned(
                        left: layout.left,
                        child: SizedBox(
                          width: layout.width,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              layout.label,
                              textAlign: TextAlign.center,
                              style: labelStyle,
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HistoryBarRow extends StatelessWidget {
  const _HistoryBarRow({
    required this.entry,
    required this.metric,
    required this.axisMax,
    required this.focused,
    required this.flashing,
    required this.flashToken,
    required this.onTap,
  });

  final MapEntry<String, ScriptTaskStatistics> entry;
  final ScriptStatisticsChartMetric metric;
  final double axisMax;
  final bool focused;
  final bool flashing;
  final int flashToken;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = statisticsTaskColor(entry.key);
    final value = entry.value.metricValueFor(metric);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: _kHistoryLeadWidth,
          child: focused
              ? Container(
                  width: 2,
                  height: 16,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                )
              : null,
        ),
        const SizedBox(width: _kHistoryLeadGap),
        SizedBox(
          width: _kHistoryTaskLabelWidth,
          child: Text(
            entry.key.tr,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.15,
              color: focused ? color : AppColors.text2,
              fontWeight: focused ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: _kHistoryTaskLabelSpacing),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final ratio = axisMax <= 0 ? 0.0 : value / axisMax;
              final barWidth =
                  math.max(constraints.maxWidth * ratio, 8.0).toDouble();
              final scheme = Theme.of(context).colorScheme;
              return Tooltip(
                preferBelow: false,
                verticalOffset: 20,
                message: _tooltipText(),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  onTap: onTap,
                  child: SizedBox(
                    height: _kHistoryRowHeight,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Container(
                          height: 14,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        // 普通 Container：每根柱子各带一个隐式动画时，数据一更新
                        // 会同时启动 N 条动画（30 天 = 30 条），是掉帧的主要来源。
                        Container(
                          width: barWidth,
                          height: focused ? 20 : 16,
                          decoration: BoxDecoration(
                            color:
                                color.withValues(alpha: focused ? 0.92 : 0.76),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: focused ? scheme.onSurface : color,
                              width: focused ? 1.3 : 1,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          child: _HistoryValueBadge(
                            label: formatStatisticsMetricByType(value, metric),
                            color: color,
                            flashing: flashing,
                            flashToken: flashToken,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Builds tooltip lines without repeating the task name.
  String _tooltipText() {
    return '${I18n.homeStatsTotalDuration.tr}: '
        '${formatStatisticsDuration(entry.value.totalDurationSeconds)}\n'
        '${I18n.homeStatsRunCount.tr}: ${entry.value.runCount}\n'
        '${I18n.homeStatsBattleCount.tr}: ${entry.value.battleCount}\n'
        '${I18n.homeStatsBattleAvgDuration.tr}: '
        '${formatStatisticsDuration(entry.value.battleAvgDurationSeconds)}\n'
        '${I18n.homeStatsAvgRunDuration.tr}: '
        '${formatStatisticsDuration(entry.value.avgRunDurationSeconds)}';
  }
}

class _HistoryValueBadge extends StatelessWidget {
  const _HistoryValueBadge({
    required this.label,
    required this.color,
    required this.flashing,
    required this.flashToken,
  });

  final String label;
  final Color color;
  final bool flashing;
  final int flashToken;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      key: ValueKey('$label|$flashToken|$flashing'),
      tween: Tween<double>(begin: flashing ? 1 : 0, end: 0),
      duration: Duration(milliseconds: flashing ? 1300 : 180),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final pulse = flashing ? value : 0.0;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Color.lerp(
              Colors.transparent,
              color.withValues(alpha: 0.18),
              pulse,
            ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Color.lerp(
                    Colors.transparent,
                    color.withValues(alpha: 0.56),
                    pulse,
                  ) ??
                  Colors.transparent,
            ),
            boxShadow: pulse > 0
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.26 * pulse),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : const [],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: pulse > 0.02 ? scheme.onSurface : AppColors.text2,
              ),
            ),
          ),
        );
      },
    );
  }
}
