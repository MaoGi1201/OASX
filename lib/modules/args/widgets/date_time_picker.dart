// ignore_for_file: must_be_immutable

part of args;

final dateDaysInWeek =
    List.generate(7, (index) => index < 10 ? '0$index' : '$index').toList();
final dateHours =
    List.generate(24, (index) => index < 10 ? '0$index' : '$index').toList();
final dateMinutes =
    List.generate(60, (index) => index < 10 ? '0$index' : '$index').toList();
final dateSeconds =
    List.generate(60, (index) => index < 10 ? '0$index' : '$index').toList();

final dateTimeDelta = [
  dateDaysInWeek,
  dateHours,
  dateMinutes,
  dateSeconds,
];
final dateTime = [
  dateHours,
  dateMinutes,
  dateSeconds,
];

String ensureTimeDeltaString(dynamic value) {
  if (value is String) {
    return value;
  }
  if (value is int || value is double) {
    final duration = Duration(seconds: value.toInt());
    final day0 = duration.inDays;
    final hour0 = duration.inHours.remainder(24);
    final minute0 = duration.inMinutes.remainder(60);
    final second = duration.inSeconds.remainder(60);

    final day = day0 < 10 ? '0$day0' : '$day0';
    final hour = hour0 < 10 ? '0$hour0' : '$hour0';
    final minute = minute0 < 10 ? '0$minute0' : '$minute0';
    final seconds = second < 10 ? '0$second' : '$second';
    return '$day $hour:$minute:$seconds';
  }
  return '00 00:00:00';
}

class DateTimePickerBase extends StatefulWidget {
  DateTimePickerBase({
    super.key,
    required this.value,
    required this.onChange,
    this.hoverStyle,
    this.notHoverStyle,
  });

  String value = '';
  final TextStyle? hoverStyle;
  final TextStyle? notHoverStyle;
  void Function(String value) onChange = (value) {};

  @override
  State<StatefulWidget> createState() => DateTimePickerBaseState();
}

class DateTimePickerBaseState extends State<DateTimePickerBase> {
  bool _isHover = false;

  /// Labels of the editable time components.
  List<String> get componentLabels => const ['时', '分', '秒'];

  String _pad(String value) => value.padLeft(2, '0');

  /// Splits [value] into editable component strings.
  List<String> parseComponents(String value) {
    final parts = value
        .split(RegExp(r'\D+'))
        .where((part) => part.isNotEmpty)
        .toList();
    while (parts.length < componentLabels.length) {
      parts.insert(0, '0');
    }
    return parts
        .take(componentLabels.length)
        .map(_pad)
        .toList(growable: false);
  }

  /// Joins editable component strings back into the stored format.
  String joinComponents(List<String> parts) => parts.map(_pad).join(':');

  @override
  Widget build(BuildContext context) {
    final hoverStyle = widget.hoverStyle ??
        TextStyle(color: Theme.of(context).primaryColor, fontSize: 16);
    final notHoverStyle = widget.notHoverStyle ?? const TextStyle(fontSize: 16);
    final baseHeight = (hoverStyle.fontSize ?? 16) * 1.2;
    final outline = Theme.of(context).colorScheme.outline;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHover = true),
          onExit: (_) => setState(() => _isHover = false),
          child: Text(widget.value, style: _isHover ? hoverStyle : notHoverStyle)
              .scale(
                all: _isHover ? 1.1 : 1.0,
                alignment: Alignment.centerLeft,
                animate: true,
              )
              .animate(const Duration(milliseconds: 120), Curves.easeOut)
              .constrained(height: baseHeight)
              .gestures(onTap: () => showPicker(context, widget.value)),
        ),
        _MiniIconAction(
          icon: Icons.av_timer_rounded,
          tooltip: '分项修改',
          color: outline,
          onTap: () => _showComponentsEditor(context),
        ),
      ],
    );
  }

  /// Opens a dialog that edits each time component in its own field, so the
  /// user does not have to scroll a wheel or type a full formatted string.
  Future<void> _showComponentsEditor(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _ComponentsEditorDialog(
        labels: componentLabels,
        initial: parseComponents(widget.value),
        joinValue: joinComponents,
      ),
    );
    if (result == null || result.isEmpty) {
      return;
    }
    widget.onChange(result);
  }

  void showPicker(context, dynamic value) {
    final now = DateTime.now();
    final minDate = DateTime(now.year - 1, 1, 1);
    final maxDate = DateTime(now.year + 1, 12, 31, 23, 59, 59);
    Pickers.showDatePicker(
      context,
      mode: DateMode.YMDHMS,
      pickerStyle: Theme.of(context).brightness == Brightness.light
          ? DefaultPickerStyle()
          : DefaultPickerStyle.dark(),
      suffix: Suffix(
        years: I18n.year.tr,
        month: I18n.month.tr,
        days: I18n.day.tr,
        hours: I18n.hour.tr,
        minutes: I18n.minute.tr,
        seconds: I18n.seconds.tr,
      ),
      minDate: PDuration.parse(minDate),
      maxDate: PDuration.parse(maxDate),
      selectDate: _clampSelectedDate(value, minDate, maxDate),
      onConfirm: (p) => widget.onChange(_formatPickerValue(p)),
    );
  }

  PDuration _clampSelectedDate(
    dynamic value,
    DateTime minDate,
    DateTime maxDate,
  ) {
    final parsed = _parsePickerValue(value) ?? DateTime.now();
    final normalized = parsed.isBefore(minDate)
        ? minDate
        : parsed.isAfter(maxDate)
            ? maxDate
            : parsed;
    return PDuration.parse(normalized);
  }

  DateTime? _parsePickerValue(dynamic value) {
    if (value is! String) {
      return null;
    }
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return DateTime.tryParse(normalized.replaceFirst(' ', 'T'));
  }

  String _formatPickerValue(PDuration value) {
    final year = value.year ?? 0;
    final month = _twoDigits(value.month);
    final day = _twoDigits(value.day);
    final hour = _twoDigits(value.hour);
    final minute = _twoDigits(value.minute);
    final second = _twoDigits(value.second);
    return '$year-$month-$day $hour:$minute:$second';
  }

  String _twoDigits(int? value) {
    final normalized = value ?? 0;
    return normalized < 10 ? '0$normalized' : '$normalized';
  }
}

/// 「分项修改时间」弹窗。
///
/// controllers / FocusNode 必须由弹窗自身持有，并在它自己的 dispose 里释放：
/// 如果在 `await showDialog(...)` 返回后立刻 dispose，弹窗此时还在播放退出动画、
/// TextField 仍然挂着这些节点，就会抛
/// "A FocusNode was used after being disposed"。
class _ComponentsEditorDialog extends StatefulWidget {
  const _ComponentsEditorDialog({
    required this.labels,
    required this.initial,
    required this.joinValue,
  });

  final List<String> labels;
  final List<String> initial;
  final String Function(List<String> parts) joinValue;

  @override
  State<_ComponentsEditorDialog> createState() =>
      _ComponentsEditorDialogState();
}

class _ComponentsEditorDialogState extends State<_ComponentsEditorDialog> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = <TextEditingController>[
      for (var i = 0; i < widget.labels.length; i++)
        TextEditingController(text: widget.initial[i]),
    ];
    _focusNodes = <FocusNode>[
      for (var i = 0; i < widget.labels.length; i++) FocusNode(),
    ];
    // Select the whole value when a field gains focus, so typing a number
    // replaces the old content without deleting it first.
    for (var i = 0; i < _focusNodes.length; i++) {
      final index = i;
      _focusNodes[index].addListener(() {
        if (!mounted || !_focusNodes[index].hasFocus) {
          return;
        }
        final controller = _controllers[index];
        controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.text.length,
        );
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(
      widget.joinValue(_controllers.map((c) => c.text.trim()).toList()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('分项修改时间'),
      content: SizedBox(
        width: widget.labels.length > 4 ? 420 : 320,
        child: Row(
          children: [
            for (var i = 0; i < widget.labels.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _controllers[i],
                  focusNode: _focusNodes[i],
                  autofocus: i == 0,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: widget.labels[i],
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 10,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(I18n.cancel.tr),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(I18n.confirm.tr),
        ),
      ],
    );
  }
}

class _MiniIconAction extends StatelessWidget {
  const _MiniIconAction({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}

class DateTimePicker extends DateTimePickerBase {
  DateTimePicker({
    super.key,
    required super.value,
    required super.onChange,
    super.hoverStyle,
    super.notHoverStyle,
  });

  @override
  State<StatefulWidget> createState() => DateTimePickerState();
}

class DateTimePickerState extends DateTimePickerBaseState {
  @override
  List<String> get componentLabels => const ['年', '月', '日', '时', '分', '秒'];

  @override
  List<String> parseComponents(String value) {
    final dt = DateTime.tryParse(value.trim().replaceFirst(' ', 'T')) ??
        DateTime.now();
    return [
      dt.year.toString(),
      _pad('${dt.month}'),
      _pad('${dt.day}'),
      _pad('${dt.hour}'),
      _pad('${dt.minute}'),
      _pad('${dt.second}'),
    ];
  }

  @override
  String joinComponents(List<String> parts) {
    return '${parts[0]}-${parts[1]}-${parts[2]} '
        '${parts[3]}:${parts[4]}:${parts[5]}';
  }
}
