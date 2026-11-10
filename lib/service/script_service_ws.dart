part of 'script_service.dart';

extension ScriptServiceWsX on ScriptService {
  Future<void> connectScript(String name) async {
    if (!scriptModelMap.containsKey(name)) {
      addScriptModel(name);
    }
    wsService.removeAllListeners(name);
    final client = await wsService.connect(
      name: name,
      listener: (mg) => wsListener(mg, name),
    );
    await _wsStatusSubscriptions.remove(name)?.cancel();
    _wsStatusSubscriptions[name] = client.status.listen(
      (wsStatus) => _applyWsStatus(name, wsStatus),
    );
    // 连接已存在时服务端不会重复推 state，主动要一次，避免刷新后停留在旧状态。
    if (client.status.value == WsStatus.connected) {
      await wsService.send(name, 'get_state');
    }
  }

  /// 把 WS 传输状态反映到脚本状态上。
  ///
  /// `connected` 只代表 WebSocket 建连成功，**不代表脚本在跑**。这里不能再把
  /// 它映射成 [ScriptState.running]：服务端建连后会立刻推一帧真实的 `state`，
  /// 而 [Rx.listen] 订阅时会立即回调一次当前值，于是刚拿到的 `inactive` 会被
  /// `connected` 覆盖回去 —— 电源按钮显示成「停止」，`startScript()` 又因
  /// `isRunning` 直接 return，用户点启动毫无反应。
  /// 运行状态只信服务端的 `state` 帧，这里只处理服务端告知不了我们的断线情况。
  void _applyWsStatus(String name, WsStatus wsStatus) {
    final model = scriptModelMap[name];
    if (model == null) {
      return;
    }
    switch (wsStatus) {
      case WsStatus.connecting:
      case WsStatus.connected:
        // 交给服务端推送的 state，这里不猜。
        break;
      case WsStatus.reconnecting:
      case WsStatus.error:
        // 断线期间拿不到真实状态，按「异常」呈现，重连后由 state 帧纠正。
        model.update(state: ScriptState.warning);
      case WsStatus.closed:
        // 连接被关闭通常意味着该配置已停止或被移除，按「离线」呈现。
        model.update(state: ScriptState.updating);
    }
  }

  Future<void> startScript(String name) async {
    if (!scriptModelMap.containsKey(name)) return;
    if (isRunning(name)) return;
    await connectScript(name);
    await wsService.send(name, 'start');
  }

  void wsListener(dynamic message, String name) {
    if (message is! String) {
      printError(info: 'Websocket push data is not of type string and map');
      return;
    }
    if (!message.startsWith('{') || !message.endsWith('}')) {
      return;
    }
    final data = jsonDecode(message) as Map<String, dynamic>;
    if (data.containsKey('state')) {
      scriptModelMap[name]!.update(state: ScriptState.getState(data['state']));
      return;
    }
    if (!data.containsKey('schedule')) {
      return;
    }

    final run = data['schedule']['running'] as Map;
    final pending = data['schedule']['pending'] as List<dynamic>;
    final waiting = data['schedule']['waiting'] as List<dynamic>;
    final runningTask = run.isNotEmpty
        ? TaskItemModel(name, run['name'], run['next_run'])
        : TaskItemModel.empty();
    final pendingList = pending
        .map((e) => TaskItemModel(name, e['name'], e['next_run']))
        .toList();
    final waitingList = waiting
        .map((e) => TaskItemModel(name, e['name'], e['next_run']))
        .toList();
    scriptModelMap[name]!.update(
      runningTask: runningTask,
      pendingTaskList: pendingList,
      waitingTaskList: waitingList,
    );
  }

  Future<void> stopScript(String name) async {
    if (!scriptModelMap.containsKey(name)) return;
    await wsService.send(name, 'stop');
  }
}
