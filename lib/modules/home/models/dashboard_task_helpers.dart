import 'package:oasx/modules/home/models/taskitem_model.dart';

/// Task type shown by the row's status icon.
enum DashboardTaskType { running, pending, waiting }

/// One row rendered in the dashboard task list.
class DashboardTaskEntry {
  const DashboardTaskEntry({
    required this.name,
    required this.timeText,
    this.type = DashboardTaskType.pending,
    this.time,
  });

  /// Task display name.
  final String name;

  /// Text shown in the time column (e.g. `13:36` or `运行中`).
  final String timeText;

  /// Running / pending / waiting, used for the status icon.
  final DashboardTaskType type;

  /// Parsed next-run time, null for the currently running task.
  final DateTime? time;
}

/// One day bucket in the dashboard date-distribution card.
class DashboardDayCount {
  const DashboardDayCount({
    required this.label,
    required this.count,
    required this.today,
  });

  /// Day label (`今天` or a weekday name).
  final String label;

  /// Number of tasks scheduled on that day.
  final int count;

  /// Whether this bucket represents today.
  final bool today;
}

const List<String> _kWeekdayLabels = <String>[
  '周一',
  '周二',
  '周三',
  '周四',
  '周五',
  '周六',
  '周日',
];

/// Collects the dashboard task list: the running task first, then the backend's
/// `pending` and `waiting` arrays **in the order the server sent them**.
///
/// The queue order is decided by the backend alone:
/// - `schedule_rule = Filter` (OAS default) sorts `pending` by the fixed
///   `ConfigManual.SCHEDULER_PRIORITY` table, so `next_run` does not decide who
///   runs first;
/// - `FIFO` sorts `pending` by `next_run`;
/// - `waiting` is always sorted by `next_run` on the server.
///
/// Re-sorting `pending` locally by time makes the first row disagree with the
/// task the script will actually start, so keep the server order and only merge
/// the two arrays. Same contract as the built-in OAS GUI (`Overview.qml`
/// appends both arrays verbatim).
///
/// The OAS schedule splits tasks into `pending` (already due / overdue) and
/// `waiting` (scheduled for later). Today's tasks usually live in `waiting`, so
/// both lists must be merged or the day list looks empty.
List<DashboardTaskEntry> collectDashboardTasks({
  required String runningTaskName,
  required List<TaskItemModel> pendingTasks,
  List<TaskItemModel> waitingTasks = const <TaskItemModel>[],
}) {
  final entries = <DashboardTaskEntry>[];
  final running = runningTaskName.trim();
  if (running.isNotEmpty) {
    entries.add(
      DashboardTaskEntry(
        name: running,
        timeText: '运行中',
        type: DashboardTaskType.running,
      ),
    );
  }
  void addTasks(List<TaskItemModel> tasks, DashboardTaskType type) {
    for (final task in tasks) {
      final name = task.taskName.value.trim();
      if (name.isEmpty) {
        continue;
      }
      final time = parseDashboardTaskTime(task.nextRun.value);
      entries.add(
        DashboardTaskEntry(
          name: name,
          time: time,
          timeText: time == null ? '--:--' : formatHhMm(time),
          type: type,
        ),
      );
    }
  }

  addTasks(pendingTasks, DashboardTaskType.pending);
  addTasks(waitingTasks, DashboardTaskType.waiting);
  return entries;
}

/// Builds the eight day buckets (today + next seven days) for the distribution
/// card. [now] is injectable for deterministic tests.
List<DashboardDayCount> buildDashboardDayCounts(
  List<DashboardTaskEntry> entries, {
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  final days = List<DateTime>.generate(
    8,
    (index) => today.add(Duration(days: index)),
  );
  final counts = List<int>.filled(days.length, 0);
  for (final entry in entries) {
    final time = entry.time;
    if (time == null) {
      // 「运行中」的条目没有 next_run（timeText 是「运行中」），
      // 时间解析失败的条目也一样。这跟 _filterEntriesForDay 的口径保持一致：
      // 它们只出现在「今天」页，所以计数也必须落在今天，
      // 否则只剩一个任务在跑时「今天」会显示 0。
      counts[0]++;
      continue;
    }
    final day = DateTime(time.year, time.month, time.day);
    // Overdue tasks belong to today's bucket so the "今天" count matches the
    // task list (quick-run sets next_run to yesterday).
    final index = day.isAfter(today)
        ? days.indexWhere((candidate) => candidate == day)
        : 0;
    if (index >= 0) {
      counts[index]++;
    }
  }
  return List<DashboardDayCount>.generate(days.length, (index) {
    return DashboardDayCount(
      label: index == 0 ? '今天' : _kWeekdayLabels[days[index].weekday - 1],
      count: counts[index],
      today: index == 0,
    );
  });
}

/// Parses a backend `next_run` string (e.g. `2026-10-21 13:36:34`).
DateTime? parseDashboardTaskTime(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return null;
  }
  return DateTime.tryParse(text) ??
      DateTime.tryParse(text.replaceFirst(' ', 'T'));
}

/// Formats a time as `HH:mm`.
String formatHhMm(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
