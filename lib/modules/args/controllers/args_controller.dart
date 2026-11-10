part of args;

class ArgsController extends GetxController {
  final groups = Rx<List<GroupsModel>>([]);
  final groupsName = Rx<List<String>>([]);
  final groupsData = Rx<Map<String, GroupsModel>>({});
  final dirtyFieldKeys = <String>{}.obs;
  final fieldErrors = <String, String>{}.obs;
  final isDraftMode = false.obs;
  final isSavingDraft = false.obs;
  final scopeScriptCount = 1.obs;
  static const String schedulerGroup = 'scheduler';
  static const String nextRunArg = 'next_run';
  static const String enableArg = 'enable';
  static final RegExp _dateTimePattern =
      RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$');
  static final RegExp _timePattern = RegExp(r'^\d{2}:\d{2}:\d{2}$');
  static final RegExp _timeDeltaPattern = RegExp(r'^\d{2,} \d{2}:\d{2}:\d{2}$');

  final Map<String, dynamic> _originalValues = {};
  String _loadedConfig = '';
  String _loadedTask = '';

  /// 每次 [loadGroups] 领一个版本号。
  ///
  /// 连点两个任务时，A 的 `/args` 回包可能晚于 B 到达。没有版本校验就会把
  /// A 的参数写进「当前=B」的表单，紧接着 `saveDraftChanges` 用 `_loadedTask`
  /// 落盘，就把 A 的值写到了 B 的配置里。
  int _loadRevision = 0;
  List<String> _scopeScripts = const [];
  SaveArgumentCallback? _saveArgumentOverride;

  static bool isImmediateSchedulingField(String group, String argument) {
    return group == schedulerGroup && argument == nextRunArg;
  }

  void loadModel(Map<String, dynamic> json) {
    groups.value = [];
    json.forEach((key, value) {
      groups.value.add(GroupsModel(groupName: key, members: value));
    });
  }

  void loadModelfromStr(String json) {
    loadModel(jsonDecode(json));
  }

  /// 加载某个任务的参数模型。
  ///
  /// 返回 `false` 只代表「这次请求失败」，调用方可以据此提示错误；
  /// 被更新的加载取代时返回 `true`（不是错误，不要弹红条）。
  Future<bool> loadGroups({
    String config = '',
    String task = '',
    bool stagingMode = false,
    List<String> scopeScripts = const [],
    SaveArgumentCallback? saveArgumentOverride,
  }) async {
    final revision = ++_loadRevision;
    updateScopeScripts(scopeScripts, config: config);
    _saveArgumentOverride = saveArgumentOverride;
    isDraftMode.value = stagingMode;
    dirtyFieldKeys.clear();
    fieldErrors.clear();
    _originalValues.clear();

    final json = await ApiClient().getScriptTask(config, task);
    // 期间又切了任务：这次回包作废，别覆盖更新的那次加载结果。
    if (revision != _loadRevision) {
      return true;
    }
    // 请求失败时保留表单现状，不能当成「这个任务没有参数」把界面清空。
    if (json == null) {
      return false;
    }
    // _loaded* 只在数据真的落地时才更新，保证「表单里看到的」和
    // 「保存时写回去的」始终是同一个配置 + 任务。
    _loadedConfig = config;
    _loadedTask = task;

    final groupsMap = <String, GroupsModel>{};
    final names = <String>[];
    for (final entry in json.entries) {
      names.add(entry.key);
      final arguments = <ArgumentModel>[];
      for (final argument in entry.value) {
        arguments.add(ArgumentModel.fromJson(argument));
      }
      groupsMap[entry.key] =
          GroupsModel(groupName: entry.key, members: arguments);
    }
    groupsData.value = groupsMap;
    groupsName.value = names;
    _snapshotOriginalValues();
    return true;
  }

  Future<dynamic> getArgValue(
      String config, String task, String group, String argument) {
    if (groupsData.value.isEmpty) {
      loadGroups(config: config, task: task);
    }
    return groupsData.value[group]!.members
        .map((e) => e as ArgumentModel)
        .firstWhere((element) => element.title == argument)
        .value;
  }

  Future<bool> setArgument(String? config, String? task, String group,
      String argument, String type, dynamic value) async {
    if (config == null || task == null || config.isEmpty || task.isEmpty) {
      return false;
    }
    final ret = await ApiClient()
        .putScriptArg(config, task, group, argument, type, value);
    if (ret && group == schedulerGroup) {
      await Get.find<WebSocketService>().send(config, 'get_schedule');
    }
    return ret;
  }

  Future<bool> updateScriptTaskNextRun(
      String config, String task, String nextRun) async {
    return setArgument(
        config, task, schedulerGroup, nextRunArg, 'next_run', nextRun);
  }

  Future<bool> updateScriptTask(String config, String task, bool enable) async {
    return setArgument(
        config, task, schedulerGroup, enableArg, 'boolean', enable);
  }

  void stageArgumentChange(
      String group, String argument, dynamic value, String type) {
    final model = findArgument(group, argument);
    if (model == null) {
      return;
    }
    model.value = value;
    final key = _fieldKey(group, argument);
    if (_isEqualValue(_originalValues[key], value)) {
      dirtyFieldKeys.remove(key);
    } else {
      dirtyFieldKeys.add(key);
    }
    final error = validateArgument(model, value);
    if (error == null || error.isEmpty) {
      fieldErrors.remove(key);
    } else {
      fieldErrors[key] = error;
    }
    if (!dirtyFieldKeys.contains(key)) {
      fieldErrors.remove(key);
    }
    fieldErrors.refresh();
  }

  void discardDraftField(String group, String argument) {
    final key = _fieldKey(group, argument);
    final model = findArgument(group, argument);
    final hasOriginal = _originalValues.containsKey(key);
    var shouldRefreshModel = false;
    if (model != null &&
        hasOriginal &&
        !_isEqualValue(model.value, _originalValues[key])) {
      model.value = _originalValues[key];
      shouldRefreshModel = true;
    }
    final removedDirty = dirtyFieldKeys.remove(key);
    final removedError = fieldErrors.remove(key) != null;
    if (!shouldRefreshModel && !removedDirty && !removedError) {
      return;
    }
    dirtyFieldKeys.refresh();
    fieldErrors.refresh();
    if (shouldRefreshModel) {
      groups.refresh();
      groupsData.refresh();
    }
  }

  ArgumentModel? findArgument(String group, String argument) {
    final groupModel = groupsData.value[group];
    if (groupModel == null) {
      return null;
    }
    return groupModel.members.cast<ArgumentModel>().firstWhereOrNull(
          (item) => item.title == argument,
        );
  }

  bool isFieldDirty(String group, String argument) {
    return dirtyFieldKeys.contains(_fieldKey(group, argument));
  }

  String? fieldError(String group, String argument) {
    return fieldErrors[_fieldKey(group, argument)];
  }

  bool get hasDraftChanges => dirtyFieldKeys.isNotEmpty;

  String get currentConfig => _loadedConfig;

  String get currentTask => _loadedTask;

  List<String> get scopeScripts => _scopeScripts;

  void updateScopeScripts(List<String> scopeScripts, {String config = ''}) {
    _scopeScripts = _normalizeScope(scopeScripts, config);
    scopeScriptCount.value = _scopeScripts.isEmpty ? 1 : _scopeScripts.length;
  }

  Future<void> discardDraftChanges() async {
    for (final entry in groupsData.value.entries) {
      for (final member in entry.value.members.cast<ArgumentModel>()) {
        final key = _fieldKey(entry.key, member.title);
        if (_originalValues.containsKey(key)) {
          member.value = _originalValues[key];
        }
      }
    }
    dirtyFieldKeys.clear();
    fieldErrors.clear();
    groups.refresh();
    groupsData.refresh();
  }

  Future<bool> saveDraftChanges() async {
    if (!isDraftMode.value || _loadedConfig.isEmpty || _loadedTask.isEmpty) {
      return false;
    }
    final errors = _collectValidationErrors();
    fieldErrors
      ..clear()
      ..addAll(errors);
    fieldErrors.refresh();
    if (errors.isNotEmpty) {
      return false;
    }
    if (dirtyFieldKeys.isEmpty) {
      return true;
    }

    isSavingDraft.value = true;
    var allSuccess = true;
    final targets = _saveArgumentOverride == null
        ? (_scopeScripts.isEmpty ? [_loadedConfig] : _scopeScripts)
        : [_loadedConfig];
    final savedKeys = <String>{};
    try {
      for (final key in dirtyFieldKeys.toList()) {
        final field = _decodeFieldKey(key);
        final model = findArgument(field.group, field.argument);
        if (model == null) {
          continue;
        }
        var fieldSuccess = true;
        for (final config in targets) {
          final ret = await _persistArgument(
            config: config,
            task: _loadedTask,
            group: field.group,
            argument: field.argument,
            type: model.type,
            value: model.value,
          );
          fieldSuccess = ret && fieldSuccess;
        }
        allSuccess = fieldSuccess && allSuccess;
        if (fieldSuccess) {
          _originalValues[key] = model.value;
          savedKeys.add(key);
        }
      }
      if (savedKeys.isNotEmpty) {
        dirtyFieldKeys.removeAll(savedKeys);
      }
      dirtyFieldKeys.refresh();
      return allSuccess;
    } finally {
      isSavingDraft.value = false;
    }
  }

  String? validateArgument(ArgumentModel model, dynamic value) {
    final current = value?.toString() ?? '';
    return switch (model.type) {
      'integer' => _validateInteger(model, current),
      'number' => _validateNumber(model, current),
      'date_time' =>
        _dateTimePattern.hasMatch(current) ? null : I18n.argsInvalidDateTime.tr,
      'time' => _timePattern.hasMatch(current) ? null : I18n.argsInvalidTime.tr,
      'time_delta' => _timeDeltaPattern.hasMatch(current)
          ? null
          : I18n.argsInvalidTimeDelta.tr,
      'enum' => _validateEnum(model, current),
      _ => null,
    };
  }

  Map<String, String> _collectValidationErrors() {
    final errors = <String, String>{};
    for (final entry in groupsData.value.entries) {
      for (final model in entry.value.members.cast<ArgumentModel>()) {
        final error = validateArgument(model, model.value);
        if (error != null && error.isNotEmpty) {
          errors[_fieldKey(entry.key, model.title)] = error;
        }
      }
    }
    return errors;
  }

  Future<bool> _persistArgument({
    required String config,
    required String task,
    required String group,
    required String argument,
    required String type,
    required dynamic value,
  }) async {
    if (_saveArgumentOverride != null) {
      return _saveArgumentOverride!(
        config,
        task,
        group,
        argument,
        type,
        value,
      );
    }
    return setArgument(config, task, group, argument, type, value);
  }

  List<String> _normalizeScope(List<String> raw, String config) {
    final result = raw
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (config.isNotEmpty && !result.contains(config)) {
      result.insert(0, config);
    }
    return result;
  }

  void _snapshotOriginalValues() {
    for (final entry in groupsData.value.entries) {
      for (final model in entry.value.members.cast<ArgumentModel>()) {
        _originalValues[_fieldKey(entry.key, model.title)] = model.value;
      }
    }
  }

  bool _isEqualValue(dynamic left, dynamic right) {
    return left?.toString() == right?.toString();
  }

  String _fieldKey(String group, String argument) {
    return '$group::$argument';
  }

  _FieldDescriptor _decodeFieldKey(String value) {
    final parts = value.split('::');
    return _FieldDescriptor(
      group: parts.first,
      argument: parts.length > 1 ? parts[1] : '',
    );
  }

  String? _validateEnum(ArgumentModel model, String value) {
    final options = model.enumEnum ?? const <String>[];
    if (options.isEmpty || options.contains(value)) {
      return null;
    }
    return I18n.argsInvalidEnum.tr;
  }

  String? _validateInteger(ArgumentModel model, String value) {
    final parsed = int.tryParse(value);
    if (parsed == null) {
      return I18n.argsInvalidInteger.tr;
    }
    final minimum = _numValue(model.minimum);
    if (minimum != null && parsed < minimum) {
      return '${I18n.argsMinValue.tr} $minimum';
    }
    final maximum = _numValue(model.maximum);
    if (maximum != null && parsed > maximum) {
      return '${I18n.argsMaxValue.tr} $maximum';
    }
    return null;
  }

  String? _validateNumber(ArgumentModel model, String value) {
    final parsed = num.tryParse(value);
    if (parsed == null) {
      return I18n.argsInvalidNumber.tr;
    }
    final minimum = _numValue(model.minimum);
    if (minimum != null && parsed < minimum) {
      return '${I18n.argsMinValue.tr} $minimum';
    }
    final maximum = _numValue(model.maximum);
    if (maximum != null && parsed > maximum) {
      return '${I18n.argsMaxValue.tr} $maximum';
    }
    return null;
  }

  num? _numValue(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value;
    }
    return num.tryParse(value.toString());
  }
}

class GroupsModel {
  final String groupName;
  List<dynamic> members;

  GroupsModel({required this.groupName, required this.members});

  String getGroupName() => groupName;
}

class ArgumentModel {
  final String title;
  dynamic value;
  final String type;
  final String? description;
  final List<String>? enumEnum;
  final dynamic minimum;
  final dynamic maximum;
  final dynamic defaultValue;

  ArgumentModel(
    this.enumEnum,
    this.minimum,
    this.maximum,
    this.defaultValue,
    this.description, {
    required this.title,
    required this.value,
    required this.type,
  });

  factory ArgumentModel.fromJson(Map<String, dynamic> json) {
    return ArgumentModel(
      List<String>.from(json['enumEnum']?.map((item) => item) ?? []),
      json['minimum'],
      json['maximum'],
      json['defaultValue'],
      json['description'],
      title: json['name'] as String,
      value: json['value'],
      type: json['type'] as String,
    );
  }

  set setValue(dynamic newValue) => value = newValue;
}

class _FieldDescriptor {
  const _FieldDescriptor({
    required this.group,
    required this.argument,
  });

  final String group;
  final String argument;
}
