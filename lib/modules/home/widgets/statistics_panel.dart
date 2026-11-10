import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/config/app_colors.dart';
import 'package:oasx/config/app_metrics.dart';
import 'package:oasx/modules/common/widgets/app_popup_menu.dart';
import 'package:oasx/modules/home/controllers/statistics_controller.dart';
import 'package:oasx/modules/home/models/script_statistics_models.dart';
import 'package:oasx/modules/home/widgets/statistics_detail_section.dart';
import 'package:oasx/modules/home/widgets/statistics_formatters.dart';
import 'package:oasx/modules/home/widgets/statistics_history_chart.dart';
import 'package:oasx/modules/home/widgets/statistics_hour_track.dart';
import 'package:oasx/translation/i18n_content.dart';

const _kPanelPadding = 12.0;
const _kSectionGap = 10.0;
const _kChipGap = 5.0;
const _kTooltipWait = Duration(milliseconds: 350);

/// Main statistics tab content for the active script.
///
/// Layout is intentionally vertical and dense: the narrow right column only
/// has ~800px of usable height, so the summary is a single strip instead of a
/// grid of cards, and the bar chart is sized to show every task without
/// scrolling.
class ScriptStatisticsPanel extends StatelessWidget {
  /// Creates the statistics panel.
  const ScriptStatisticsPanel({super.key});

  /// Controller that owns statistics state.
  HomeStatisticsController get controller =>
      Get.find<HomeStatisticsController>();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final statistics = controller.statistics.value;
      final availableDates =
          controller.availableDateKeys.toList(growable: false);
      // 这些读操作必须在 Obx 闭包内：子组件 build 里读 Rx 不会建立订阅，
      // 换日期、点时段、对比日到达时都不会触发重建。
      final selectedDateKey = controller.selectedDateKey.value;
      final selectedHour = controller.selectedHour.value;
      final buckets = controller.hourlyBuckets;
      final comparison = controller.comparisonDay.value;
      final spanStart = controller.activeSpanStart;
      final spanEnd = controller.activeSpanEnd;
      final connectionState = controller.connectionState.value;
      final hasStreamError = controller.lastErrorMessage.value.isNotEmpty ||
          connectionState == ScriptStatisticsConnectionState.error;
      final metric = controller.historyMetric.value;
      final sortField = controller.historySortField.value;
      final sortDescending = controller.historySortDescending.value;
      if (statistics == null) {
        return _StatisticsPlaceholder(
          label: _placeholderLabel(),
          message: controller.lastErrorMessage.value,
          loading: _placeholderIsLoading(),
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          _kPanelPadding,
          _kSectionGap,
          _kPanelPadding,
          _kPanelPadding,
        ),
        children: [
          _DateSegmentedBar(
            availableDateKeys: availableDates,
            selectedKey: selectedDateKey,
            isToday: controller.isTodaySelected,
            connectionState: connectionState,
            hasStreamError: hasStreamError,
            onSelectDate: controller.selectHistoryDate,
          ),
          const SizedBox(height: _kSectionGap),
          _HeroBlock(statistics: statistics, controller: controller),
          const SizedBox(height: _kSectionGap),
          _SummaryStrip(statistics: statistics),
          const SizedBox(height: _kSectionGap),
          StatisticsHourTrack(
            buckets: buckets,
            selectedHour: selectedHour,
            todayCaption: spanStart == null || spanEnd == null
                ? ''
                : '${formatStatisticsClockTime(spanStart)} → '
                    '${formatStatisticsClockTime(spanEnd)} · '
                    '${formatStatisticsDuration(controller.activeSpanSeconds)}',
            comparisonLabel:
                comparison != null && comparison.runEntries.isNotEmpty
                    ? formatStatisticsDayChipLabel(comparison.dateKey)
                    : null,
            comparisonCaption: comparison == null
                ? ''
                : formatStatisticsDuration(comparison.totalRuntimeSeconds),
            onToggleHour: controller.toggleHistoryHour,
            onClearHour: controller.clearHistoryHour,
          ),
          const SizedBox(height: _kSectionGap),
          _MetricChipRow(
            controller: controller,
            metric: metric,
            sortField: sortField,
            sortDescending: sortDescending,
            allowTimeSort: controller.canSortByTime,
          ),
          const SizedBox(height: 6),
          _ChartSection(controller: controller),
        ],
      );
    });
  }

  /// Returns the placeholder title for the current controller state.
  String _placeholderLabel() {
    if (controller.datesLoading.value || controller.statisticsLoading.value) {
      return I18n.homeStatsLoadingMessage.tr;
    }
    if (controller.availableDateKeys.isEmpty) {
      return controller.lastErrorMessage.value.isEmpty
          ? I18n.homeStatsHistoryDateEmpty.tr
          : I18n.error.tr;
    }
    if (controller.isTodaySelected) {
      return switch (controller.connectionState.value) {
        ScriptStatisticsConnectionState.connecting =>
          I18n.homeStatsLoadingMessage.tr,
        ScriptStatisticsConnectionState.reconnecting =>
          I18n.homeStatsReconnecting.tr,
        ScriptStatisticsConnectionState.error => I18n.homeStatsStreamError.tr,
        _ => I18n.homeStatsWaitingSnapshot.tr,
      };
    }
    return controller.lastErrorMessage.value.isEmpty
        ? I18n.homeStatsChartEmpty.tr
        : I18n.error.tr;
  }

  /// Returns whether the placeholder should show a loading indicator.
  bool _placeholderIsLoading() {
    if (controller.datesLoading.value || controller.statisticsLoading.value) {
      return true;
    }
    return controller.isTodaySelected &&
        controller.connectionState.value !=
            ScriptStatisticsConnectionState.error &&
        controller.availableDateKeys.isNotEmpty;
  }
}

// ---------------------------------------------------------------------------
// Header: date segments + live indicator
// ---------------------------------------------------------------------------
class _DateSegmentedBar extends StatelessWidget {
  const _DateSegmentedBar({
    required this.availableDateKeys,
    required this.selectedKey,
    required this.isToday,
    required this.connectionState,
    required this.hasStreamError,
    required this.onSelectDate,
  });

  final List<String> availableDateKeys;
  final String selectedKey;
  final bool isToday;
  final ScriptStatisticsConnectionState connectionState;
  final bool hasStreamError;
  final ValueChanged<String> onSelectDate;

  @override
  Widget build(BuildContext context) {
    final head = availableDateKeys.take(2).toList(growable: false);
    final tail = availableDateKeys.skip(2).toList(growable: false);
    final selected = selectedKey;
    final selectedInTail = tail.contains(selected);
    return Row(
      children: [
        for (final key in head) ...[
          _SegmentChip(
            label: formatStatisticsDayChipLabel(key),
            selected: selected == key,
            onTap: () => onSelectDate(key),
          ),
          const SizedBox(width: _kChipGap),
        ],
        if (tail.isNotEmpty)
          _MoreDatesChip(
            // 没选具体日期时只显示「更多」：写上一个具体日期（比如 11-08）
            // 会让人以为这就是当前展示的日期，实际还要点开再选一次。
            label: selectedInTail
                ? formatStatisticsDayLabel(selected)
                : I18n.homeStatsMoreDates.tr,
            selectedKey: selectedInTail ? selected : '',
            dates: tail,
            onSelected: onSelectDate,
          ),
        const Spacer(),
        _LiveIndicator(
          isToday: isToday,
          connectionState: connectionState,
          hasStreamError: hasStreamError,
        ),
      ],
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.selected,
    this.onTap,
    this.caret = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool caret;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: 26,
          padding: EdgeInsets.only(left: 10, right: caret ? 4 : 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.tealDim : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? AppColors.teal.withValues(alpha: 0.45)
                  : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? AppColors.teal : AppColors.text2,
                ),
              ),
              if (caret)
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 16,
                  color: selected ? AppColors.teal : AppColors.text3,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreDatesChip extends StatelessWidget {
  const _MoreDatesChip({
    required this.label,
    required this.selectedKey,
    required this.dates,
    required this.onSelected,
  });

  final String label;
  final String selectedKey;
  final List<String> dates;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return _SegmentChip(
      label: label,
      selected: selectedKey.isNotEmpty,
      caret: true,
      onTap: () => _openMenu(context),
    );
  }

  /// Opens the overflow date menu anchored under this chip.
  Future<void> _openMenu(BuildContext context) async {
    final options = dates
        .map(
          (key) => AppMenuOption(
            value: key,
            label: formatStatisticsDayLabel(key),
          ),
        )
        .toList(growable: false);
    final picked = await showAppMenu<String>(
      context,
      options: options,
      selected: selectedKey,
      // 日期 chip 在右栏靠右，默认展开方向会朝左压住「昨天」，这里钉成向右。
      anchor: AppMenuAnchor.start,
    );
    if (picked != null) {
      onSelected(picked);
    }
  }
}

class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator({
    required this.isToday,
    required this.connectionState,
    required this.hasStreamError,
  });

  final bool isToday;
  final ScriptStatisticsConnectionState connectionState;
  final bool hasStreamError;

  @override
  Widget build(BuildContext context) {
    if (!isToday) {
      return const SizedBox.shrink();
    }
    final state = connectionState;
    final hasError = hasStreamError;
    final color = hasError
        ? AppColors.red
        : switch (state) {
            ScriptStatisticsConnectionState.connected => AppColors.teal,
            ScriptStatisticsConnectionState.connecting ||
            ScriptStatisticsConnectionState.reconnecting =>
              AppColors.yellow,
            _ => AppColors.text3,
          };
    final label = hasError
        ? I18n.homeStatsStreamError.tr
        : switch (state) {
            ScriptStatisticsConnectionState.reconnecting =>
              I18n.homeStatsReconnecting.tr,
            ScriptStatisticsConnectionState.connecting =>
              I18n.homeStatsLoadingMessage.tr,
            _ => I18n.homeStatsLive.tr,
          };
    return Tooltip(
      message: label,
      waitDuration: _kTooltipWait,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: AppColors.text3),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero: total runtime + effective ratio
// ---------------------------------------------------------------------------
class _HeroBlock extends StatelessWidget {
  const _HeroBlock({required this.statistics, required this.controller});

  final ScriptStatisticsDay statistics;
  final HomeStatisticsController controller;

  @override
  Widget build(BuildContext context) {
    final ratio = controller.effectiveRatio;
    final start = controller.activeSpanStart;
    final end = controller.activeSpanEnd;
    final span = controller.activeSpanSeconds;
    final caption = start == null || end == null
        ? I18n.homeStatsActiveSpan.tr
        : '${formatStatisticsClockTime(start)} → '
            '${formatStatisticsClockTime(end)} · '
            '${formatStatisticsDuration(span)}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatStatisticsDuration(statistics.totalRuntimeSeconds),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 22,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: AppColors.text3),
              ),
            ],
          ),
        ),
        if (ratio != null) ...[
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(ratio * 100).round()}%',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: AppColors.teal,
                ),
              ),
              Text(
                I18n.homeStatsEffectiveRatio.tr,
                style: TextStyle(fontSize: 9.5, color: AppColors.text3),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Summary strip: four metrics separated by hairlines
// ---------------------------------------------------------------------------
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.statistics});

  final ScriptStatisticsDay statistics;

  @override
  Widget build(BuildContext context) {
    final runCount = statistics.totalTaskRunCount;
    final avgSeconds =
        runCount == 0 ? 0.0 : statistics.totalRuntimeSeconds / runCount;
    final items = <_StripItem>[
      _StripItem(
        label: I18n.homeStatsTasks.tr,
        value: '${statistics.taskCount}',
      ),
      _StripItem(
        label: I18n.homeStatsRunCount.tr,
        value: '$runCount',
      ),
      _StripItem(
        label: I18n.homeStatsBattleShort.tr,
        value: '${statistics.totalBattleCount}',
      ),
      _StripItem(
        label: I18n.homeStatsChipAvgDuration.tr,
        value: formatStatisticsDuration(avgSeconds),
      ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0)
            Container(
              width: 1,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: AppColors.border,
            ),
          Expanded(child: _StripCell(item: items[index])),
        ],
      ],
    );
  }
}

class _StripItem {
  const _StripItem({required this.label, required this.value});

  final String label;
  final String value;
}

class _StripCell extends StatelessWidget {
  const _StripCell({required this.item});

  final _StripItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          item.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 9.5, color: AppColors.text3),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 24-hour heat tracks
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Metric chips + sort control
// ---------------------------------------------------------------------------
class _MetricChipRow extends StatelessWidget {
  const _MetricChipRow({
    required this.controller,
    required this.metric,
    required this.sortField,
    required this.sortDescending,
    required this.allowTimeSort,
  });

  final HomeStatisticsController controller;
  final ScriptStatisticsChartMetric metric;
  final ScriptStatisticsChartSortField sortField;
  final bool sortDescending;
  final bool allowTimeSort;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: _kChipGap,
            runSpacing: _kChipGap,
            children: [
              for (final option in ScriptStatisticsChartMetric.values)
                _FilterChip(
                  label: _metricLabel(option),
                  selected: metric == option,
                  onTap: () => controller.selectHistoryMetric(option),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        _SortControl(
          controller: controller,
          field: sortField,
          descending: sortDescending,
          allowTime: allowTimeSort,
        ),
      ],
    );
  }

  /// Short chip label for one chart metric.
  String _metricLabel(ScriptStatisticsChartMetric metric) {
    return switch (metric) {
      ScriptStatisticsChartMetric.totalDuration =>
        I18n.homeStatsChipDuration.tr,
      ScriptStatisticsChartMetric.runCount => I18n.homeStatsChipRunCount.tr,
      ScriptStatisticsChartMetric.battleCount =>
        I18n.homeStatsChipBattleCount.tr,
      ScriptStatisticsChartMetric.battleAvgDuration =>
        I18n.homeStatsChipBattleAvg.tr,
      ScriptStatisticsChartMetric.avgRunDuration =>
        I18n.homeStatsChipAvgDuration.tr,
    };
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.caret = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool caret;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: AppSize.chip,
          padding: EdgeInsets.only(left: 9, right: caret ? 3 : 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.tealDim : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? AppColors.teal.withValues(alpha: 0.45)
                  : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? AppColors.teal : AppColors.text2,
                ),
              ),
              if (caret)
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 15,
                  color: selected ? AppColors.teal : AppColors.text3,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortControl extends StatelessWidget {
  const _SortControl({
    required this.controller,
    required this.field,
    required this.descending,
    required this.allowTime,
  });

  final HomeStatisticsController controller;
  final ScriptStatisticsChartSortField field;
  final bool descending;
  final bool allowTime;

  @override
  Widget build(BuildContext context) {
    final resolvedField =
        field == ScriptStatisticsChartSortField.time && allowTime
            ? ScriptStatisticsChartSortField.time
            : ScriptStatisticsChartSortField.data;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FilterChip(
          label: resolvedField == ScriptStatisticsChartSortField.time
              ? I18n.homeStatsSortByTime.tr
              : I18n.homeStatsSortByData.tr,
          selected: false,
          caret: true,
          onTap: () => _openMenu(context, resolvedField, allowTime),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: controller.toggleHistorySortDirection,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              descending
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              size: 15,
              color: AppColors.text2,
            ),
          ),
        ),
      ],
    );
  }

  /// Opens the sort-field menu.
  Future<void> _openMenu(
    BuildContext context,
    ScriptStatisticsChartSortField field,
    bool allowTime,
  ) async {
    final options = <AppMenuOption<ScriptStatisticsChartSortField>>[
      AppMenuOption(
        value: ScriptStatisticsChartSortField.data,
        label: I18n.homeStatsSortByData.tr,
      ),
      if (allowTime)
        AppMenuOption(
          value: ScriptStatisticsChartSortField.time,
          label: I18n.homeStatsSortByTime.tr,
        ),
    ];
    final picked = await showAppMenu<ScriptStatisticsChartSortField>(
      context,
      options: options,
      selected: field,
      // 排序 chip 在指标行最右端，菜单朝左展开落在面板内部。
      anchor: AppMenuAnchor.end,
    );
    if (picked != null) {
      controller.selectHistorySortField(picked);
    }
  }
}

// ---------------------------------------------------------------------------
// Chart + detail
// ---------------------------------------------------------------------------
class _ChartSection extends StatelessWidget {
  const _ChartSection({required this.controller});

  final HomeStatisticsController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final loading = controller.historyChartLoading.value;
      final entries = controller.historyTaskEntries;
      final detailRuns = controller.selectedHistoryDetailRuns;
      if (entries.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Text(
            controller.selectedHour.value == null
                ? I18n.homeStatsChartEmpty.tr
                : I18n.homeStatsHourEmpty.tr,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: AppColors.text3),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 2,
            child: loading
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: const LinearProgressIndicator(minHeight: 2),
                  )
                : null,
          ),
          Opacity(
            opacity: loading ? 0.32 : 1,
            child: IgnorePointer(
              ignoring: loading,
              child: ScriptStatisticsHistoryChart(
                entries: entries,
                metric: controller.historyMetric.value,
                focusedTaskName: controller.selectedTaskName.value,
                onSelectTask: controller.selectHistoryTask,
                flashingTaskName: controller.latestUpdatedTaskName.value,
                flashToken: controller.latestUpdatedTaskPulse.value,
                highlightRealtimeTask: controller.isTodaySelected,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 10),
          ScriptStatisticsDetailSection(
            taskName: controller.selectedTaskName.value,
            runs: detailRuns,
          ),
        ],
      );
    });
  }
}

class _StatisticsPlaceholder extends StatelessWidget {
  const _StatisticsPlaceholder({
    required this.label,
    this.message = '',
    this.loading = false,
  });

  final String label;
  final String message;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading) ...[
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.6),
              ),
              const SizedBox(height: 14),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (message.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
