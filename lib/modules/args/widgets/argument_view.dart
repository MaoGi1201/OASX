part of args;

class ArgumentView extends StatefulWidget {
  const ArgumentView({
    required this.setArgument,
    required this.getGroupName,
    required this.index,
    this.lockImmediateScheduling = false,
    Key? key,
    this.scriptName,
    this.taskName,
  }) : super(key: key);

  final SetArgumentCallback setArgument;
  final String Function() getGroupName;
  final int index;
  final bool lockImmediateScheduling;
  final String? scriptName;
  final String? taskName;

  @override
  State<ArgumentView> createState() => _ArgumentViewState();
}

class _ArgumentViewState extends State<ArgumentView> {
  Timer? timer;
  bool landscape = true;
  late final TextEditingController _textController;
  late final FocusNode _focusNode;

  ArgumentModel get model {
    final controller = Get.find<ArgsController>();
    final groupsModel = controller.groupsData.value[widget.getGroupName()];
    return groupsModel!.members[widget.index];
  }

  ArgsController get _argsController => Get.find<ArgsController>();

  bool get _isProtectedImmediateScheduleField {
    return widget.lockImmediateScheduling &&
        ArgsController.isImmediateSchedulingField(
          widget.getGroupName(),
          model.title,
        );
  }

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: model.value.toString());
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    timer?.cancel();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      landscape = MediaQuery.of(context).orientation == Orientation.landscape;
      _syncTextController();
      final title = _title();
      final form = _buildFormSection();
      if (landscape) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            const SizedBox(width: 12),
            Expanded(child: form),
          ],
        ).padding(bottom: 8);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [title, form],
      ).padding(bottom: 8);
    });
  }

  Widget _title() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          model.title.tr,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (model.description != null && model.description!.isNotEmpty)
          SelectableText(
            model.description!.tr,
            style: Theme.of(context).textTheme.bodySmall,
          ).padding(top: 4),
      ],
    );
  }

  Widget _buildFormSection() {
    final errorText =
        _argsController.fieldError(widget.getGroupName(), model.title);
    final isLocked = _isProtectedImmediateScheduleField;
    final child = switch (model.type) {
      'boolean' => Checkbox(
          value: model.value,
          onChanged: isLocked ? null : onCheckboxChanged,
        ).alignment(Alignment.centerLeft),
      'string' => _buildTextField(errorText: errorText, enabled: !isLocked),
      'multi_line' => _buildTextField(
          errorText: errorText,
          maxLines: null,
          enabled: !isLocked,
        ),
      'number' => _buildTextField(
          errorText: errorText,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[-0-9.]')),
          ],
          onChanged: _scheduleNumberChange,
          enabled: !isLocked,
        ),
      'integer' => _buildTextField(
          errorText: errorText,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[-0-9]')),
          ],
          onChanged: _scheduleIntegerChange,
          enabled: !isLocked,
        ),
      'enum' => _buildEnumField(errorText: errorText, enabled: !isLocked),
      'date_time' => _buildPicker(
          DateTimePicker(value: model.value, onChange: onDateTimeChanged),
          errorText,
          enabled: !isLocked,
        ),
      'time_delta' => _buildPicker(
          TimeDeltaPicker(
            value: ensureTimeDeltaString(model.value),
            onChange: onTimeDeltaChanged,
          ),
          errorText,
          enabled: !isLocked,
        ),
      'time' => _buildPicker(
          TimePicker(value: model.value, onChange: onTimeChanged),
          errorText,
          enabled: !isLocked,
        ),
      _ => Text(model.value.toString()),
    };
    return child;
  }

  /// 枚举字段：闭合态是一个和其它输入框同款的下拉框，展开后走全局统一的
  /// [showAppMenu]（Material 的 DropdownButton 展开的是自己的 48px 通栏列表）。
  ///
  /// 这里用 `Builder` 拿字段**自己**的 context：直接用 State 的 `context` 会锚到
  /// 整行（横屏时还包含左边的标题），菜单会贴着对话框左边缘展开、跟输入框错位。
  Widget _buildEnumField({required String? errorText, required bool enabled}) {
    return Builder(
      builder: (fieldContext) => InputDecorator(
        decoration: InputDecoration(errorText: errorText),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? () => _openEnumMenu(fieldContext) : null,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  model.value.toString().tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: AppColors.text),
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AppColors.text3,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 该分支固定使用模拟器，emulator_control 不提供 desktop 选项。
  List<String> _enumOptions() {
    final values = model.enumEnum ?? const <String>[];
    if (model.title != 'emulator_control') {
      return values;
    }
    return values.where((item) => item != 'desktop').toList(growable: false);
  }

  Future<void> _openEnumMenu(BuildContext fieldContext) async {
    final values = _enumOptions();
    if (values.isEmpty) {
      return;
    }
    final picked = await showAppMenu<String>(
      fieldContext,
      options: [
        for (final value in values)
          AppMenuOption(value: value, label: value.tr),
      ],
      selected: model.value.toString(),
      maxVisibleItems: 10,
      // 菜单与输入框同宽、左缘对齐，读起来像一个原生 select。
      anchor: AppMenuAnchor.start,
      matchAnchorWidth: true,
    );
    if (picked != null) {
      onEnumChanged(picked);
    }
  }

  Widget _buildTextField({
    required String? errorText,
    bool enabled = true,
    int? maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
  }) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final isSingleLine = maxLines == 1;
    return TextFormField(
      controller: _textController,
      focusNode: _focusNode,
      enabled: enabled,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      scrollPadding: EdgeInsets.only(
        left: 12,
        top: 12,
        right: 12,
        bottom: keyboardInset > 0 ? keyboardInset + 24 : 24,
      ),
      textInputAction:
          isSingleLine ? TextInputAction.done : TextInputAction.newline,
      decoration: InputDecoration(errorText: errorText),
      onTapOutside:
          PlatformUtils.isWeb ? null : (_) => _focusNode.unfocus(),
      onEditingComplete: PlatformUtils.isWeb
          ? null
          : (isSingleLine ? _focusNode.unfocus : null),
      onChanged: onChanged ?? _scheduleStringChange,
    );
  }

  Widget _buildPicker(
    Widget picker,
    String? errorText, {
    bool enabled = true,
  }) {
    return IgnorePointer(
      ignoring: !enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            picker,
            if (errorText != null && errorText.isNotEmpty)
              Text(
                errorText,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ).padding(top: 4),
          ],
        ),
      ),
    );
  }

  void _syncTextController() {
    if (_focusNode.hasFocus) {
      return;
    }
    final nextValue = model.value.toString();
    if (_textController.text == nextValue) {
      return;
    }
    _textController.value = TextEditingValue(
      text: nextValue,
      selection: TextSelection.collapsed(offset: nextValue.length),
    );
  }

  void _scheduleStringChange(String value) {
    timer?.cancel();
    timer =
        Timer(const Duration(milliseconds: 150), () => onStringChanged(value));
  }

  void _scheduleNumberChange(String value) {
    timer?.cancel();
    timer =
        Timer(const Duration(milliseconds: 150), () => onNumberChanged(value));
  }

  void _scheduleIntegerChange(String value) {
    timer?.cancel();
    timer =
        Timer(const Duration(milliseconds: 150), () => onIntegerChanged(value));
  }
}
