import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/modules/home/models/script_statistics_models.dart';

ScriptTaskRunRecord _run(String? start, String? end) {
  DateTime? parse(String? value) {
    if (value == null) {
      return null;
    }
    return DateTime.parse(value.replaceFirst(' ', 'T'));
  }

  return ScriptTaskRunRecord(
    startTimeText: start ?? '',
    endTimeText: end ?? '',
    durationSeconds: 0,
    battle: null,
    startTime: parse(start),
    endTime: parse(end),
  );
}

ScriptStatisticsDay _day(
  String dateKey,
  List<ScriptTaskRunRecord> runs, {
  double totalRuntime = 0,
}) {
  return ScriptStatisticsDay(
    scriptName: 'CDB',
    dateKey: dateKey,
    totalRuntimeSeconds: totalRuntime,
    totalTaskRunCount: runs.length,
    totalBattleCount: 0,
    tasks: {
      'RealmRaid': ScriptTaskStatistics(
        runCount: runs.length,
        totalDurationSeconds: totalRuntime,
        battle: null,
        runs: runs,
        latestRunStartTime: runs.isEmpty ? null : runs.last.startTime,
      ),
    },
  );
}

void main() {
  group('statisticsRunSecondsInHour', () {
    test('a run inside one hour fills that hour only', () {
      final run = _run('2026-11-06 09:00:00', '2026-11-06 10:00:00');
      expect(statisticsRunSecondsInHour(run, 9), 3600);
      expect(statisticsRunSecondsInHour(run, 8), 0);
      expect(statisticsRunSecondsInHour(run, 10), 0);
    });

    test('a run crossing an hour boundary is clipped on both sides', () {
      final run = _run('2026-11-06 09:40:00', '2026-11-06 10:10:00');
      expect(statisticsRunSecondsInHour(run, 9), 20 * 60);
      expect(statisticsRunSecondsInHour(run, 10), 10 * 60);
      expect(statisticsRunSecondsInHour(run, 11), 0);
    });

    test('a run crossing midnight only counts inside its own date', () {
      final run = _run('2026-11-06 23:30:00', '2026-11-07 00:30:00');
      expect(statisticsRunSecondsInHour(run, 23), 30 * 60);
      // 次日那 30 分钟属于 11-07 的统计，不塞进 11-06 的 0 点格子。
      expect(statisticsRunSecondsInHour(run, 0), 0);
    });

    test('runs without parsed timestamps contribute nothing', () {
      final run = _run(null, null);
      expect(statisticsRunSecondsInHour(run, 9), 0);
      expect(statisticsRunOverlapsHour(run, 9), isFalse);
    });
  });

  group('buildStatisticsHourBuckets', () {
    test('accumulates several runs of the same hour', () {
      final day = _day('2026-11-06', [
        _run('2026-11-06 07:05:00', '2026-11-06 07:15:00'),
        _run('2026-11-06 07:40:00', '2026-11-06 07:55:00'),
      ]);
      final buckets = buildStatisticsHourBuckets(day);
      expect(buckets, hasLength(24));
      expect(buckets[7].seconds, 25 * 60);
      expect(buckets[7].hasRun, isTrue);
      expect(buckets[8].hasRun, isFalse);
      expect(buckets[7].hour, 7);
    });

    test('fills the comparison column from the comparison day only', () {
      final today = _day('2026-11-06', [
        _run('2026-11-06 09:00:00', '2026-11-06 09:30:00'),
      ]);
      final yesterday = _day('2026-11-05', [
        _run('2026-11-05 09:00:00', '2026-11-05 10:00:00'),
      ]);
      final buckets = buildStatisticsHourBuckets(today, comparison: yesterday);
      expect(buckets[9].seconds, 30 * 60);
      expect(buckets[9].comparisonSeconds, 60 * 60);
      // 只给今天的日子画轨道时对比列全为 0。
      final solo = buildStatisticsHourBuckets(today);
      expect(solo[9].comparisonSeconds, 0);
    });
  });

  group('statisticsActiveSpanOf', () {
    test('spans from the first start to the last end', () {
      final day = _day('2026-11-06', [
        _run('2026-11-06 06:40:00', '2026-11-06 07:10:00'),
        _run('2026-11-06 15:00:00', '2026-11-06 15:37:00'),
      ], totalRuntime: 402 * 60);
      final span = statisticsActiveSpanOf(day);
      expect(span.start, DateTime.parse('2026-11-06T06:40:00'));
      expect(span.end, DateTime.parse('2026-11-06T15:37:00'));
      expect(span.seconds, 8 * 3600 + 57 * 60);
      // 有效运行占比 = 运行时长 / 跨度。
      expect(402 * 60 / span.seconds, closeTo(0.75, 0.01));
    });

    test('a day without runs has an empty span', () {
      final day = _day('2026-11-06', const []);
      final span = statisticsActiveSpanOf(day);
      expect(span.start, isNull);
      expect(span.end, isNull);
      expect(span.seconds, 0);
    });
  });
}
