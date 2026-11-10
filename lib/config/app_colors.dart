import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Single source of truth for OASX colours.
///
/// The dashboard, the dialogs and the global [ThemeData] all read from here so
/// the whole app switches between day and night with one palette.
///
/// `xxxFor(brightness)` variants exist because [ThemeData] is built for an
/// explicit brightness, while widgets use the context-free getters.
///
/// Dark mode is deliberately *not* an inversion of light mode: the surfaces sit
/// on a dark grey instead of pure black and the text stops short of white,
/// which keeps the body contrast near 10.7:1. Pure black plus near-white text
/// makes glyph edges glow (halation) and is the main source of eye strain during
/// long sessions; mainstream editors settle in the 7-11:1 range for the same
/// reason.
///
/// Surface elevation runs light-wards: `bg` < `panel` < `surface3` < `card` <
/// `surface2`. `surface3` is the recessed tone used for inputs and grooves.
class AppColors {
  const AppColors._();

  static Brightness get _brightness =>
      Get.isDarkMode ? Brightness.dark : Brightness.light;

  static Color _pick(Brightness b, Color light, Color dark) =>
      b == Brightness.dark ? dark : light;

  // Surfaces
  static Color bgFor(Brightness b) =>
      _pick(b, const Color(0xFFF3F4F7), const Color(0xFF191C21));
  static Color panelFor(Brightness b) =>
      _pick(b, const Color(0xFFFFFFFF), const Color(0xFF20242A));
  static Color cardFor(Brightness b) =>
      _pick(b, const Color(0xFFF7F8FA), const Color(0xFF282D35));
  static Color surface2For(Brightness b) =>
      _pick(b, const Color(0xFFEDEFF3), const Color(0xFF2F353E));
  static Color surface3For(Brightness b) =>
      _pick(b, const Color(0xFFF0F2F5), const Color(0xFF232830));
  static Color selectedBgFor(Brightness b) =>
      _pick(b, const Color(0xFFEAF6F2), const Color(0xFF1F2E2A));
  static Color selectedBorderFor(Brightness b) =>
      _pick(b, const Color(0xFFBEE8DC), const Color(0xFF2C4A42));
  static Color borderFor(Brightness b) =>
      _pick(b, const Color(0xFFE1E5EB), const Color(0xFF343B45));

  // Text
  static Color textFor(Brightness b) =>
      _pick(b, const Color(0xFF1B1F24), const Color(0xFFC6CED9));
  static Color text2For(Brightness b) =>
      _pick(b, const Color(0xFF5A6472), const Color(0xFF9BA5B2));
  static Color text3For(Brightness b) =>
      _pick(b, const Color(0xFF8B94A3), const Color(0xFF848D9A));

  // Accents
  static Color tealFor(Brightness b) =>
      _pick(b, const Color(0xFF0E9E7A), const Color(0xFF3CBFA0));
  static Color tealDimFor(Brightness b) =>
      _pick(b, const Color(0xFFDFF5EE), const Color(0xFF16332C));
  static Color greenFor(Brightness b) =>
      _pick(b, const Color(0xFF16A34A), const Color(0xFF52B788));
  static Color yellowFor(Brightness b) =>
      _pick(b, const Color(0xFFD97706), const Color(0xFFD9A441));
  static Color redFor(Brightness b) =>
      _pick(b, const Color(0xFFDC2626), const Color(0xFFDB5A5E));
  static Color blueFor(Brightness b) =>
      _pick(b, const Color(0xFF2563EB), const Color(0xFF5C8BD9));

  /// Filled "danger" button: 停止配置 and the delete confirmation.
  ///
  /// Dark mode uses a **deeper** red than [redFor] rather than the bright
  /// `#DB5A5E` + near-black text it used to. Black text on a light salmon fill
  /// reads like an alarm sticker dropped onto a near-black surface — the two
  /// ends of the luminance range sit side by side and the button screams.
  /// `#B24A4E` with warm white text keeps 5.2:1 for the label while the fill
  /// itself stops glowing (2.96:1 against the panel, same order as the teal
  /// start button, so both states still weigh the same).
  static Color dangerFillFor(Brightness b) =>
      _pick(b, const Color(0xFFDC2626), const Color(0xFFB24A4E));

  /// Text colour on top of [dangerFillFor].
  static Color onDangerFillFor(Brightness b) =>
      _pick(b, Colors.white, const Color(0xFFFDF2F2));

  /// Text colour on top of a filled accent button.
  static Color onAccentFor(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF0B1F19) : Colors.white;

  /// Text colour on top of the warning (yellow) fill.
  ///
  /// Near-black in both themes: white on `#D9A441` sits near 3:1, while this
  /// combination is above 9:1.
  static Color onWarningFor(Brightness b) => const Color(0xFF1F1A00);

  /// Fixed palette for the per-task bars in the statistics chart.
  ///
  /// The colour of a task is derived from its name hash, so it has to stay
  /// stable across restarts; six hues that remain distinguishable on both the
  /// light and the dark card surface.
  static const List<Color> chartPalette = <Color>[
    Color(0xFF2563EB),
    Color(0xFFDC2626),
    Color(0xFF16A34A),
    Color(0xFFD97706),
    Color(0xFF7C3AED),
    Color(0xFF0891B2),
  ];

  // Log levels. These used to be raw `Colors.yellow / lightGreen / red`, which
  // on the *light* log background sat at 1.2–1.9:1 — effectively unreadable.
  // Same hue family, tuned per brightness.
  static Color logInfoFor(Brightness b) =>
      _pick(b, const Color(0xFF0E7490), const Color(0xFF5FD3E8));
  static Color logWarnFor(Brightness b) =>
      _pick(b, const Color(0xFF92600A), const Color(0xFFE8C05C));
  static Color logErrorFor(Brightness b) => redFor(b);
  static Color logSuccessFor(Brightness b) =>
      _pick(b, const Color(0xFF15803D), const Color(0xFF7BD88F));
  static Color logDebugFor(Brightness b) =>
      _pick(b, const Color(0xFF6D28D9), const Color(0xFFB79CFF));

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
  static Color get onWarning => onWarningFor(_brightness);
  static Color get dangerFill => dangerFillFor(_brightness);
  static Color get onDangerFill => onDangerFillFor(_brightness);
  static Color get logInfo => logInfoFor(_brightness);
  static Color get logWarn => logWarnFor(_brightness);
  static Color get logError => logErrorFor(_brightness);
  static Color get logSuccess => logSuccessFor(_brightness);
  static Color get logDebug => logDebugFor(_brightness);

  /// Seed used to derive Material component colours.
  static const Color seed = Color(0xFF0E9E7A);
}
