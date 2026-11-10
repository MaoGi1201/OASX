part of 'api_client.dart';

extension ApiClientScriptX on ApiClient {
  /// Loads the full argument model for one task.
  ///
  /// 返回 `null` 表示这次请求失败（后端不可达、500 等）。调用方必须区分
  /// 「失败」和「这个任务没有参数组」：否则一次网络抖动会把参数表单清空，
  /// 或者把「任务不存在」的错误结论永久写进能力缓存。
  /// 参数是用户随时会改的数据，所以这里也绕开 7 天缓存，避免读到旧值。
  Future<Map<String, dynamic>?> getScriptTask(
    String scriptName,
    String taskName,
  ) async {
    final res = await request(
      () => get('/$scriptName/$taskName/args', options: _noCacheOptions()),
    );
    final data = res.data;
    if (!res.isSuccess || data is! Map) {
      return null;
    }
    return data.cast<String, dynamic>();
  }

  /// Persists one task argument through the generic value endpoint.
  Future<bool> putScriptArg(
    String scriptName,
    String taskName,
    String groupName,
    String argumentName,
    String type,
    dynamic value,
  ) async {
    final res = await request(
      () => put(
        '/$scriptName/$taskName/$groupName/$argumentName/value',
        queryParameters: {'types': type, 'value': value},
      ),
    );
    return res.isSuccess && res.data == true;
  }

  /// Synchronizes one task back into the waiting queue immediately.
  Future<bool> syncScriptTaskNextRun(
    String scriptName,
    String taskName,
    String targetDt,
  ) async {
    final res = await request(
      () => put(
        '/$scriptName/$taskName/sync_next_run',
        queryParameters: {'target_dt': targetDt},
      ),
    );
    return res.isSuccess && res.data == true;
  }
}
