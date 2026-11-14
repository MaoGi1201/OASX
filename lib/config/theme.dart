import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:chinese_font_library/chinese_font_library.dart';
import 'package:oasx/config/app_colors.dart';
import 'package:oasx/config/app_metrics.dart';
import 'package:oasx/modules/common/widgets/app_popup_menu.dart';

/// 全局界面字体族。
///
/// `LatoLato` 在 `pubspec.yaml` 里注册，实际文件是 `assets/Lato-Regular.ttf`。
/// Lato 只有拉丁与数字字形，汉字由 `useSystemChineseFont()` 交给系统字体
/// （Windows → Microsoft YaHei）。
const String kAppFontFamily = 'LatoLato';

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

/// Every explicit `TextStyle` in the theme must carry the family itself.
///
/// `dialogTheme.titleTextStyle`, `inputDecorationTheme.hintStyle`,
/// `popupMenuTheme.textStyle` … all **replace** the text theme instead of
/// merging into it, so a style that omits `fontFamily` silently falls back to
/// the platform default and that one string ends up in a different typeface
/// than everything around it.
TextStyle _style({
  required double fontSize,
  double? height,
  FontWeight? fontWeight,
  Color? color,
}) {
  return TextStyle(
    fontFamily: kAppFontFamily,
    fontFamilyFallback: SystemChineseFont.fontFamilyFallback,
    fontSize: fontSize,
    height: height,
    fontWeight: fontWeight,
    color: color,
  );
}

/// Builds the app theme from [AppColors] so every Material component
/// (dialogs, cards, inputs, menus, tooltips) shares one look.
ThemeData _buildTheme(Brightness brightness) {
  final teal = AppColors.tealFor(brightness);
  final text = AppColors.textFor(brightness);
  final text2 = AppColors.text2For(brightness);
  final border = AppColors.borderFor(brightness);
  final surface2 = AppColors.surface2For(brightness);
  final radius = BorderRadius.circular(AppRadius.input);

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
    // 兜底：任何绕过 textTheme 取默认样式的组件（Typography 派生样式）也用同一族。
    fontFamily: kAppFontFamily,
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
        borderRadius: BorderRadius.circular(AppRadius.dialog),
        side: BorderSide(color: border),
      ),
      titleTextStyle: _style(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: text,
      ),
      contentTextStyle: _style(fontSize: 13, color: text2),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
    ),
    cardTheme: CardThemeData(
      color: AppColors.cardFor(brightness),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: surface2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: _style(fontSize: 13, color: AppColors.text3For(brightness)),
      labelStyle: _style(fontSize: 13, color: text2),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
        textStyle: _style(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        foregroundColor: text2,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
        textStyle: _style(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: teal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
        textStyle: _style(fontSize: 13, fontWeight: FontWeight.w500),
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
        borderRadius: BorderRadius.circular(AppRadius.menu),
        side: BorderSide(color: border),
      ),
      // 与 app_popup_menu.dart 的 kAppMenuInset 对应：让菜单行像卡片里的圆角条目，
      // 而不是贴着面板边缘的通栏矩形。
      menuPadding: const EdgeInsets.all(kAppMenuInset),
      textStyle: _style(fontSize: 13, color: text),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: surface2,
        borderRadius: BorderRadius.circular(AppRadius.tooltip),
        border: Border.all(color: border),
      ),
      textStyle: _style(fontSize: 12, color: text),
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surface3For(brightness),
      contentTextStyle: _style(fontSize: 13, color: text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.menu)),
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
  // 六档字号：16 / 15 / 13 / 12 / 11 / 10。
  //
  // 这里以前是九个空 `TextStyle()`：没有 fontSize 也没有 color，于是凡是没
  // 显式写样式的地方都会落到 Flutter 默认的 14px，各组件只能自己发明字号
  // （全仓一度出现 15 种取值，同屏相邻文字就差半级）。现在先把基线定下来，
  // 显式 fontSize 再逐步往这几档上收。
  final text = AppColors.textFor(brightness);
  final text2 = AppColors.text2For(brightness);
  final text3 = AppColors.text3For(brightness);
  final baseTheme = TextTheme(
    // 16 —— 对话框 / 页面主标题
    titleLarge: _style(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: text,
    ),
    // 15 —— 区块标题
    titleMedium: _style(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: text,
    ),
    // 13 —— 卡片标题 / 强调
    titleSmall: _style(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: text,
    ),
    // 13 —— 正文
    bodyLarge: _style(fontSize: 13, color: text),
    bodyMedium: _style(fontSize: 13, color: text),
    // 12 —— 次要说明
    bodySmall: _style(fontSize: 12, color: text2),
    // 13 —— 按钮文字
    labelLarge: _style(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: text,
    ),
    // 11 —— 小标签
    labelMedium: _style(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: text2,
    ),
    // 10 —— 角标 / 极次要
    labelSmall: _style(fontSize: 10, color: text3),
  );
  final withFamily = baseTheme.apply(fontFamily: kAppFontFamily);
  return kIsWeb
      ? _applyFontFallback(withFamily, _webChineseFontFallback)
      : withFamily.useSystemChineseFont(brightness);
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
