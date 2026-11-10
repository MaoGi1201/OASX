import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/config/app_colors.dart';
import 'package:oasx/modules/home/models/script_statistics_models.dart';
import 'package:oasx/modules/home/widgets/statistics_formatters.dart';
import 'package:oasx/translation/i18n_content.dart';

const _kTrackCellGap = 1.0;
const _kTodayTrackHeight = 30.0;
const _kCompareTrackHeight = 18.0;
const _kTooltipWait = Duration(milliseconds: 350);

/// 标尺行固定高度，等于筛选徽标的高度。
///
/// 徽标是按小时筛选时才出现的；不占位的话行高会从 ~14 变成 20，整条热力图
/// 会往下窜一下。固定成徽标高度后，点选只换内容不换尺寸。
const _kTrackHeaderHeight = 20.0;

/// 透明占位徽标的空回调，避免在 build 里反复建闭包。
void _noop() {}

/// 24-hour heat tracks for the selected day, with an optional comparison day.
///
/// The widget takes plain data instead of the controller on purpose: the calls
/// that read the Rx values live in the panel's `Obx` closure, otherwise a
/// change of the selected hour would not rebuild this subtree (reads inside a
/// child's `build` do not subscribe in GetX).
class StatisticsHourTrack extends StatefulWidget {
  const StatisticsHourTrack({
    super.key,
    required this.buckets,
    required this.selectedHour,
    required this.todayCaption,
    required this.comparisonLabel,
    required this.comparisonCaption,
    required this.onToggleHour,
    required this.onClearHour,
  });

  /// 24 hourly buckets of the selected day.
  final List<StatisticsHourBucket> buckets;

  /// Hour currently used as a chart filter, null when disabled.
  final int? selectedHour;

  /// Caption under the today track label.
  final String todayCaption;

  /// Label of the comparison track, null hides the track.
  final String? comparisonLabel;

  /// Caption under the comparison track label.
  final String comparisonCaption;

  /// Called when a non-empty hour cell is tapped.
  final ValueChanged<int> onToggleHour;

  /// Called when the active hour filter is cleared.
  final VoidCallback onClearHour;

  @override
  State<StatisticsHourTrack> createState() => _StatisticsHourTrackState();
}

class _StatisticsHourTrackState extends State<StatisticsHourTrack> {
  /// Hour under the pointer; null when nothing is hovered.
  int? _hoverHour;

  @override
  Widget build(BuildContext context) {
    final buckets = widget.buckets;
    final comparisonLabel = widget.comparisonLabel;
    var maxSeconds = 0.0;
    for (final bucket in buckets) {
      maxSeconds = math.max(
        maxSeconds,
        math.max(bucket.seconds, bucket.comparisonSeconds),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HourTrack(
          label: I18n.homeStatsToday.tr,
          caption: widget.todayCaption,
          buckets: buckets,
          valueOf: (bucket) => bucket.seconds,
          maxSeconds: maxSeconds,
          height: _kTodayTrackHeight,
          fill: AppColors.teal,
          selectedHour: widget.selectedHour,
          hoveredHour: _hoverHour,
          onHoverHour: _setHoverHour,
          onTapHour: widget.onToggleHour,
          onClearFilter: widget.onClearHour,
        ),
        if (comparisonLabel != null) ...[
          const SizedBox(height: 6),
          _HourTrack(
            label: comparisonLabel,
            caption: widget.comparisonCaption,
            buckets: buckets,
            valueOf: (bucket) => bucket.comparisonSeconds,
            maxSeconds: maxSeconds,
            height: _kCompareTrackHeight,
            fill: AppColors.text3.withValues(alpha: 0.7),
            selectedHour: null,
            hoveredHour: _hoverHour,
            onHoverHour: _setHoverHour,
            dimmed: true,
          ),
        ],
        const SizedBox(height: 3),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final label in const ['00', '06', '12', '18', '24'])
              Text(
                label,
                style: TextStyle(fontSize: 9, color: AppColors.text3),
              ),
          ],
        ),
      ],
    );
  }

  /// Updates the hovered hour without rebuilding when it did not change.
  void _setHoverHour(int? hour) {
    if (_hoverHour == hour) {
      return;
    }
    setState(() => _hoverHour = hour);
  }
}

class _HourTrack extends StatelessWidget {
  const _HourTrack({
    required this.label,
    required this.caption,
    required this.buckets,
    required this.valueOf,
    required this.maxSeconds,
    required this.height,
    required this.fill,
    required this.selectedHour,
    required this.hoveredHour,
    required this.onHoverHour,
    this.onTapHour,
    this.onClearFilter,
    this.dimmed = false,
  });

  final String label;
  final String caption;
  final List<StatisticsHourBucket> buckets;
  final double Function(StatisticsHourBucket bucket) valueOf;
  final double maxSeconds;
  final double height;
  final Color fill;
  final int? selectedHour;
  final int? hoveredHour;
  final ValueChanged<int?> onHoverHour;
  final ValueChanged<int>? onTapHour;
  final VoidCallback? onClearFilter;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final hasFilter = selectedHour != null && onClearFilter != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _kTrackHeaderHeight,
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: dimmed ? AppColors.text3 : AppColors.text2,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _displayCaption(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9.5, color: AppColors.text3),
                ),
              ),
              const SizedBox(width: 6),
              // 徽标位常驻：未筛选时透明占位，宽度与筛选后完全一致，
              // 这样右侧说明文字的可用宽度也不会在点选瞬间突然收窄。
              Opacity(
                opacity: hasFilter ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !hasFilter,
                  child: _HourFilterBadge(
                    // 占位用 00 点，和真实徽标同宽（HH:00–HH:00）。
                    hour: selectedHour ?? 0,
                    onClear: onClearFilter ?? _noop,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            for (final bucket in buckets)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _kTrackCellGap,
                  ),
                  child: MouseRegion(
                    cursor: onTapHour != null && valueOf(bucket) > 0
                        ? SystemMouseCursors.click
                        : MouseCursor.defer,
                    onEnter: (_) => onHoverHour(bucket.hour),
                    onExit: (_) => onHoverHour(null),
                    child: _HourCell(
                      key: onTapHour == null
                          ? null
                          : ValueKey('stats-hour-${bucket.hour}'),
                      seconds: valueOf(bucket),
                      maxSeconds: maxSeconds,
                      height: height,
                      fill: fill,
                      selected: selectedHour == bucket.hour,
                      muted: dimmed,
                      // 空小时不可点：点了只会把图表过滤成空白。
                      onTap: onTapHour == null || valueOf(bucket) <= 0
                          ? null
                          : () => onTapHour!(bucket.hour),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Swaps the caption for the hovered hour when the pointer is over a cell.
  String _displayCaption() {
    final hour = hoveredHour;
    if (hour == null) {
      return caption;
    }
    final start = hour.toString().padLeft(2, '0');
    final end = (hour + 1).toString().padLeft(2, '0');
    final seconds = valueOf(buckets[hour]);
    final detail = seconds > 0
        ? formatStatisticsDuration(seconds)
        : I18n.homeStatsHourEmpty.tr;
    return '$start:00–$end:00 · $detail';
  }
}

class _HourFilterBadge extends StatelessWidget {
  const _HourFilterBadge({required this.hour, required this.onClear});

  final int hour;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final label = '${hour.toString().padLeft(2, '0')}:00–'
        '${(hour + 1).toString().padLeft(2, '0')}:00';
    return Tooltip(
      message: I18n.homeStatsHourFilterClear.tr,
      waitDuration: _kTooltipWait,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onClear,
        child: Container(
          height: 20,
          padding: const EdgeInsets.only(left: 8, right: 4),
          decoration: BoxDecoration(
            color: AppColors.tealDim,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.teal.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.teal,
                ),
              ),
              Icon(Icons.close_rounded, size: 12, color: AppColors.teal),
            ],
          ),
        ),
      ),
    );
  }
}

class _HourCell extends StatelessWidget {
  const _HourCell({
    super.key,
    required this.seconds,
    required this.maxSeconds,
    required this.height,
    required this.fill,
    required this.selected,
    required this.muted,
    this.onTap,
  });

  final double seconds;
  final double maxSeconds;
  final double height;
  final Color fill;
  final bool selected;
  final bool muted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasRun = seconds > 0;
    final ratio = maxSeconds <= 0 ? 0.0 : (seconds / maxSeconds).clamp(0.0, 1.0);
    final fillHeight = hasRun ? math.max(2.0, ratio * height) : 0.0;
    // 选中标识用「虚影柱」：该格背后铺一条半透明的全高绿柱，真实数据柱
    // 仍按原不透明度压在上面。比调 fill 的不透明度看得清得多，又不会像
    // 描边那样在格子边缘多出一圈、视觉上把格子压窄。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Stack(
          children: [
            if (selected)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    // 0.26 在深色底上合成约 (42,79,77)，与空格子的亮度比 1.64：
                    // 一眼能看到整列，又不会浓到被误读成真实数据（真实柱是 0.92）。
                    color: fill.withValues(alpha: 0.26),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            if (hasRun)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: fillHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: fill.withValues(alpha: muted ? 0.55 : 0.92),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
