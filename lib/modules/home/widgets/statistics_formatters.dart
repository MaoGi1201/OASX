import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:oasx/modules/home/models/script_statistics_models.dart';
import 'package:oasx/translation/i18n_content.dart';

/// Formats seconds into a readable duration label.
String formatStatisticsDuration(double seconds) {
  if (seconds <= 0) {
    return '0s';
  }
  final rounded = seconds.round();
  final duration = Duration(seconds: rounded);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final remainingSeconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '${hours}h ${minutes}m ${remainingSeconds}s';
  }
  if (minutes > 0) {
    return '${minutes}m ${remainingSeconds}s';
  }
  return '${remainingSeconds}s';
}

/// Formats timestamps used by the statistics payload.
String formatStatisticsDateTime(DateTime? value) {
  if (value == null) {
    return '--';
  }
  return DateFormat('MM-dd HH:mm:ss').format(value);
}

/// Formats timestamps into an hour-minute label.
String formatStatisticsClockTime(DateTime? value) {
  if (value == null) {
    return '--';
  }
  return DateFormat('HH:mm').format(value);
}

/// Formats timestamps into an hour-minute-second label.
String formatStatisticsClockTimePrecise(DateTime? value) {
  if (value == null) {
    return '--';
  }
  return DateFormat('HH:mm:ss').format(value);
}

/// Formats a day key for chip labels.
String formatStatisticsDayLabel(String dayKey) {
  final value = DateTime.tryParse(dayKey);
  if (value == null) {
    return dayKey;
  }
  return DateFormat('MM-dd').format(value);
}

/// Formats generic metric values used by the historical chart.
String formatStatisticsMetricValue(double value, {bool duration = false}) {
  if (duration) {
    return formatStatisticsDuration(value);
  }
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(2);
}

/// Formats metric values according to the selected statistics metric.
String formatStatisticsMetricByType(
  double value,
  ScriptStatisticsChartMetric metric,
) {
  return formatStatisticsMetricValue(
    value,
    duration: statisticsMetricUsesDuration(metric),
  );
}

/// Formats a selected run range for the detail header.
String formatStatisticsTimeRange(DateTime? start, DateTime? end) {
  return '${formatStatisticsDateTime(start)} -> ${formatStatisticsDateTime(end)}';
}

/// Formats a selected run range using clock-only labels.
String formatStatisticsClockTimeRange(DateTime? start, DateTime? end) {
  return '${formatStatisticsClockTimePrecise(start)} -> ${formatStatisticsClockTimePrecise(end)}';
}

/// Formats a date key as 今天 / 昨天 / MM-dd for the segmented date bar.
String formatStatisticsDayChipLabel(String dateKey) {
  if (isStatisticsDateToday(dateKey)) {
    return I18n.homeStatsToday.tr;
  }
  final value = DateTime.tryParse(dateKey);
  if (value != null) {
    final now = DateTime.now();
    final yesterday =
        DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    if (value.year == yesterday.year &&
        value.month == yesterday.month &&
        value.day == yesterday.day) {
      return I18n.homeStatsYesterday.tr;
    }
  }
  return formatStatisticsDayLabel(dateKey);
}
