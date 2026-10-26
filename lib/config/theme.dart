import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:chinese_font_library/chinese_font_library.dart';
import 'package:oasx/config/app_colors.dart';

const List<String> _webChineseFontFallback = <String>[
  'PingFang SC',
  'Hiragino Sans GB',
  'Microsoft YaHei',
  'Noto Sans SC',
  'Noto Sans CJK SC',
  'Source Han Sans SC',
  'WenQuanYi Micro Hei',
  'sans-serif',
];

/// 用枚举太麻烦了
enum ColorSeed {
  baseColor('M3 Baseline', Color(0xff6750a4)),
  indigo('Indigo', Colors.indigo),
  blue('Blue', Colors.blue),
  teal('Teal', Colors.teal),
  green('Green', Colors.green),
  yellow('Yellow', Colors.yellow),
  orange('Orange', Colors.orange),
  deepOrange('Deep Orange', Colors.deepOrange),
  pink('Pink', Colors.pink);

  const ColorSeed(this.label, this.color);
  final String label;
  final Color color;
}

const Map<String, Color> colorSeedMap = {
  'M3 Baseline': Color(0xff6750a4),
  'Indigo': Colors.indigo,
  'Blue': Colors.blue,
  'Teal': Colors.teal,
  'Green': Colors.green,
  'Yellow': Colors.yellow,
  'Orange': Colors.orange,
  'Deep Orange': Colors.deepOrange,
  'Pink': Colors.pink
};

ThemeData lightTheme = _buildTheme(Brightness.light);
ThemeData darkTheme = _buildTheme(Brightness.dark);

/// Builds the app theme from [AppColors] so every Material component
/// (dialogs, cards, inputs, menus, tooltips) shares one look.
ThemeData _buildTheme(Brightness brightness) {
  final teal = AppColors.tealFor(brightness);
  final text = AppColors.textFor(brightness);
  final text2 = AppColors.text2For(brightness);
  final border = AppColors.borderFor(brightness);
  final surface2 = AppColors.surface2For(brightness);
  final radius = BorderRadius.circular(10);

  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.seed,
    brightness: brightness,
  ).copyWith(
    primary: teal,
    onPrimary: AppColors.onAccentFor(brightness),
    surface: AppColors.panelFor(brightness),
    onSurface: text,
    onSurfaceVariant: text2,
    outline: border,
    outlineVariant: border,
    error: AppColors.redFor(brightness),
    surfaceContainerHighest: surface2,
    surfaceContainerHigh: AppColors.surface3For(brightness),
    surfaceContainer: surface2,
    surfaceContainerLow: AppColors.panelFor(brightness),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: _buildTextTheme(brightness),
    scaffoldBackgroundColor: AppColors.bgFor(brightness),
    canvasColor: AppColors.panelFor(brightness),
    cardColor: AppColors.cardFor(brightness),
    dividerColor: border,
    shadowColor: Colors.transparent,
    splashFactory: InkSparkle.splashFactory,
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: AppColors.bgFor(brightness),
      indicatorColor: AppColors.tealDimFor(brightness),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.panelFor(brightness),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: border),
      ),
      titleTextStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: text,
      ),
      contentTextStyle: TextStyle(fontSize: 13, color: text2),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
    ),
    cardTheme: CardThemeData(
      color: AppColors.cardFor(brightness),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: surface2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: TextStyle(fontSize: 13, color: AppColors.text3For(brightness)),
      labelStyle: TextStyle(fontSize: 13, color: text2),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: teal, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        foregroundColor: text2,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: teal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(text2),
        iconSize: const WidgetStatePropertyAll(18),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.panelFor(brightness),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: border),
      ),
      textStyle: TextStyle(fontSize: 13, color: text),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: surface2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      textStyle: TextStyle(fontSize: 12, color: text),
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surface3For(brightness),
      contentTextStyle: TextStyle(fontSize: 13, color: text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: teal),
    // Material 3 默认用 colorScheme.primary/onPrimary 组合，深色下拇指会接近黑色，
    // 在青色轨道上几乎看不见；这里显式指定白色拇指 + 青色轨道。
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : AppColors.text3For(brightness),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? teal : surface2,
      ),
      trackOutlineColor: WidgetStatePropertyAll(border),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.tealDimFor(brightness)
              : surface2,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? teal : text2,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: border)),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: border, width: 1.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? teal : null,
      ),
    ),
    listTileTheme: ListTileThemeData(iconColor: text2, textColor: text),
    tabBarTheme: TabBarThemeData(
      labelColor: teal,
      unselectedLabelColor: text2,
      indicatorColor: teal,
      dividerColor: border,
    ),
  );
}

TextTheme _buildTextTheme(Brightness brightness) {
  const baseTheme = TextTheme(
    bodyLarge: TextStyle(),
    bodyMedium: TextStyle(),
    bodySmall: TextStyle(),
    labelLarge: TextStyle(),
    labelMedium: TextStyle(),
    labelSmall: TextStyle(),
    titleLarge: TextStyle(),
    titleMedium: TextStyle(),
    titleSmall: TextStyle(),
  );
  if (kIsWeb) {
    return _applyFontFallback(baseTheme, _webChineseFontFallback);
  }
  return baseTheme.apply(fontFamily: 'LatoLato').useSystemChineseFont(
        brightness,
      );
}

TextTheme _applyFontFallback(TextTheme textTheme, List<String> fallback) {
  return textTheme.copyWith(
    bodyLarge: _applyTextStyleFallback(textTheme.bodyLarge, fallback),
    bodyMedium: _applyTextStyleFallback(textTheme.bodyMedium, fallback),
    bodySmall: _applyTextStyleFallback(textTheme.bodySmall, fallback),
    labelLarge: _applyTextStyleFallback(textTheme.labelLarge, fallback),
    labelMedium: _applyTextStyleFallback(textTheme.labelMedium, fallback),
    labelSmall: _applyTextStyleFallback(textTheme.labelSmall, fallback),
    titleLarge: _applyTextStyleFallback(textTheme.titleLarge, fallback),
    titleMedium: _applyTextStyleFallback(textTheme.titleMedium, fallback),
    titleSmall: _applyTextStyleFallback(textTheme.titleSmall, fallback),
  );
}

TextStyle? _applyTextStyleFallback(TextStyle? style, List<String> fallback) {
  return style?.copyWith(fontFamilyFallback: fallback);
}
