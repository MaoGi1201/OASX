import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/modules/home/models/dashboard_task_helpers.dart';
import 'package:oasx/modules/home/models/taskitem_model.dart';

void main() {
  group('parseDashboardTaskTime', () {
    test('parses space separated datetime', () {
      final dt = parseDashboardTaskTime('2026-10-21 13:36:34');
      expect(dt, isNotNull);
      expect(dt!.year, 2026);
      expect(dt.month, 10);
      expect(dt.day, 21);
      expect(dt.hour, 13);
      expect(dt.minute, 36);
    });

    test('returns null for empty or garbage', () {
      expect(parseDashboardTaskTime(''), isNull);
      expect(parseDashboardTaskTime('   '), isNull);
      expect(parseDashboardTaskTime('not-a-date'), isNull);
    });
  });

  group('formatHhMm', () {
    test('pads hour and minute', () {
      expect(formatHhMm(DateTime(2026, 10, 21, 9, 5)), '09:05');
      expect(formatHhMm(DateTime(2026, 10, 21, 23, 55)), '23:55');
    });
  });

  group('collectDashboardTasks', () {
    test('running first then pending sorted by time', () {
      final tasks = <TaskItemModel>[
        TaskItemModel('CDB', '突破', '2026-10-21 15:00:00'),
        TaskItemModel('CDB', '道馆', '2026-10-21 13:00:00'),
        TaskItemModel('CDB', '', '2026-10-21 12:00:00'),
      ];
      final entries = collectDashboardTasks(
        runningTaskName: '结界踏卡',
        pendingTasks: tasks,
      );
      expect(entries.length, 3);
      expect(entries[0].name, '结界踏卡');
      expect(entries[0].timeText, '运行中');
      expect(entries[1].name, '道馆');
      expect(entries[1].timeText, '13:00');
      expect(entries[2].name, '突破');
      expect(entries[2].timeText, '15:00');
    });

    test('unparseable time falls back to --:--', () {
      final entries = collectDashboardTasks(
        runningTaskName: '',
        pendingTasks: <TaskItemModel>[
          TaskItemModel('CDB', '资产更新', ''),
        ],
      );
      expect(entries.single.timeText, '--:--');
      expect(entries.single.time, isNull);
    });

    test('merges waiting tasks into the sorted list', () {
      final entries = collectDashboardTasks(
        runningTaskName: '',
        pendingTasks: <TaskItemModel>[
          TaskItemModel('CDB', 'Overdue', '2026-10-07 01:40:08'),
        ],
        waitingTasks: <TaskItemModel>[
          TaskItemModel('CDB', 'Tonight', '2026-10-21 19:28:58'),
        ],
      );
      expect(entries.length, 2);
      expect(entries[0].name, 'Overdue');
      expect(entries[1].name, 'Tonight');
      expect(entries[1].timeText, '19:28');
    });

    test('empty input returns empty list', () {
      expect(
        collectDashboardTasks(
          runningTaskName: '',
          pendingTasks: const <TaskItemModel>[],
        ),
        isEmpty,
      );
    });
  });

  group('buildDashboardDayCounts', () {
    test('buckets tasks across today plus next seven days', () {
      final now = DateTime(2026, 10, 21, 12);
      final entries = <DashboardTaskEntry>[
        DashboardTaskEntry(
          name: 'a',
          timeText: '13:00',
          time: DateTime(2026, 10, 21, 13),
        ),
        DashboardTaskEntry(
          name: 'b',
          timeText: '14:00',
          time: DateTime(2026, 10, 21, 14),
        ),
        DashboardTaskEntry(
          name: 'c',
          timeText: '13:00',
          time: DateTime(2026, 10, 22, 13),
        ),
        DashboardTaskEntry(
          name: 'd',
          timeText: '13:00',
          time: DateTime(2026, 10, 30, 13),
        ),
        const DashboardTaskEntry(name: 'e', timeText: '运行中'),
      ];
      final days = buildDashboardDayCounts(entries, now: now);
      expect(days.length, 8);
      expect(days[0].label, '今天');
      expect(days[0].today, isTrue);
      expect(days[0].count, 2);
      expect(days[1].label, '周四');
      expect(days[1].count, 1);
      final total = days.fold<int>(0, (sum, day) => sum + day.count);
      expect(total, 3);
    });

    test('overdue tasks count toward today', () {
      final now = DateTime(2026, 10, 21, 12);
      final entries = <DashboardTaskEntry>[
        DashboardTaskEntry(
          name: 'overdue',
          timeText: '13:00',
          time: DateTime(2026, 10, 20, 13),
        ),
        DashboardTaskEntry(
          name: 'today',
          timeText: '15:00',
          time: DateTime(2026, 10, 21, 15),
        ),
      ];
      final days = buildDashboardDayCounts(entries, now: now);
      // Quick-run moves next_run to yesterday; it must still land in "今天".
      expect(days[0].count, 2);
    });
  });
}
