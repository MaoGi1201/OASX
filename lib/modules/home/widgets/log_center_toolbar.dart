part of 'log_center_panel.dart';

/// Header controls for the log center.
class LogCenterToolbar extends StatelessWidget {
  /// Creates toolbar controls.
  const LogCenterToolbar({
    super.key,
    required this.controller,
    required this.onToggleLineWrap,
  });

  /// Log browser controller.
  final ScriptLogBrowserController controller;

  /// Toggles wrapping with panel-level scroll handling.
  final VoidCallback onToggleLineWrap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _leadingControls(context)),
        const SizedBox(width: 8),
        _trailingControls(),
      ],
    );
  }

  /// Builds the info/error tab switch on the left.
  Widget _leadingControls(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [_tabSwitch()],
    );
  }

  /// Builds action buttons aligned to the right.
  Widget _trailingControls() {
    return Obx(() {
      if (!_shouldShowLogActions()) {
        return const SizedBox.shrink();
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_shouldShowWrapAction()) _wrapButton(),
          if (controller.activeTab.value == ScriptLogBrowserTab.info)
            _autoScrollButton(),
          _copyButton(),
          _clearButton(),
        ],
      );
    });
  }

  /// Returns whether the current view owns log text actions.
  bool _shouldShowLogActions() {
    if (controller.activeTab.value == ScriptLogBrowserTab.info) {
      return true;
    }
    return controller.errorDetailVisible.value;
  }

  /// Returns whether wrapping can affect the current log text.
  bool _shouldShowWrapAction() {
    if (controller.activeTab.value == ScriptLogBrowserTab.info) {
      return true;
    }
    return controller.errorDetailVisible.value;
  }

  /// Builds the info/error tab selector.
  Widget _tabSwitch() {
    return Obx(() {
      final active = controller.activeTab.value;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LogTabChip(
            label: I18n.homeLogInfoTab.tr,
            selected: active == ScriptLogBrowserTab.info,
            onTap: () => controller.selectTab(ScriptLogBrowserTab.info),
          ),
          const SizedBox(width: 8),
          _LogTabChip(
            label: I18n.homeLogErrorTab.tr,
            selected: active == ScriptLogBrowserTab.error,
            onTap: () => controller.selectTab(ScriptLogBrowserTab.error),
          ),
        ],
      );
    });
  }

  Widget _autoScrollButton() {
    final enabled = controller.autoScroll.value;
    return _LogIconButton(
      tooltip: I18n.homeLogAutoScroll.tr,
      onTap: controller.toggleAutoScroll,
      icon: enabled ? Icons.flash_on_rounded : Icons.flash_off_rounded,
      color: enabled ? _logTeal : _logText2,
    );
  }

  /// Builds the long-line wrapping action.
  Widget _wrapButton() {
    final enabled = controller.wrapLines.value;
    return _LogIconButton(
      tooltip: I18n.homeLogWrapLines.tr,
      onTap: onToggleLineWrap,
      icon: enabled ? Icons.wrap_text : Icons.short_text,
    );
  }

  /// Builds the copy action.
  Widget _copyButton() {
    return _LogIconButton(
      tooltip: I18n.copy.tr,
      onTap: _copyCurrent,
      icon: Icons.content_copy_rounded,
    );
  }

  /// Builds the clear action.
  Widget _clearButton() {
    return _LogIconButton(
      tooltip: I18n.clearLog.tr,
      onTap: controller.clearCurrentView,
      icon: Icons.delete_outline_rounded,
    );
  }

  void _copyCurrent() {
    controller.copyCurrentView();
  }
}

/// Dark pill tab used by the log toolbar (matches the task toolbar chips).
class _LogTabChip extends StatelessWidget {
  const _LogTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _logTealDim : _logSurface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? _logTeal.withValues(alpha: 0.45) : _logBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? _logTeal : _logText2,
          ),
        ),
      ),
    );
  }
}

/// Compact 28x28 icon button matching the dashboard controls.
class _LogIconButton extends StatelessWidget {
  const _LogIconButton({
    required this.tooltip,
    required this.onTap,
    required this.icon,
    this.color,
  });

  final String tooltip;
  final VoidCallback? onTap;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.only(left: 6),
          decoration: BoxDecoration(
            color: _logSurface2,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: _logBorder),
          ),
          child: Icon(icon, size: 15, color: color ?? _logText2),
        ),
      ),
    );
  }
}
