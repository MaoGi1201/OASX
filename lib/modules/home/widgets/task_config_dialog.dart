import 'package:flutter/material.dart';
import 'package:oasx/config/app_colors.dart';
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
        backgroundColor: AppColors.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.border),
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
                          color: AppColors.text,
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
                                color: AppColors.teal,
                              ),
                            )
                          : Icon(
                              Icons.refresh_rounded,
                              color: AppColors.text2,
                            ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: AppColors.text2,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.border),
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(color: AppColors.teal),
                      )
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                '加载失败：$_error',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.text2),
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

ThemeData _dialogTheme() {
  final brightness = AppColors.isDark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.teal,
    brightness: brightness,
  ).copyWith(
    primary: AppColors.teal,
    surface: AppColors.panel,
    onSurface: AppColors.text,
    outlineVariant: AppColors.border,
    surfaceContainerHighest: AppColors.card,
    secondaryContainer: AppColors.tealDim,
  );
  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.panel,
    // DropdownButton 的浮层菜单用的是 canvasColor，不设会退回默认浅色。
    canvasColor: AppColors.panel,
    cardColor: AppColors.card,
    dividerColor: AppColors.border,
    iconTheme: IconThemeData(color: AppColors.text2),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.border),
      ),
      textStyle: TextStyle(fontSize: 13, color: AppColors.text),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AppColors.panel),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: AppColors.border),
          ),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.panel,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      hintStyle: TextStyle(color: AppColors.text2, fontSize: 12.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.teal),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.text2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.teal,
        foregroundColor: AppColors.isDark ? const Color(0xFF04140F) : Colors.white,
      ),
    ),
  );
}
