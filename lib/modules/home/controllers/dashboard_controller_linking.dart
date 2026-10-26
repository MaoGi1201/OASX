part of 'dashboard_controller.dart';

extension HomeDashboardLinkingX on HomeDashboardController {
  void toggleLinkMode() {
    final next = !isLinkModeEnabled.value;
    isLinkModeEnabled.value = next;
    if (!next) {
      linkedScriptList.clear();
    }
  }

  void setScriptLinked(String scriptName, bool linked) {
    if (!isLinkModeEnabled.value) {
      return;
    }
    final name = scriptName.trim();
    if (name.isEmpty) {
      return;
    }
    final updated = linkedScriptList.toSet();
    if (linked) {
      updated.add(name);
    } else {
      updated.remove(name);
    }
    linkedScriptList.value = updated.toList()..sort();
  }

  bool isScriptLinked(String scriptName) {
    return linkedScriptList.contains(scriptName.trim());
  }

  List<String> get validLinkedScripts => linkedScriptList
      .where((name) => _scriptService.scriptModelMap.containsKey(name))
      .toSet()
      .toList()
    ..sort();

  List<String> linkedScopeScriptsFor(String sourceScript) {
    return _collectCascadeTargets(sourceScript);
  }

  bool shouldCascadeFrom(String sourceScript) {
    final source = sourceScript.trim();
    if (!isLinkModeEnabled.value || source.isEmpty) {
      return false;
    }
    return validLinkedScripts.contains(source);
  }

  /// 除 [sourceScript] 之外可被连接进来的配置（用于连接器弹窗的勾选列表）。
  List<String> linkCandidatesFor(String sourceScript) {
    final source = sourceScript.trim();
    return _scriptService.scriptOrderList
        .where((name) => name != source)
        .toList(growable: false);
  }

  /// [sourceScript] 是否真的会参与同步：自己勾上了，且至少还有一个别的配置。
  ///
  /// `_collectCascadeTargets` 依赖 `shouldCascadeFrom`，也就是「源配置本身必须
  /// 在勾选列表里」，所以只看 `validLinkedScripts` 是否非空是不够的。
  bool hasActiveLinkFor(String sourceScript) {
    if (!isLinkModeEnabled.value) {
      return false;
    }
    final source = sourceScript.trim();
    final links = validLinkedScripts;
    return links.contains(source) && links.length > 1;
  }

  Future<void> applyLinkedPowerToggle({
    required String sourceScript,
    required bool enable,
  }) async {
    final targets = _collectCascadeTargets(sourceScript);
    for (final name in targets) {
      if (enable) {
        await _scriptService.startScript(name);
      } else {
        await _scriptService.stopScript(name);
        // 停止后重新拉一次 schedule，刚停下的任务才不会从列表里消失。
        _scriptService.wsService.send(name, 'get_schedule');
      }
    }
  }

  /// 在连接作用域内对同一任务执行「立即执行 / 延后」。
  Future<bool> quickScheduleTaskAcrossLink({
    required String scriptName,
    required String taskName,
    required bool runNow,
  }) async {
    final targets = linkedScopeScriptsFor(scriptName);
    var allSuccess = true;
    for (final target in targets) {
      final ok = await quickScheduleTask(
        scriptName: target,
        taskName: taskName,
        runNow: runNow,
      );
      allSuccess = ok && allSuccess;
    }
    return allSuccess;
  }

  /// 在连接作用域内对同一任务做启用 / 停用。
  Future<bool> quickToggleTaskEnabledAcrossLink({
    required String scriptName,
    required String taskName,
    required bool enable,
  }) async {
    final targets = linkedScopeScriptsFor(scriptName);
    var allSuccess = true;
    for (final target in targets) {
      final ok = await quickToggleTaskEnabled(
        scriptName: target,
        taskName: taskName,
        enable: enable,
      );
      allSuccess = ok && allSuccess;
    }
    return allSuccess;
  }

  Future<bool> applyLinkedSetArgument({
    required String? config,
    required String? task,
    required String group,
    required String argument,
    required String type,
    required dynamic value,
  }) async {
    final source = (config ?? '').trim();
    final normalizedTask = (task ?? '').trim();
    if (source.isEmpty || normalizedTask.isEmpty) {
      return false;
    }
    final argsController = Get.find<ArgsController>();
    return _applyTaskActionAcrossLinkedScope(
      sourceScript: source,
      taskName: normalizedTask,
      action: (target, resolvedTask) {
        return argsController.setArgument(
          target,
          resolvedTask,
          group,
          argument,
          type,
          value,
        );
      },
    );
  }

  List<String> _collectCascadeTargets(String sourceScript) {
    final source = sourceScript.trim();
    if (source.isEmpty) {
      return const [];
    }
    if (!shouldCascadeFrom(source)) {
      return [source];
    }
    final targets = validLinkedScripts.toSet();
    if (!targets.contains(source)) {
      return [source];
    }
    return targets.toList()..sort();
  }
}
