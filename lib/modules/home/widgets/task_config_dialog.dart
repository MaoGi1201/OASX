import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/modules/args/index.dart';
import 'package:oasx/modules/home/controllers/dashboard_controller.dart';

/// Opens a dialog that shows and edits the configuration of [taskName].
///
/// Reuses the shared [Args] form in staging mode so the user can review and
/// change the task's groups/arguments, then save or cancel. The header has a
/// refresh button that reloads the configuration from the backend.
Future<void> showTaskConfigDialog(
  BuildContext context, {
  required HomeDashboardController controller,
  required String scriptName,
  required String taskName,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _TaskConfigDialog(
      controller: controller,
      scriptName: scriptName,
      taskName: taskName,
    ),
  );
}

class _TaskConfigDialog extends StatefulWidget {
  const _TaskConfigDialog({
    required this.controller,
    required this.scriptName,
    required this.taskName,
  });

  final HomeDashboardController controller;
  final String scriptName;
  final String taskName;

  @override
  State<_TaskConfigDialog> createState() => _TaskConfigDialogState();
}

class _TaskConfigDialogState extends State<_TaskConfigDialog> {
  int _reloadSerial = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final argsController = Get.find<ArgsController>();
      final scope = widget.controller.linkedScopeScriptsFor(widget.scriptName);
      await argsController.loadGroups(
        config: widget.scriptName,
        task: widget.taskName,
        stagingMode: true,
        scopeScripts: scope,
        saveArgumentOverride: (config, task, group, argument, type, value) {
          return widget.controller.applyLinkedSetArgument(
            config: config,
            task: task,
            group: group,
            argument: argument,
            type: type,
            value: value,
          );
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _reloadSerial++;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = (size.width - 48).clamp(320.0, 780.0);
    final height = (size.height - 48).clamp(320.0, 640.0);
    return Theme(
      data: _dialogTheme(),
      child: Dialog(
        backgroundColor: _dialogSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: _dialogBorder),
        ),
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: width,
          height: height,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${widget.taskName.tr} · 配置与设置',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _dialogText,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新配置',
                      onPressed: _loading ? null : _load,
                      icon: _loading
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _dialogTeal,
                              ),
                            )
                          : Icon(
                              Icons.refresh_rounded,
                              color: _dialogText2,
                            ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: _dialogText2,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: _dialogBorder),
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(color: _dialogTeal),
                      )
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                '加载失败：$_error',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: _dialogText2),
                              ),
                            ),
                          )
                        : Args(
                            key: ValueKey<String>(
                              'task-config-${widget.scriptName}-'
                              '${widget.taskName}-$_reloadSerial',
                            ),
                            scriptName: widget.scriptName,
                            taskName: widget.taskName,
                            groupDraggable: false,
                            stagingMode: true,
                            onCancel: () async {
                              if (mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog palette: mirrors the dashboard's light/dark colors and teal accent.
// ---------------------------------------------------------------------------
bool get _dialogDark => Get.isDarkMode;
Color get _dialogSurface =>
    _dialogDark ? const Color(0xFF12151A) : Colors.white;
Color get _dialogCard =>
    _dialogDark ? const Color(0xFF1A1F26) : const Color(0xFFF7F8FA);
Color get _dialogBorder =>
    _dialogDark ? const Color(0xFF232932) : const Color(0xFFE1E5EB);
Color get _dialogText =>
    _dialogDark ? const Color(0xFFE8EAED) : const Color(0xFF1B1F24);
Color get _dialogText2 =>
    _dialogDark ? const Color(0xFF9AA3AF) : const Color(0xFF5A6472);
Color get _dialogTeal =>
    _dialogDark ? const Color(0xFF2FD6A5) : const Color(0xFF0E9E7A);
Color get _dialogTealDim =>
    _dialogDark ? const Color(0xFF123B34) : const Color(0xFFDFF5EE);

ThemeData _dialogTheme() {
  final brightness = _dialogDark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: _dialogTeal,
    brightness: brightness,
  ).copyWith(
    primary: _dialogTeal,
    surface: _dialogSurface,
    onSurface: _dialogText,
    outlineVariant: _dialogBorder,
    surfaceContainerHighest: _dialogCard,
    secondaryContainer: _dialogTealDim,
  );
  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: _dialogSurface,
    cardColor: _dialogCard,
    dividerColor: _dialogBorder,
    iconTheme: IconThemeData(color: _dialogText2),
    dialogTheme: DialogThemeData(
      backgroundColor: _dialogSurface,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _dialogCard,
      hintStyle: TextStyle(color: _dialogText2, fontSize: 12.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _dialogBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _dialogBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _dialogTeal),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: _dialogText2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _dialogTeal,
        foregroundColor: _dialogDark ? const Color(0xFF04140F) : Colors.white,
      ),
    ),
  );
}
