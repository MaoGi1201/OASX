part of 'dashboard_controller.dart';

/// Maximum time the UI stays locked for one bulk quick schedule request.
const _bulkQuickScheduleTimeout = Duration(seconds: 5);

extension HomeDashboardWorkspaceX on HomeDashboardController {
  /// Records the latest resolved workbench layout mode.
  void setWorkbenchLayoutMode(HomeWorkbenchLayoutMode value) {
    if (workbenchLayoutMode.value == value) {
      return;
    }
    workbenchLayoutMode.value = value;
  }

  bool canQuickScheduleTask(ScriptModel model, String taskName) {
    final normalized = taskName.trim();
    if (normalized.isEmpty) {
      return false;
    }
    final runningTaskName = model.runningTask.value.taskName.value.trim();
    final isConfigRunning = model.state.value == ScriptState.running;
    return !isConfigRunning || runningTaskName != normalized;
  }

  /// Returns whether a bulk quick schedule operation is currently active.
  bool get isBulkQuickScheduling {
    return bulkQuickScheduleMode.value != HomeBulkQuickScheduleMode.none;
  }

  /// Collects enabled task names in overview order for bulk quick scheduling.
  List<String> quickSchedulableTaskNamesFor(ScriptModel model) {
    final names = <String>[];
    final seen = <String>{};
    _addQuickScheduleTaskName(
      model,
      names,
      seen,
      model.runningTask.value.taskName.value,
    );
    for (final task in model.pendingTaskList) {
      _addQuickScheduleTaskName(model, names, seen, task.taskName.value);
    }
    for (final task in model.waitingTaskList) {
      _addQuickScheduleTaskName(model, names, seen, task.taskName.value);
    }
    // 已被取消的任务不要参与批量调度（running 槽里的残留项）。
    final disabled = locallyDisabledTaskNames[model.name];
    if (disabled != null && disabled.isNotEmpty) {
      names.removeWhere(disabled.contains);
    }
    return names;
  }

  /// Runs all eligible tasks through the existing quick schedule flow.
  Future<HomeBulkQuickScheduleResult> bulkQuickScheduleTasks({
    required String scriptName,
    required bool runNow,
  }) async {
    if (isBulkQuickScheduling) {
      return HomeBulkQuickScheduleResult.skipped;
    }
    final source = scriptName.trim();
    if (source.isEmpty) {
      return HomeBulkQuickScheduleResult.skipped;
    }
    // 连接器勾选后，批量操作要对同一组配置一起执行。
    final targets = linkedScopeScriptsFor(source);
    bulkQuickScheduleMode.value = runNow
        ? HomeBulkQuickScheduleMode.runNow
        : HomeBulkQuickScheduleMode.waitNow;
    try {
      var anyTimedOut = false;
      var anyFailed = false;
      var anyDone = false;
      for (final target in targets) {
        final result = await _bulkQuickScheduleTasksForSingle(target, runNow);
        switch (result) {
          case HomeBulkQuickScheduleResult.completed:
            anyDone = true;
          case HomeBulkQuickScheduleResult.timedOut:
            anyTimedOut = true;
            anyDone = true;
          case HomeBulkQuickScheduleResult.failed:
            anyFailed = true;
            anyDone = true;
          case HomeBulkQuickScheduleResult.skipped:
            break;
        }
      }
      if (!anyDone) {
        return HomeBulkQuickScheduleResult.skipped;
      }
      if (anyTimedOut) {
        return HomeBulkQuickScheduleResult.timedOut;
      }
      return anyFailed
          ? HomeBulkQuickScheduleResult.failed
          : HomeBulkQuickScheduleResult.completed;
    } finally {
      bulkQuickScheduleMode.value = HomeBulkQuickScheduleMode.none;
    }
  }

  /// 单个配置的批量执行，返回值不再改动 [bulkQuickScheduleMode]。
  Future<HomeBulkQuickScheduleResult> _bulkQuickScheduleTasksForSingle(
    String scriptName,
    bool runNow,
  ) async {
    final source = scriptName.trim();
    final model = _scriptService.findScriptModel(source);
    final taskNames = model == null
        ? const <String>[]
        : quickSchedulableTaskNamesFor(model);
    if (source.isEmpty || taskNames.isEmpty) {
      return HomeBulkQuickScheduleResult.skipped;
    }
    final result = await Future.any<bool?>([
      _runBulkQuickScheduleTasks(source, taskNames, runNow),
      Future<bool?>.delayed(_bulkQuickScheduleTimeout, () => null),
    ]);
    if (result == null) {
      return HomeBulkQuickScheduleResult.timedOut;
    }
    return result
        ? HomeBulkQuickScheduleResult.completed
        : HomeBulkQuickScheduleResult.failed;
  }

  List<HomeWorkbenchTab> workbenchTabsFor(HomeWorkbenchLayoutMode mode) {
    return resolveHomeWorkbenchTabs(mode);
  }

  List<HomeWorkbenchTab> workbenchSidebarTabsFor(HomeWorkbenchLayoutMode mode) {
    return resolveHomeWorkbenchSidebarTabs(mode);
  }

  HomeWorkbenchTab displayedWorkbenchTabFor(HomeWorkbenchLayoutMode mode) {
    if (mode == HomeWorkbenchLayoutMode.threePane &&
        isHomeWorkbenchSidebarTab(activeWorkbenchTab.value)) {
      return _lastPrimaryWorkbenchTab.value;
    }
    return activeWorkbenchTab.value;
  }

  HomeWorkbenchTab displayedWorkbenchSidebarTabFor(
    HomeWorkbenchLayoutMode mode,
  ) {
    return activeWorkbenchSidebarTab.value;
  }

  bool get isStatsVisibleInCurrentLayout {
    if (statsPanelVisible.value) {
      return true;
    }
    if (workbenchLayoutMode.value == HomeWorkbenchLayoutMode.threePane) {
      return displayedWorkbenchSidebarTabFor(workbenchLayoutMode.value) ==
          HomeWorkbenchTab.stats;
    }
    return activeWorkbenchTab.value == HomeWorkbenchTab.stats;
  }

  /// Called by the dashboard's right column when it switches tabs.
  void setStatsPanelVisible(bool visible) {
    if (statsPanelVisible.value == visible) {
      return;
    }
    statsPanelVisible.value = visible;
  }

  List<ScriptModel> get orderedScripts {
    final models = <ScriptModel>[];
    for (final name in _scriptService.scriptOrderList) {
      final model = _scriptService.findScriptModel(name);
      if (model != null) {
        models.add(model);
      }
    }
    return models;
  }

  List<ScriptModel> get visibleScripts {
    return orderedScripts.where(_matchesVisibleFilter).toList();
  }

  ScriptModel? get activeScriptModel {
    return _scriptService.findScriptModel(activeScriptName.value.trim());
  }

  List<String> get selectedScopeScripts {
    final active = activeScriptName.value.trim();
    return active.isEmpty ? const [] : [active];
  }

  int get selectedScopeCount => selectedScopeScripts.length;

  bool get isSinglePaneScriptListPage =>
      workbenchPage.value == HomeWorkbenchPage.scripts;

  int countScriptsByState(HomeScriptStateFilter filter) {
    return orderedScripts
        .where((model) => scriptCollectionStateFor(model) == filter)
        .length;
  }

  bool isScriptSelected(String scriptName) {
    return selectedScriptList.contains(scriptName.trim());
  }

  Set<String> enabledTaskNamesFor(ScriptModel model) {
    final names = <String>{};
    final running = model.runningTask.value.taskName.value.trim();
    if (running.isNotEmpty) {
      names.add(running);
    }
    names.addAll(
      model.pendingTaskList
          .map((task) => task.taskName.value.trim())
          .where((taskName) => taskName.isNotEmpty),
    );
    names.addAll(
      model.waitingTaskList
          .map((task) => task.taskName.value.trim())
          .where((taskName) => taskName.isNotEmpty),
    );
    // 后端 running 槽会残留刚被取消的任务，按本地取消记录剔除，
    // 否则「总览」里的勾选永远摘不掉。
    final disabled = locallyDisabledTaskNames[model.name];
    if (disabled != null && disabled.isNotEmpty) {
      // 若它又出现在 pending/waiting 里（例如从原版 GUI 重新启用），
      // 说明后端认定它仍在启用，就不再按本地记录剔除。
      final scheduled = <String>{
        ...model.pendingTaskList.map((task) => task.taskName.value.trim()),
        ...model.waitingTaskList.map((task) => task.taskName.value.trim()),
      };
      names.removeAll(disabled.where((name) => !scheduled.contains(name)));
    }
    return names;
  }

  /// 记录一次本地启停结果，供 [enabledTaskNamesFor] 剔除残留的 running 项。
  void markTaskEnabledLocally(
    String scriptName,
    String taskName,
    bool enable,
  ) {
    final script = scriptName.trim();
    final task = taskName.trim();
    if (script.isEmpty || task.isEmpty) {
      return;
    }
    final next = <String>{...?locallyDisabledTaskNames[script]};
    final changed = enable ? next.remove(task) : next.add(task);
    if (!changed) {
      return;
    }
    if (next.isEmpty) {
      locallyDisabledTaskNames.remove(script);
    } else {
      locallyDisabledTaskNames[script] = next;
    }
  }

  bool isTaskEnabled(ScriptModel model, String taskName) {
    final normalized = taskName.trim();
    if (normalized.isEmpty) {
      return false;
    }
    return enabledTaskNamesFor(model).contains(normalized);
  }

  HomeScriptStateFilter scriptStateFor(ScriptModel model) {
    return switch (model.state.value) {
      ScriptState.running => HomeScriptStateFilter.running,
      ScriptState.warning => HomeScriptStateFilter.abnormal,
      ScriptState.inactive => HomeScriptStateFilter.stopped,
      ScriptState.updating => HomeScriptStateFilter.offline,
    };
  }

  HomeScriptStateFilter scriptCollectionStateFor(ScriptModel model) {
    return switch (model.state.value) {
      ScriptState.running => HomeScriptStateFilter.running,
      ScriptState.warning => HomeScriptStateFilter.abnormal,
      ScriptState.inactive => HomeScriptStateFilter.stopped,
      ScriptState.updating => HomeScriptStateFilter.abnormal,
    };
  }

  void setSearchQuery(String value) {
    searchQuery.value = value.trim().toLowerCase();
    _ensureActiveScript(visibleScripts);
  }

  void setStateFilterValue(HomeScriptStateFilter value) {
    stateFilter.value = value;
    _ensureActiveScript(visibleScripts);
  }

  void setActiveScript(String scriptName) {
    final normalized = scriptName.trim();
    if (normalized.isEmpty) {
      return;
    }
    if (activeScriptName.value == normalized) {
      return;
    }
    activeScriptName.value = normalized;
  }

  void showScriptListPage() {
    clearActiveTask();
    workbenchPage.value = HomeWorkbenchPage.scripts;
  }

  void showWorkspacePage() {
    if (activeScriptName.value.trim().isEmpty) {
      return;
    }
    workbenchPage.value = HomeWorkbenchPage.workspace;
  }

  void toggleScriptSelected(String scriptName, bool selected) {
    final normalized = scriptName.trim();
    if (normalized.isEmpty) {
      return;
    }
    final updated = selectedScriptList.toSet();
    if (selected) {
      updated.add(normalized);
      activeScriptName.value = normalized;
    } else {
      updated.remove(normalized);
      if (activeScriptName.value == normalized) {
        final next = updated.isEmpty ? '' : updated.first;
        activeScriptName.value = next;
      }
    }
    selectedScriptList.value = updated.toList()..sort();
    _ensureActiveScript(visibleScripts);
  }

  void clearSelectedScripts() {
    selectedScriptList.clear();
    _ensureActiveScript(visibleScripts);
  }

  void setActiveWorkbenchTabValue(HomeWorkbenchTab value) {
    if (isHomeWorkbenchSidebarTab(value)) {
      activeWorkbenchSidebarTab.value = value;
    } else {
      _lastPrimaryWorkbenchTab.value = value;
    }
    if (value != HomeWorkbenchTab.tasks) {
      clearActiveTask();
    }
    activeWorkbenchTab.value = value;
  }

  void setActiveWorkbenchSidebarTabValue(HomeWorkbenchTab value) {
    if (!isHomeWorkbenchSidebarTab(value)) {
      return;
    }
    activeWorkbenchSidebarTab.value = value;
    if (workbenchLayoutMode.value != HomeWorkbenchLayoutMode.threePane) {
      setActiveWorkbenchTabValue(value);
    }
  }

  void setTaskCatalogFilterValue(HomeTaskCatalogFilter value) {
    taskCatalogFilter.value = value;
  }

  void openTaskParameters(
    String taskName, {
    required HomeTaskParameterEntrySource source,
  }) {
    final normalized = taskName.trim();
    if (normalized.isEmpty) {
      return;
    }
    activeTaskName.value = normalized;
    _taskParameterEntrySource.value = source;
    activeWorkbenchTab.value = HomeWorkbenchTab.tasks;
  }

  void clearActiveTask() {
    activeTaskName.value = '';
    _taskParameterEntrySource.value = null;
  }

  Future<void> closeTaskParameters() async {
    final returnTab = switch (_taskParameterEntrySource.value) {
      HomeTaskParameterEntrySource.overview => HomeWorkbenchTab.status,
      HomeTaskParameterEntrySource.tasks || null => HomeWorkbenchTab.tasks,
    };
    clearActiveTask();
    _lastPrimaryWorkbenchTab.value = returnTab;
    activeWorkbenchTab.value = returnTab;
  }

  void syncWorkspaceState() {
    _ensureActiveScript(visibleScripts);
  }

  Future<void> applySelectionPowerToggle({
    required String sourceScript,
    required bool enable,
  }) async {
    for (final name in _resolveScopeTargets(sourceScript)) {
      if (enable) {
        await _scriptService.startScript(name);
      } else {
        await _scriptService.stopScript(name);
      }
    }
  }

  Future<bool> applySelectionSetArgument({
    required String? config,
    required String? task,
    required String group,
    required String argument,
    required String type,
    required dynamic value,
  }) async {
    final source = (config ?? '').trim();
    if (source.isEmpty || task == null || task.isEmpty) {
      return false;
    }
    final argsController = Get.find<ArgsController>();
    var allSuccess = true;
    for (final target in _resolveScopeTargets(source)) {
      final ret = await argsController.setArgument(
        target,
        task,
        group,
        argument,
        type,
        value,
      );
      allSuccess = ret && allSuccess;
    }
    return allSuccess;
  }

  Future<bool> quickScheduleTask({
    required String scriptName,
    required String taskName,
    required bool runNow,
  }) async {
    if (!runNow) {
      return syncTaskNextRun(scriptName: scriptName, taskName: taskName);
    }
    final targetDt = formatDateTime(
      DateTime.now().add(const Duration(days: -1)),
    );
    return updateTaskNextRun(
      scriptName: scriptName,
      taskName: taskName,
      nextRun: targetDt,
    );
  }

  Future<bool> updateTaskNextRun({
    required String scriptName,
    required String taskName,
    required String nextRun,
  }) async {
    final source = scriptName.trim();
    final normalizedTask = taskName.trim();
    final normalizedNextRun = nextRun.trim();
    if (source.isEmpty || normalizedTask.isEmpty || normalizedNextRun.isEmpty) {
      return false;
    }
    final argsController = Get.find<ArgsController>();
    return _applyTaskActionAcrossLinkedScope(
      sourceScript: source,
      taskName: normalizedTask,
      action: (target, resolvedTask) {
        return argsController.updateScriptTaskNextRun(
          target,
          resolvedTask,
          normalizedNextRun,
        );
      },
    );
  }

  /// Routes one quick wait action through the dedicated sync endpoint.
  Future<bool> syncTaskNextRun({
    required String scriptName,
    required String taskName,
    String targetDt = '',
  }) async {
    final source = scriptName.trim();
    final normalizedTask = taskName.trim();
    if (source.isEmpty || normalizedTask.isEmpty) {
      return false;
    }
    return _applyTaskActionAcrossLinkedScope(
      sourceScript: source,
      taskName: normalizedTask,
      action: (target, resolvedTask) {
        return ApiClient().syncScriptTaskNextRun(
          target,
          resolvedTask,
          targetDt,
        );
      },
    );
  }

  Future<bool> quickToggleTaskEnabled({
    required String scriptName,
    required String taskName,
    required bool enable,
  }) async {
    return toggleTaskEnabled(
      scriptName: scriptName,
      taskName: taskName,
      enable: enable,
    );
  }

  /// Adds one task name to the bulk snapshot when it can be scheduled.
  void _addQuickScheduleTaskName(
    ScriptModel model,
    List<String> names,
    Set<String> seen,
    String value,
  ) {
    final taskName = value.trim();
    if (taskName.isEmpty || seen.contains(taskName)) {
      return;
    }
    if (!canQuickScheduleTask(model, taskName)) {
      return;
    }
    seen.add(taskName);
    names.add(taskName);
  }

  /// Serially invokes quick scheduling for a fixed task snapshot.
  Future<bool> _runBulkQuickScheduleTasks(
    String scriptName,
    List<String> taskNames,
    bool runNow,
  ) async {
    var allSuccess = true;
    for (final taskName in taskNames) {
      try {
        final ret = await quickScheduleTask(
          scriptName: scriptName,
          taskName: taskName,
          runNow: runNow,
        );
        allSuccess = ret && allSuccess;
      } catch (_) {
        allSuccess = false;
      }
    }
    return allSuccess;
  }

  /// Toggles one task enable flag, optionally across the linked scope.
  Future<bool> toggleTaskEnabled({
    required String scriptName,
    required String taskName,
    required bool enable,
    bool applyLinkedScope = true,
  }) async {
    final source = scriptName.trim();
    final normalizedTask = taskName.trim();
    if (source.isEmpty || normalizedTask.isEmpty) {
      return false;
    }
    final argsController = Get.find<ArgsController>();
    if (!applyLinkedScope) {
      final ok =
          await argsController.updateScriptTask(source, normalizedTask, enable);
      if (ok) {
        markTaskEnabledLocally(source, normalizedTask, enable);
      }
      return ok;
    }
    final targets = await _resolveLinkedTaskTargets(source, normalizedTask);
    if (targets.isEmpty) {
      return false;
    }
    var allSuccess = true;
    for (final target in targets) {
      final ret =
          await argsController.updateScriptTask(target, normalizedTask, enable);
      if (ret) {
        markTaskEnabledLocally(target, normalizedTask, enable);
      }
      allSuccess = ret && allSuccess;
    }
    return allSuccess;
  }

  bool _matchesVisibleFilter(ScriptModel model) {
    final query = searchQuery.value.trim();
    final stateMatched =
        stateFilter.value == HomeScriptStateFilter.all ||
        scriptCollectionStateFor(model) == stateFilter.value;
    if (!stateMatched) {
      return false;
    }
    if (query.isEmpty) {
      return true;
    }
    return model.name.toLowerCase().contains(query);
  }

  List<String> _resolveScopeTargets(String sourceScript) {
    final source = sourceScript.trim();
    return source.isEmpty ? const [] : [source];
  }

  Future<bool> _applyTaskActionAcrossLinkedScope({
    required String sourceScript,
    required String taskName,
    required Future<bool> Function(String scriptName, String taskName) action,
  }) async {
    final source = sourceScript.trim();
    final normalizedTask = taskName.trim();
    if (source.isEmpty || normalizedTask.isEmpty) {
      return false;
    }
    final targets = await _resolveLinkedTaskTargets(source, normalizedTask);
    if (targets.isEmpty) {
      return false;
    }
    var allSuccess = true;
    for (final target in targets) {
      final ret = await action(target, normalizedTask);
      allSuccess = ret && allSuccess;
    }
    return allSuccess;
  }

  Future<List<String>> _resolveLinkedTaskTargets(
    String sourceScript,
    String taskName,
  ) async {
    final source = sourceScript.trim();
    final normalizedTask = taskName.trim();
    if (source.isEmpty || normalizedTask.isEmpty) {
      return const [];
    }
    final scopeTargets = linkedScopeScriptsFor(source);
    if (scopeTargets.length <= 1) {
      return scopeTargets;
    }
    if (!scopeTargets.contains(source)) {
      return [source];
    }
    final targets = <String>[source];
    for (final target in scopeTargets) {
      if (target == source) {
        continue;
      }
      if (await _scriptContainsTask(target, normalizedTask)) {
        targets.add(target);
      }
    }
    return targets;
  }

  Future<bool> _scriptContainsTask(String scriptName, String taskName) async {
    final normalizedScript = scriptName.trim();
    final normalizedTask = taskName.trim();
    if (normalizedScript.isEmpty || normalizedTask.isEmpty) {
      return false;
    }
    final cacheKey = '$normalizedScript::$normalizedTask';
    final cached = _taskAvailabilityCache[cacheKey];
    if (cached != null) {
      return cached;
    }
    final taskData = await ApiClient().getScriptTask(
      normalizedScript,
      normalizedTask,
    );
    final supported = taskData.isNotEmpty;
    _taskAvailabilityCache[cacheKey] = supported;
    return supported;
  }

  void _ensureActiveScript(List<ScriptModel> candidates) {
    final current = activeScriptName.value.trim();
    final validNames = candidates.map((item) => item.name).toSet();
    if (current.isNotEmpty && validNames.contains(current)) {
      return;
    }
    if (candidates.isEmpty) {
      clearActiveTask();
      activeScriptName.value = '';
      workbenchPage.value = HomeWorkbenchPage.scripts;
      return;
    }
    activeScriptName.value = candidates.isEmpty ? '' : candidates.first.name;
  }
}
