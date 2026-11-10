import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/config/app_colors.dart';
import 'package:oasx/config/app_metrics.dart';
import 'package:oasx/modules/home/models/script_statistics_models.dart';
import 'package:oasx/modules/home/widgets/statistics_formatters.dart';
import 'package:oasx/translation/i18n_content.dart';

/// How many runs stay visible while the detail list is collapsed.
const _kCollapsedRunCount = 4;
const _kDetailRowHeight = 26.0;
const _kDetailIndexWidth = 22.0;
const _kDetailDurationWidth = 54.0;
const _kDetailBattleWidth = 32.0;

/// Task execution detail list rendered below the chart.
///
/// The list is folded by default: four rows plus a "show more" affordance keeps
/// the panel on one screen, and the whole table is one flat block instead of a
/// card per run.
class ScriptStatisticsDetailSection extends StatefulWidget {
  /// Creates a task execution detail section.
  const ScriptStatisticsDetailSection({
    super.key,
    required this.taskName,
    required this.runs,
  });

  /// Task name currently focused by the chart.
  final String taskName;

  /// Visible run records for the focused task.
  final List<ScriptTaskRunRecord> runs;

  @override
  State<ScriptStatisticsDetailSection> createState() =>
      _ScriptStatisticsDetailSectionState();
}

class _ScriptStatisticsDetailSectionState
    extends State<ScriptStatisticsDetailSection> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant ScriptStatisticsDetailSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换任务时回到折叠态：上一个任务展开到 20 行，切过来不该把面板撑爆。
    if (oldWidget.taskName != widget.taskName) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.taskName.trim().isEmpty) {
      return _DetailPlaceholder(label: I18n.homeStatsNoTaskSelected.tr);
    }
    final runs = widget.runs;
    if (runs.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailHeader(taskName: widget.taskName, runs: runs),
          const SizedBox(height: 8),
          _DetailPlaceholder(label: I18n.homeStatsTaskDetailEmpty.tr),
        ],
      );
    }
    final visibleRuns = _expanded
        ? runs
        : runs.take(_kCollapsedRunCount).toList(growable: false);
    final hiddenCount = runs.length - visibleRuns.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DetailHeader(taskName: widget.taskName, runs: runs),
        const SizedBox(height: 6),
        _DetailColumnHeader(),
        for (var index = 0; index < visibleRuns.length; index++)
          _DetailRow(
            run: visibleRuns[index],
            color: statisticsTaskColor(widget.taskName),
            serialNumber: runs.length - index,
            showDivider: index != visibleRuns.length - 1,
          ),
        if (hiddenCount > 0 || _expanded)
          _DetailToggle(
            label: _expanded
                ? I18n.homeStatsCollapse.tr
                : I18n.homeStatsExpandRest.tr.replaceFirst(
                    '%s',
                    '$hiddenCount',
                  ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
      ],
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.taskName, required this.runs});

  final String taskName;
  final List<ScriptTaskRunRecord> runs;

  @override
  Widget build(BuildContext context) {
    final color = statisticsTaskColor(taskName);
    var battleCount = 0;
    var durationSeconds = 0.0;
    for (final run in runs) {
      battleCount += run.battleCount;
      durationSeconds += run.durationSeconds;
    }
    final avgSeconds = runs.isEmpty ? 0.0 : durationSeconds / runs.length;
    final summary = battleCount > 0
        ? '$battleCount ${I18n.homeStatsBattleShort.tr}  ·  '
            '${I18n.homeStatsChipAvgDuration.tr} '
            '${formatStatisticsDuration(avgSeconds)}'
        : formatStatisticsDuration(avgSeconds);
    return Row(
      children: [
        Container(
          width: 3,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            '${taskName.tr} · ${runs.length} ${I18n.homeStatsRunUnit.tr}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            summary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 10, color: AppColors.text3),
          ),
        ),
      ],
    );
  }
}

class _DetailColumnHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 9, color: AppColors.text3);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: _kDetailIndexWidth,
            child: Text('#', style: style),
          ),
          Expanded(child: Text(I18n.homeStatsHourFilter.tr, style: style)),
          SizedBox(
            width: _kDetailDurationWidth,
            child: Text(
              I18n.homeStatsDuration.tr,
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
          SizedBox(
            width: _kDetailBattleWidth,
            child: Text(
              I18n.homeStatsBattleShort.tr,
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.run,
    required this.color,
    required this.serialNumber,
    required this.showDivider,
  });

  final ScriptTaskRunRecord run;
  final Color color;
  final int serialNumber;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kDetailRowHeight,
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                bottom: BorderSide(
                  color: AppColors.border.withValues(alpha: 0.55),
                ),
              )
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: _kDetailIndexWidth,
            child: Text(
              '$serialNumber',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color.withValues(alpha: 0.9),
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${formatStatisticsClockTime(run.startTime)} → '
              '${formatStatisticsClockTime(run.endTime)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.text2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(
            width: _kDetailDurationWidth,
            child: Text(
              formatStatisticsDuration(run.durationSeconds),
              textAlign: TextAlign.right,
              maxLines: 1,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(
            width: _kDetailBattleWidth,
            child: Text(
              run.battleCount > 0 ? '${run.battleCount}' : '–',
              textAlign: TextAlign.right,
              maxLines: 1,
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.text3,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailToggle extends StatelessWidget {
  const _DetailToggle({required this.label, required this.onTap});

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
          height: 26,
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

class _DetailPlaceholder extends StatelessWidget {
  const _DetailPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.menu),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: AppColors.text3),
      ),
    );
  }
}
