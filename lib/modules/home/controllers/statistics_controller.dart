import 'dart:async';

import 'package:get/get.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/api/sse_client.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';
import 'package:oasx/modules/home/models/script_statistics_models.dart';
import 'package:oasx/utils/platform_utils.dart';

/// Drives statistics state for the active script workbench.
class HomeStatisticsController extends GetxController {
  /// Dashboard controller used to resolve the active script and tab.
  final HomeDashboardController dashboardController =
      Get.find<HomeDashboardController>();

  /// Current stream state shown by the statistics header.
  final connectionState = ScriptStatisticsConnectionState.idle.obs;

  /// Latest user-visible error message.
  final lastErrorMessage = ''.obs;

  /// Whether the available dates list is loading.
  final datesLoading = false.obs;

  /// Whether one selected-date snapshot request is loading.
  final statisticsLoading = false.obs;

  /// Available backend-provided dates for the active script.
  final availableDateKeys = <String>[].obs;

  /// Selected-date statistics currently rendered by the page.
  final statistics = Rxn<ScriptStatisticsDay>();

  /// Date currently selected in the header control.
  final selectedDateKey = ''.obs;

  /// Task currently focused in the chart.
  final selectedTaskName = ''.obs;

  /// Hour (0-23) currently used to filter the chart, null when disabled.
  final selectedHour = Rxn<int>();

  /// Previous day snapshot used by the comparison heat track.
  final comparisonDay = Rxn<ScriptStatisticsDay>();

  /// Whether the comparison day snapshot is loading.
  final comparisonLoading = false.obs;

  /// Metric currently shown by the chart.
  final historyMetric = ScriptStatisticsChartMetric.totalDuration.obs;

  /// Sort field currently applied to the chart.
  final historySortField = ScriptStatisticsChartSortField.data.obs;

  /// Whether chart values are sorted descending.
  final historySortDescending = true.obs;

  /// Whether the chart is waiting for a metric refresh.
  final historyChartLoading = false.obs;

  /// Task name highlighted by realtime updates.
  final latestUpdatedTaskName = ''.obs;

  /// Monotonic token used to restart flash animations.
  final latestUpdatedTaskPulse = 0.obs;

  /// Worker that keeps the controller bound to dashboard context.
  Worker? _dashboardWorker;

  /// Active SSE service, only present when today is selected.
  ApiSseClient? _streamService;

  /// Script currently bound by the statistics tab.
  String _boundScriptName = '';

  /// Script currently owned by the live SSE stream.
  String _streamScriptName = '';

  /// Date currently owned by the live SSE stream.
  String _streamDateKey = '';

  /// Sequence used to invalidate stale bootstrap work.
  int _bindingRevision = 0;

  /// Sequence used to invalidate stale stats work.
  int _statsRevision = 0;

  /// Sequence used to show chart metric loading transitions.
  int _historyMetricRequestId = 0;

  /// Cache key for sorted chart entries.
  String _taskEntriesCacheKey = '';

  /// Cached chart entries for the last derived state.
  List<MapEntry<String, ScriptTaskStatistics>> _taskEntriesCache = const [];

  /// Cache key for hourly buckets and the active span.
  String _dayDerivedCacheKey = '';

  /// Cached 24-hour buckets for the selected day.
  List<StatisticsHourBucket> _hourBucketsCache = const [];

  /// Cached first-start to last-end span of the selected day.
  double _activeSpanSeconds = 0;

  /// Cached first run start of the selected day.
  DateTime? _activeSpanStart;

  /// Cached last run end of the selected day.
  DateTime? _activeSpanEnd;

  /// Sequential queue that preserves SSE event ordering during async parsing.
  Future<void> _streamEventQueue = Future<void>.value();

  @override
  void onInit() {
    _dashboardWorker = everAll([
      dashboardController.activeScriptName,
      dashboardController.activeWorkbenchTab,
      dashboardController.activeWorkbenchSidebarTab,
      dashboardController.workbenchLayoutMode,
      dashboardController.statsPanelVisible,
    ], (_) {
      unawaited(syncStatisticsBinding());
    });
    unawaited(syncStatisticsBinding());
    super.onInit();
  }

  @override
  void onClose() {
    _dashboardWorker?.dispose();
    _dashboardWorker = null;
    unawaited(_stopStream());
    super.onClose();
  }

  /// Whether the selected date is today.
  bool get isTodaySelected {
    return isStatisticsDateToday(selectedDateKey.value);
  }

  /// Whether the selected day can use time-based sorting.
  bool get canSortByTime {
    return statistics.value != null;
  }

  /// Sorted chart entries for the currently selected day.
  ///
  /// When an hour filter is active, only tasks with a run overlapping that hour
  /// remain, and their values are recomputed from those runs so the bars keep
  /// matching what the heat track says happened.
  List<MapEntry<String, ScriptTaskStatistics>> get historyTaskEntries {
    final currentStatistics = statistics.value;
    if (currentStatistics == null) {
      return const [];
    }
    final metric = historyMetric.value;
    final sortField = historySortField.value;
    final descending = historySortDescending.value;
    final hour = selectedHour.value;
    final cacheKey =
        '${currentStatistics.dateKey}|${currentStatistics.totalRuntimeSeconds}|${currentStatistics.totalTaskRunCount}|${metric.name}|${sortField.name}|$descending|${hour ?? -1}';
    if (_taskEntriesCacheKey == cacheKey) {
      return _taskEntriesCache;
    }
    var entries = currentStatistics.tasks.entries.where((entry) {
      if (statisticsMetricUsesBattleFilter(metric)) {
        return entry.value.battleCount > 0;
      }
      return entry.value.runCount > 0;
    }).toList();
    if (hour != null) {
      entries = entries
          .map((entry) => _restrictEntryToHour(entry, hour))
          .whereType<MapEntry<String, ScriptTaskStatistics>>()
          .toList();
    }
    entries.sort((left, right) {
      final compareValue = switch (sortField) {
        ScriptStatisticsChartSortField.data => left.value
            .metricValueFor(metric)
            .compareTo(right.value.metricValueFor(metric)),
        ScriptStatisticsChartSortField.time => _compareLatestRunTime(
            left.value,
            right.value,
          ),
      };
      if (compareValue != 0) {
        return descending ? -compareValue : compareValue;
      }
      return left.key.compareTo(right.key);
    });
    _taskEntriesCacheKey = cacheKey;
    _taskEntriesCache =
        List<MapEntry<String, ScriptTaskStatistics>>.unmodifiable(entries);
    return _taskEntriesCache;
  }

  /// 24 hourly buckets for the selected day plus the comparison day.
  List<StatisticsHourBucket> get hourlyBuckets {
    _ensureDayDerived();
    return _hourBucketsCache;
  }

  /// Span from the first run start to the last run end on the selected day.
  double get activeSpanSeconds {
    _ensureDayDerived();
    return _activeSpanSeconds;
  }

  /// First run start of the selected day, used by the hero caption.
  DateTime? get activeSpanStart {
    _ensureDayDerived();
    return _activeSpanStart;
  }

  /// Last run end of the selected day, used by the hero caption.
  DateTime? get activeSpanEnd {
    _ensureDayDerived();
    return _activeSpanEnd;
  }

  /// Whether the comparison track has any data worth drawing.
  bool get hasComparisonTrack {
    final day = comparisonDay.value;
    if (day == null) {
      return false;
    }
    return day.runEntries.isNotEmpty;
  }

  /// Runtime divided by the active span, null when the day has no run.
  double? get effectiveRatio {
    final currentStatistics = statistics.value;
    final span = activeSpanSeconds;
    if (currentStatistics == null || span <= 0) {
      return null;
    }
    return (currentStatistics.totalRuntimeSeconds / span).clamp(0.0, 1.0);
  }

  /// Run details for the focused task, sorted from newest to oldest.
  List<ScriptTaskRunRecord> get selectedHistoryDetailRuns {
    final currentStatistics = statistics.value;
    final taskName = selectedTaskName.value.trim();
    if (currentStatistics == null || taskName.isEmpty) {
      return const [];
    }
    final runs = List<ScriptTaskRunRecord>.from(
      currentStatistics.tasks[taskName]?.runs ?? const [],
    );
    runs.removeWhere((run) => !run.hasTimeRange);
    final hour = selectedHour.value;
    if (hour != null) {
      runs.removeWhere((run) => !statisticsRunOverlapsHour(run, hour));
    }
    runs.sort((left, right) {
      final leftTime = left.endTime ?? left.startTime;
      final rightTime = right.endTime ?? right.startTime;
      if (leftTime == null && rightTime == null) {
        return 0;
      }
      if (leftTime == null) {
        return 1;
      }
      if (rightTime == null) {
        return -1;
      }
      return rightTime.compareTo(leftTime);
    });
    return runs;
  }

  /// Rebinds the statistics transport to the currently visible script context.
  Future<void> syncStatisticsBinding() async {
    final scriptName = dashboardController.activeScriptName.value.trim();
    if (!dashboardController.isStatsVisibleInCurrentLayout ||
        scriptName.isEmpty) {
      await _resetBindingState(clearSelection: false);
      return;
    }
    if (_boundScriptName == scriptName && availableDateKeys.isNotEmpty) {
      return;
    }
    await _bootstrapForScript(scriptName);
  }

  /// Updates the selected date and reloads its data.
  void selectHistoryDate(String dateKey) {
    if (selectedDateKey.value == dateKey ||
        !availableDateKeys.contains(dateKey) ||
        _boundScriptName.isEmpty) {
      return;
    }
    selectedDateKey.value = dateKey;
    selectedHour.value = null;
    unawaited(_loadSelectedDate(_boundScriptName, dateKey));
  }

  /// Updates the focused task in the chart.
  void selectHistoryTask(String taskName) {
    selectedTaskName.value = taskName.trim();
  }

  /// Toggles the hour filter; tapping the same hour again clears it.
  void toggleHistoryHour(int hour) {
    if (hour < 0 || hour > 23) {
      return;
    }
    selectedHour.value = selectedHour.value == hour ? null : hour;
    _syncSelections();
  }

  /// Clears the hour filter.
  void clearHistoryHour() {
    if (selectedHour.value == null) {
      return;
    }
    selectedHour.value = null;
    _syncSelections();
  }

  /// Updates the chart sort field.
  void selectHistorySortField(ScriptStatisticsChartSortField field) {
    final resolvedField =
        field == ScriptStatisticsChartSortField.time && !canSortByTime
            ? ScriptStatisticsChartSortField.data
            : field;
    if (historySortField.value == resolvedField) {
      return;
    }
    historySortField.value = resolvedField;
    _syncSelections();
  }

  /// Toggles the chart sort direction.
  void toggleHistorySortDirection() {
    historySortDescending.value = !historySortDescending.value;
    _syncSelections();
  }

  /// Updates the chart metric with a visible loading state.
  Future<void> selectHistoryMetric(ScriptStatisticsChartMetric metric) async {
    if (historyMetric.value == metric) {
      return;
    }
    final requestId = ++_historyMetricRequestId;
    historyMetric.value = metric;
    _syncSelections();
    historyChartLoading.value = true;
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (requestId != _historyMetricRequestId) {
      return;
    }
    historyChartLoading.value = false;
  }

  /// Loads dates first, then binds the newest available selected date.
  Future<void> _bootstrapForScript(String scriptName) async {
    final bindingRevision = ++_bindingRevision;
    _boundScriptName = scriptName;
    await _stopStream();
    _resetDerivedState();
    datesLoading.value = true;
    statisticsLoading.value = false;
    connectionState.value = ScriptStatisticsConnectionState.idle;
    lastErrorMessage.value = '';
    try {
      final dateList = await ApiClient().getScriptStatisticsDates(scriptName);
      if (!_isBindingActive(bindingRevision, scriptName)) {
        return;
      }
      availableDateKeys.assignAll(dateList.dates);
      datesLoading.value = false;
      if (availableDateKeys.isEmpty) {
        selectedDateKey.value = '';
        statistics.value = null;
        return;
      }
      selectedDateKey.value = availableDateKeys.first;
      await _loadSelectedDate(scriptName, selectedDateKey.value);
    } catch (error) {
      if (!_isBindingActive(bindingRevision, scriptName)) {
        return;
      }
      datesLoading.value = false;
      availableDateKeys.clear();
      selectedDateKey.value = '';
      statistics.value = null;
      lastErrorMessage.value = error.toString();
    }
  }

  /// Loads the currently selected date using either SSE or one-shot HTTP.
  Future<void> _loadSelectedDate(String scriptName, String dateKey) async {
    if (_boundScriptName != scriptName ||
        !availableDateKeys.contains(dateKey)) {
      return;
    }
    final shouldUseLiveStream =
        isStatisticsDateToday(dateKey) && !PlatformUtils.isWeb;
    final statsRevision = ++_statsRevision;
    await _stopStream();
    _resetSelectedDateState();
    lastErrorMessage.value = '';
    if (shouldUseLiveStream) {
      statisticsLoading.value = false;
      unawaited(_loadComparisonDay(scriptName, dateKey, statsRevision));
      await _startTodayStream(scriptName, dateKey, statsRevision);
      return;
    }
    connectionState.value = ScriptStatisticsConnectionState.idle;
    statisticsLoading.value = true;
    try {
      final day = await ApiClient().getScriptStatisticsDay(scriptName, dateKey);
      if (!_isStatsRequestActive(statsRevision, scriptName, dateKey)) {
        return;
      }
      statisticsLoading.value = false;
      statistics.value = day;
      connectionState.value =
          isStatisticsDateToday(dateKey) && PlatformUtils.isWeb
              ? ScriptStatisticsConnectionState.connected
              : ScriptStatisticsConnectionState.idle;
      _syncSelections();
    } catch (error) {
      if (!_isStatsRequestActive(statsRevision, scriptName, dateKey)) {
        return;
      }
      statisticsLoading.value = false;
      statistics.value = null;
      connectionState.value =
          isStatisticsDateToday(dateKey) && PlatformUtils.isWeb
              ? ScriptStatisticsConnectionState.error
              : ScriptStatisticsConnectionState.idle;
      lastErrorMessage.value = error.toString();
    }
  }

  /// Loads the previous available date as the comparison heat track.
  ///
  /// Only today shows a comparison track: past dates already have their own
  /// single track, and pulling a second day for them doubles the request count
  /// for a view that is already off-screen most of the time.
  Future<void> _loadComparisonDay(
    String scriptName,
    String dateKey,
    int statsRevision,
  ) async {
    comparisonDay.value = null;
    if (!isStatisticsDateToday(dateKey)) {
      return;
    }
    final index = availableDateKeys.indexOf(dateKey);
    if (index < 0 || index + 1 >= availableDateKeys.length) {
      return;
    }
    final comparisonKey = availableDateKeys[index + 1];
    comparisonLoading.value = true;
    try {
      final day =
          await ApiClient().getScriptStatisticsDay(scriptName, comparisonKey);
      if (_statsRevision != statsRevision ||
          selectedDateKey.value != dateKey ||
          _boundScriptName != scriptName) {
        return;
      }
      comparisonDay.value = day;
    } catch (_) {
      // 对比轨只是参照，取不到就只画今天那条，不打扰用户。
    } finally {
      if (statsRevision == _statsRevision) {
        comparisonLoading.value = false;
      }
    }
  }

  /// Starts the live SSE stream for today.
  Future<void> _startTodayStream(
    String scriptName,
    String dateKey,
    int statsRevision,
  ) async {
    if (!_isStatsRequestActive(statsRevision, scriptName, dateKey)) {
      return;
    }
    _streamScriptName = scriptName;
    _streamDateKey = dateKey;
    final sseUri = ApiClient().buildScriptStatisticsSseUri(scriptName, dateKey);
    _streamService = ApiSseClient(
      url: sseUri,
      onEvent: _handleStreamEvent,
      onStateChanged: _handleStreamState,
    );
    await _streamService?.connect();
  }

  /// Stops the current statistics stream.
  Future<void> _stopStream() async {
    final service = _streamService;
    _streamService = null;
    _streamScriptName = '';
    _streamDateKey = '';
    _streamEventQueue = Future<void>.value();
    await service?.dispose();
  }

  /// Resets state when the tab is hidden or script becomes unavailable.
  Future<void> _resetBindingState({required bool clearSelection}) async {
    _bindingRevision++;
    _statsRevision++;
    _boundScriptName = '';
    await _stopStream();
    datesLoading.value = false;
    statisticsLoading.value = false;
    connectionState.value = ScriptStatisticsConnectionState.idle;
    lastErrorMessage.value = '';
    availableDateKeys.clear();
    statistics.value = null;
    latestUpdatedTaskName.value = '';
    latestUpdatedTaskPulse.value = 0;
    selectedHour.value = null;
    comparisonDay.value = null;
    comparisonLoading.value = false;
    historySortField.value = ScriptStatisticsChartSortField.data;
    historySortDescending.value = true;
    historyChartLoading.value = false;
    _clearDerivedCaches();
    if (clearSelection) {
      selectedDateKey.value = '';
      selectedTaskName.value = '';
    }
  }

  /// Resets derived state for a new bound script.
  void _resetDerivedState() {
    availableDateKeys.clear();
    statistics.value = null;
    selectedDateKey.value = '';
    selectedTaskName.value = '';
    selectedHour.value = null;
    comparisonDay.value = null;
    comparisonLoading.value = false;
    latestUpdatedTaskName.value = '';
    latestUpdatedTaskPulse.value = 0;
    historySortField.value = ScriptStatisticsChartSortField.data;
    historySortDescending.value = true;
    historyChartLoading.value = false;
    _clearDerivedCaches();
  }

  /// Resets selected-date data before a reload starts.
  void _resetSelectedDateState() {
    statistics.value = null;
    selectedTaskName.value = '';
    selectedHour.value = null;
    comparisonDay.value = null;
    comparisonLoading.value = false;
    latestUpdatedTaskName.value = '';
    latestUpdatedTaskPulse.value = 0;
    _clearDerivedCaches();
  }

  /// Updates the visible stream state and error label.
  void _handleStreamState(ApiSseConnectionState state, String? message) {
    if (_streamService == null || !isTodaySelected) {
      return;
    }
    final normalizedMessage = message == 'stream_closed' ? '' : (message ?? '');
    connectionState.value = switch (state) {
      ApiSseConnectionState.connecting =>
        ScriptStatisticsConnectionState.connecting,
      ApiSseConnectionState.connected =>
        ScriptStatisticsConnectionState.connected,
      ApiSseConnectionState.reconnecting =>
        ScriptStatisticsConnectionState.reconnecting,
      ApiSseConnectionState.error => ScriptStatisticsConnectionState.error,
    };
    lastErrorMessage.value = normalizedMessage;
    if (state == ApiSseConnectionState.error &&
        lastErrorMessage.value.isNotEmpty) {
      printError(info: 'stats[$_streamScriptName] ${lastErrorMessage.value}');
    }
  }

  /// Merges live SSE events into the selected-day state.
  void _handleStreamEvent(ApiSseEvent event) {
    _streamEventQueue = _streamEventQueue.then(
      (_) => _processStreamEvent(event),
      onError: (_) => _processStreamEvent(event),
    );
  }

  /// Parses and applies one SSE event without blocking the UI isolate.
  Future<void> _processStreamEvent(ApiSseEvent event) async {
    final streamService = _streamService;
    final dateKey = _streamDateKey;
    if (streamService == null || dateKey.isEmpty) {
      return;
    }
    final payloadText = event.data.trim();
    if (payloadText.isEmpty) {
      return;
    }
    try {
      switch (event.name.trim()) {
        case 'snapshot':
          final day = await parseScriptStatisticsSnapshotPayloadAsync(
            payloadText,
            dateKey: dateKey,
          );
          if (_streamService != streamService || _streamDateKey != dateKey) {
            return;
          }
          statistics.value = day;
          latestUpdatedTaskName.value = '';
          _clearDerivedCaches();
          _syncSelections();
          break;
        case 'update':
          final update = await parseScriptStatisticsUpdatePayloadAsync(
            payloadText,
          );
          if (_streamService != streamService || _streamDateKey != dateKey) {
            return;
          }
          final currentStatistics = statistics.value;
          if (currentStatistics == null ||
              currentStatistics.dateKey != dateKey) {
            return;
          }
          statistics.value = currentStatistics.applyUpdate(update);
          _markUpdatedTask(update.changedTasks);
          _clearDerivedCaches();
          _syncSelections();
          break;
        default:
          return;
      }
      connectionState.value = ScriptStatisticsConnectionState.connected;
      lastErrorMessage.value = '';
    } catch (error) {
      printError(
        info: 'stats[$_streamScriptName] parse event "${event.name}": $error',
      );
    }
  }

  /// Keeps the focused task valid when selected-date content changes.
  void _syncSelections() {
    final entries = historyTaskEntries;
    if (entries.isEmpty) {
      selectedTaskName.value = '';
      return;
    }
    if (!canSortByTime &&
        historySortField.value == ScriptStatisticsChartSortField.time) {
      historySortField.value = ScriptStatisticsChartSortField.data;
    }
    final preferredTask = selectedTaskName.value.trim();
    final hasPreferredTask = entries.any((entry) => entry.key == preferredTask);
    selectedTaskName.value =
        hasPreferredTask ? preferredTask : entries.first.key;
  }

  /// Clears cached derived lists used by the chart.
  void _clearDerivedCaches() {
    _taskEntriesCacheKey = '';
    _taskEntriesCache = const [];
    _dayDerivedCacheKey = '';
    _hourBucketsCache = const [];
    _activeSpanSeconds = 0;
    _activeSpanStart = null;
    _activeSpanEnd = null;
  }

  /// Rebuilds the hourly buckets and the active span when the day changes.
  void _ensureDayDerived() {
    final day = statistics.value;
    if (day == null) {
      _clearDerivedCaches();
      return;
    }
    final other = comparisonDay.value;
    final cacheKey = '${day.dateKey}|${day.totalRuntimeSeconds}'
        '|${day.totalTaskRunCount}|${other?.dateKey ?? ''}'
        '|${other?.totalRuntimeSeconds ?? -1}';
    if (cacheKey == _dayDerivedCacheKey) {
      return;
    }
    _hourBucketsCache = buildStatisticsHourBuckets(day, comparison: other);
    final span = statisticsActiveSpanOf(day);
    _activeSpanSeconds = span.seconds;
    _activeSpanStart = span.start;
    _activeSpanEnd = span.end;
    _dayDerivedCacheKey = cacheKey;
  }

  /// Keeps only the runs of one task that overlap the filtered hour.
  MapEntry<String, ScriptTaskStatistics>? _restrictEntryToHour(
    MapEntry<String, ScriptTaskStatistics> entry,
    int hour,
  ) {
    final runs = entry.value.runs
        .where((run) => statisticsRunOverlapsHour(run, hour))
        .toList(growable: false);
    if (runs.isEmpty) {
      return null;
    }
    var durationSeconds = 0.0;
    var battleCount = 0;
    var battleSeconds = 0.0;
    DateTime? latestStart;
    for (final run in runs) {
      durationSeconds += statisticsRunSecondsInHour(run, hour);
      battleCount += run.battleCount;
      battleSeconds += run.battleCount * run.battleAvgDurationSeconds;
      final start = run.startTime;
      if (start != null && (latestStart == null || start.isAfter(latestStart))) {
        latestStart = start;
      }
    }
    return MapEntry(
      entry.key,
      ScriptTaskStatistics(
        runCount: runs.length,
        totalDurationSeconds: durationSeconds,
        battle: battleCount > 0
            ? ScriptStatisticsBattleSummary(
                count: battleCount,
                avgDurationSeconds: battleSeconds / battleCount,
              )
            : null,
        runs: runs,
        latestRunStartTime: latestStart,
      ),
    );
  }

  /// Marks the latest updated task for a flash highlight.
  void _markUpdatedTask(Map<String, ScriptTaskStatistics> changedTasks) {
    if (changedTasks.isEmpty) {
      return;
    }
    final latestEntry = changedTasks.entries.toList()
      ..sort((left, right) {
        final leftTime = left.value.latestRunStartTime;
        final rightTime = right.value.latestRunStartTime;
        if (leftTime == null && rightTime == null) {
          return 0;
        }
        if (leftTime == null) {
          return 1;
        }
        if (rightTime == null) {
          return -1;
        }
        return rightTime.compareTo(leftTime);
      });
    latestUpdatedTaskName.value = latestEntry.first.key;
    latestUpdatedTaskPulse.value++;
  }

  /// Returns whether one bootstrap run is still active.
  bool _isBindingActive(int revision, String scriptName) {
    return revision == _bindingRevision &&
        dashboardController.isStatsVisibleInCurrentLayout &&
        _boundScriptName == scriptName &&
        dashboardController.activeScriptName.value.trim() == scriptName;
  }

  /// Returns whether one selected-date request is still active.
  bool _isStatsRequestActive(
    int revision,
    String scriptName,
    String dateKey,
  ) {
    return revision == _statsRevision &&
        dashboardController.isStatsVisibleInCurrentLayout &&
        _boundScriptName == scriptName &&
        selectedDateKey.value == dateKey;
  }

  /// Compares tasks by their latest run start time.
  int _compareLatestRunTime(
    ScriptTaskStatistics left,
    ScriptTaskStatistics right,
  ) {
    final leftTime = left.latestRunStartTime;
    final rightTime = right.latestRunStartTime;
    if (leftTime == null && rightTime == null) {
      return 0;
    }
    if (leftTime == null) {
      return -1;
    }
    if (rightTime == null) {
      return 1;
    }
    return leftTime.compareTo(rightTime);
  }
}
