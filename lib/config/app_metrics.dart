/// Shared size tokens.
///
/// Before this file existed the app had 12 different corner radii, 13 control
/// heights and 10 different icon/label gaps, because every widget picked its own
/// number. This is the single place those numbers live now; anything that is
/// neither a semantic size (dialog, card, input) nor a spacing step should not
/// invent a new value.
///
/// Radius is deliberately *not* one number for everything: a dialog reads better
/// slightly rounder than a card sitting inside it, and a pill stays a pill.
/// What we removed is the accidental drift — 14 vs 12 cards, 7 vs 8 on the same
/// widget, 9 vs 8 buttons.
library;

/// Corner radii, grouped by the kind of surface they belong to.
abstract final class AppRadius {
  /// Modal dialogs and the deployment shell.
  static const double dialog = 14;

  /// Cards, panels and any box that sits inside a panel.
  static const double card = 12;

  /// Text fields and other filled inputs.
  static const double input = 10;

  /// Buttons, list rows, small square icon buttons.
  static const double button = 8;

  /// Floating surfaces: popup menus and snackbars.
  static const double menu = 10;

  /// Tooltips and other tiny overlays.
  static const double tooltip = 6;

  /// Pills and chips; use with [BorderRadius.circular] or `StadiumBorder`.
  static const double pill = 999;
}

/// Control heights.
abstract final class AppSize {
  /// Square icon-only button (refresh, power, theme, connector…).
  static const double iconButton = 28;

  /// Chip / tag height.
  static const double chip = 26;

  /// Compact segmented tab.
  static const double tab = 28;

  /// Standard row in a task list.
  static const double row = 44;

  /// Text field height.
  static const double field = 34;

  /// Top bar.
  static const double header = 46;
}

/// Spacing steps. Everything is a multiple of 2 so the grid stays even.
abstract final class AppGap {
  /// 4 — icon to text inside a tight row.
  static const double xs = 4;

  /// 6 — between two labels.
  static const double s = 6;

  /// 8 — default gap between controls.
  static const double m = 8;

  /// 12 — between sections.
  static const double l = 12;

  /// 16 — between panels.
  static const double xl = 16;
}
