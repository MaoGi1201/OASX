import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Single source of truth for OASX colours.
///
/// The dashboard, the dialogs and the global [ThemeData] all read from here so
/// the whole app switches between day and night with one palette.
///
/// `xxxFor(brightness)` variants exist because [ThemeData] is built for an
/// explicit brightness, while widgets use the context-free getters.
class AppColors {
  const AppColors._();

  static Brightness get _brightness =>
      Get.isDarkMode ? Brightness.dark : Brightness.light;

  static Color _pick(Brightness b, Color light, Color dark) =>
      b == Brightness.dark ? dark : light;

  // Surfaces
  static Color bgFor(Brightness b) =>
      _pick(b, const Color(0xFFF3F4F7), const Color(0xFF0A0C0F));
  static Color panelFor(Brightness b) =>
      _pick(b, const Color(0xFFFFFFFF), const Color(0xFF12151A));
  static Color cardFor(Brightness b) =>
      _pick(b, const Color(0xFFF7F8FA), const Color(0xFF1A1F26));
  static Color surface2For(Brightness b) =>
      _pick(b, const Color(0xFFEDEFF3), const Color(0xFF1B2129));
  static Color surface3For(Brightness b) =>
      _pick(b, const Color(0xFFF0F2F5), const Color(0xFF141820));
  static Color selectedBgFor(Brightness b) =>
      _pick(b, const Color(0xFFEAF6F2), const Color(0xFF1C232C));
  static Color selectedBorderFor(Brightness b) =>
      _pick(b, const Color(0xFFBEE8DC), const Color(0xFF2B3540));
  static Color borderFor(Brightness b) =>
      _pick(b, const Color(0xFFE1E5EB), const Color(0xFF232932));

  // Text
  static Color textFor(Brightness b) =>
      _pick(b, const Color(0xFF1B1F24), const Color(0xFFE8EAED));
  static Color text2For(Brightness b) =>
      _pick(b, const Color(0xFF5A6472), const Color(0xFF9AA3AF));
  static Color text3For(Brightness b) =>
      _pick(b, const Color(0xFF8B94A3), const Color(0xFF6B7280));

  // Accents
  static Color tealFor(Brightness b) =>
      _pick(b, const Color(0xFF0E9E7A), const Color(0xFF2FD6A5));
  static Color tealDimFor(Brightness b) =>
      _pick(b, const Color(0xFFDFF5EE), const Color(0xFF123B34));
  static Color greenFor(Brightness b) =>
      _pick(b, const Color(0xFF16A34A), const Color(0xFF4ADE80));
  static Color yellowFor(Brightness b) =>
      _pick(b, const Color(0xFFD97706), const Color(0xFFF0B429));
  static Color redFor(Brightness b) =>
      _pick(b, const Color(0xFFDC2626), const Color(0xFFE5484D));
  static Color blueFor(Brightness b) =>
      _pick(b, const Color(0xFF2563EB), const Color(0xFF5B8DEF));

  /// Text colour on top of a filled accent button.
  static Color onAccentFor(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF04140F) : Colors.white;

  static bool get isDark => Get.isDarkMode;

  static Color get bg => bgFor(_brightness);
  static Color get panel => panelFor(_brightness);
  static Color get card => cardFor(_brightness);
  static Color get surface2 => surface2For(_brightness);
  static Color get surface3 => surface3For(_brightness);
  static Color get selectedBg => selectedBgFor(_brightness);
  static Color get selectedBorder => selectedBorderFor(_brightness);
  static Color get border => borderFor(_brightness);

  static Color get text => textFor(_brightness);
  static Color get text2 => text2For(_brightness);
  static Color get text3 => text3For(_brightness);

  static Color get teal => tealFor(_brightness);
  static Color get tealDim => tealDimFor(_brightness);
  static Color get green => greenFor(_brightness);
  static Color get yellow => yellowFor(_brightness);
  static Color get red => redFor(_brightness);
  static Color get blue => blueFor(_brightness);
  static Color get onAccent => onAccentFor(_brightness);

  /// Seed used to derive Material component colours.
  static const Color seed = Color(0xFF0E9E7A);
}
