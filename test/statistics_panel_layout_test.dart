import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:oasx/modules/home/models/script_statistics_models.dart';
import 'package:oasx/modules/home/widgets/statistics_detail_section.dart';
import 'package:oasx/modules/home/widgets/statistics_history_chart.dart';
import 'package:oasx/modules/home/widgets/statistics_hour_track.dart';
import 'package:oasx/translation/i18n.dart';

List<StatisticsHourBucket> _buckets() {
  return List<StatisticsHourBucket>.generate(
    24,
    (hour) => StatisticsHourBucket(
      hour: hour,
      seconds: hour >= 7 && hour <= 15 ? 1800 : 0,
      comparisonSeconds: hour >= 8 && hour <= 12 ? 900 : 0,
    ),
  );
}

ScriptTaskRunRecord _run(int hour) {
  return ScriptTaskRunRecord(
    startTimeText: '2026-11-06 ${hour.toString().padLeft(2, '0')}:00:00',
    endTimeText: '2026-11-06 ${hour.toString().padLeft(2, '0')}:09:20',
    durationSeconds: 560,
    battle: ScriptStatisticsBattleSummary(count: 18, avgDurationSeconds: 31),
    startTime: DateTime(2026, 11, 6, hour),
    endTime: DateTime(2026, 11, 6, hour, 9, 20),
  );
}

Widget _host(Widget child) {
  return GetMaterialApp(
    translations: Messages(),
    locale: const Locale('zh', 'CN'),
    fallbackLocale: const Locale('zh', 'CN'),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          height: 620,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: child,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('hour track renders in a 400px panel without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        StatisticsHourTrack(
          buckets: _buckets(),
          selectedHour: 9,
          todayCaption: '06:40 → 15:37 · 8h 57m',
          comparisonLabel: '昨天',
          comparisonCaption: '5h 55m',
          onToggleHour: (_) {},
          onClearHour: () {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('昨天'), findsOneWidget);
    // 今天轨道 24 格都带 key，对比轨不带。
    expect(find.byKey(const ValueKey('stats-hour-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('stats-hour-23')), findsOneWidget);
  });

  testWidgets('tapping a non-empty hour cell reports the hour', (
    tester,
  ) async {
    final tapped = <int>[];
    await tester.pumpWidget(
      _host(
        StatisticsHourTrack(
          buckets: _buckets(),
          selectedHour: null,
          todayCaption: '',
          comparisonLabel: null,
          comparisonCaption: '',
          onToggleHour: tapped.add,
          onClearHour: () {},
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('stats-hour-9')));
    expect(tapped, <int>[9]);

    // 空小时不可点。
    await tester.tap(find.byKey(const ValueKey('stats-hour-3')));
    expect(tapped, <int>[9]);
  });

  testWidgets('selecting an hour does not shift the track', (tester) async {
    Widget build({int? selectedHour}) => _host(
      StatisticsHourTrack(
        buckets: _buckets(),
        selectedHour: selectedHour,
        todayCaption: '06:40 → 15:37 · 8h 57m',
        comparisonLabel: '昨天',
        comparisonCaption: '5h 55m',
        onToggleHour: (_) {},
        onClearHour: () {},
      ),
    );

    await tester.pumpWidget(build());
    final before = tester.getTopLeft(
      find.byKey(const ValueKey('stats-hour-0')),
    );
    final headerBefore = tester.getSize(find.text('今天'));

    // 选中一个小时后，徽标出现，但标尺行高度与格子位置都不能变。
    await tester.pumpWidget(build(selectedHour: 9));
    final after = tester.getTopLeft(
      find.byKey(const ValueKey('stats-hour-0')),
    );
    final headerAfter = tester.getSize(find.text('今天'));

    expect(after, before);
    expect(headerAfter, headerBefore);
  });

  testWidgets('detail section folds to four rows and expands on demand', (
    tester,
  ) async {
    final runs = <ScriptTaskRunRecord>[
      for (var hour = 15; hour >= 6; hour--) _run(hour),
    ];
    await tester.pumpWidget(
      _host(ScriptStatisticsDetailSection(taskName: 'RealmRaid', runs: runs)),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('展开剩余 6 次'), findsOneWidget);
    // 折叠时只显示序号 10/9/8/7，第 6 次运行不出现。
    expect(find.text('6'), findsNothing);

    await tester.tap(find.text('展开剩余 6 次'));
    await tester.pump();
    expect(find.text('收起'), findsOneWidget);
    expect(find.text('展开剩余 6 次'), findsNothing);
    expect(find.text('6'), findsOneWidget);
  });

  testWidgets('history chart folds tasks beyond nine rows', (tester) async {
    final entries = <MapEntry<String, ScriptTaskStatistics>>[
      for (var index = 0; index < 12; index++)
        MapEntry(
          'Task$index',
          ScriptTaskStatistics(
            runCount: 12 - index,
            totalDurationSeconds: (12 - index) * 60.0,
            battle: null,
            runs: const [],
            latestRunStartTime: null,
          ),
        ),
    ];
    await tester.pumpWidget(
      _host(
        ScriptStatisticsHistoryChart(
          entries: entries,
          metric: ScriptStatisticsChartMetric.totalDuration,
          focusedTaskName: '',
          onSelectTask: (_) {},
          flashingTaskName: '',
          flashToken: 0,
          highlightRealtimeTask: false,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('展开剩余 3 个任务'), findsOneWidget);
    // 折叠时第 10 条以后不出现，第 9 条仍在。
    expect(find.text('Task8'), findsOneWidget);
    expect(find.text('Task9'), findsNothing);

    await tester.tap(find.text('展开剩余 3 个任务'));
    await tester.pump();
    expect(find.text('Task9'), findsOneWidget);
    expect(find.text('Task11'), findsOneWidget);
    expect(find.text('收起'), findsOneWidget);
  });

  testWidgets('history chart has no toggle when tasks fit', (tester) async {
    final entries = <MapEntry<String, ScriptTaskStatistics>>[
      for (var index = 0; index < 9; index++)
        MapEntry(
          'Task$index',
          ScriptTaskStatistics(
            runCount: 9 - index,
            totalDurationSeconds: (9 - index) * 60.0,
            battle: null,
            runs: const [],
            latestRunStartTime: null,
          ),
        ),
    ];
    await tester.pumpWidget(
      _host(
        ScriptStatisticsHistoryChart(
          entries: entries,
          metric: ScriptStatisticsChartMetric.totalDuration,
          focusedTaskName: '',
          onSelectTask: (_) {},
          flashingTaskName: '',
          flashToken: 0,
          highlightRealtimeTask: false,
        ),
      ),
    );
    expect(find.textContaining('展开剩余'), findsNothing);
    expect(find.text('Task8'), findsOneWidget);
  });
}
