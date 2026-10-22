import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Compact floating toast pinned to the bottom of the window.
///
/// The default `Get.snackbar` renders a full-width bar at the top of the
/// screen, which covers the dashboard header (config tabs, status chip) and
/// makes the UI look broken. Every user-facing notification should go through
/// this helper instead so it stays small and never blocks the header.
void showToast(
  String title,
  String message, {
  Duration? duration,
  Widget? icon,
  Color? backgroundColor,
  Color? colorText,
  SnackPosition position = SnackPosition.BOTTOM,
  bool showProgressIndicator = false,
}) {
  final isDark = Get.isDarkMode;
  final bg = backgroundColor ??
      (isDark ? const Color(0xF21F2933) : const Color(0xF22B3440));
  final fg = colorText ?? Colors.white;
  Get.snackbar(
    title,
    message,
    snackPosition: position,
    snackStyle: SnackStyle.FLOATING,
    maxWidth: 380,
    margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16, top: 16),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    borderRadius: 10,
    backgroundColor: bg,
    colorText: fg,
    icon: icon,
    shouldIconPulse: false,
    isDismissible: true,
    dismissDirection: DismissDirection.horizontal,
    duration: duration ?? const Duration(seconds: 2),
    animationDuration: const Duration(milliseconds: 180),
    forwardAnimationCurve: Curves.easeOutCubic,
    reverseAnimationCurve: Curves.easeInCubic,
    showProgressIndicator: showProgressIndicator,
    titleText: Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: fg,
      ),
    ),
    messageText: Text(
      message,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12.5, color: fg.withValues(alpha: 0.88)),
    ),
  );
}
