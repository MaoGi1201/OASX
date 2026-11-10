import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:oasx/config/app_colors.dart';

/// 全应用统一下拉的视觉参数。
///
/// 之所以不用 Material 自带的 `PopupMenuItem`：它每行 48px 高、左右 16px 内边距，
/// 选中项还会被 `_PopupMenu` 刷成一条通栏矩形（`Theme.highlightColor` 的
/// `ColoredBox`），在面板里看起来就是一块「长方框」，和这里 26~34px、圆角 7~10 的
/// chip / 任务行完全不是一套语言。
const double _kMenuRadius = 10.0;
const double _kItemRadius = 7.0;
const double _kItemHeight = 30.0;
const double _kItemGap = 1.0;

/// 菜单面板内边距，必须与 `theme.dart` 里的 `popupMenuTheme.menuPadding` 一致：
/// 那层 padding 是 `showMenu` 内部给 `SingleChildScrollView` 加的，改不到这里。
const double kAppMenuInset = 6.0;

/// 下拉菜单最多一次显示多少行，超出后滚动。
const int kAppMenuMaxVisibleItems = 8;

/// 菜单与锚点之间的垂直间隙，避免菜单顶边贴着按钮底边。
const double _kAnchorGap = 2.0;

/// 菜单面板的最小宽度（图标按钮的菜单靠这个值撑开）。
const double _kMenuMinWidth = 120.0;

/// 菜单相对锚点的水平对齐方式。
enum AppMenuAnchor {
  /// Material 默认规则：锚点离窗口哪侧更近，菜单就从哪侧展开。
  auto,

  /// 菜单左缘对齐锚点左缘、向右展开。适合左栏里靠右的 chip
  /// （右边没空间，但左边有别的控件，不能让菜单盖住）。
  start,

  /// 菜单右缘对齐锚点右缘、向左展开。适合卡片/工具栏右端的图标按钮：
  /// 菜单落在内容区内部，不会伸到旁边那一栏去。
  end,
}

/// 下拉菜单的一项。
@immutable
class AppMenuOption<T> {
  /// Creates a menu option.
  const AppMenuOption({
    required this.value,
    required this.label,
    this.icon,
    this.color,
  });

  /// Value returned by [showAppMenu] when this option is picked.
  final T value;

  /// Text shown on the row.
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// Optional text/icon color, e.g. red for destructive actions.
  final Color? color;
}

/// 弹出统一样式的下拉菜单，锚定在 [context] 对应的组件下方。
///
/// 返回用户选中的值；点空白处或按 Esc 关闭时返回 null。
Future<T?> showAppMenu<T>(
  BuildContext context, {
  required List<AppMenuOption<T>> options,
  T? selected,
  AppMenuAnchor anchor = AppMenuAnchor.auto,
  int maxVisibleItems = kAppMenuMaxVisibleItems,
  bool matchAnchorWidth = false,
}) async {
  if (options.isEmpty) {
    return null;
  }
  final anchorBox = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (anchorBox == null || overlay == null || !anchorBox.hasSize) {
    return null;
  }
  final anchorRect = Rect.fromPoints(
    anchorBox.localToGlobal(Offset.zero, ancestor: overlay),
    anchorBox.localToGlobal(
      anchorBox.size.bottomRight(Offset.zero),
      ancestor: overlay,
    ),
  );
  final overlaySize = overlay.size;
  final left = anchorRect.left;
  final right = overlaySize.width - anchorRect.right;
  // 垂直方向钉在锚点下方：showMenu 默认把菜单顶边对齐锚点顶边，
  // 对 32px 的图标按钮来说等于把按钮整个盖住，看起来像「菜单浮在按钮上」。
  final top = anchorRect.bottom + _kAnchorGap;
  final bottom = math.max(0.0, overlaySize.height - top);

  var position = RelativeRect.fromLTRB(left, top, right, bottom);
  switch (anchor) {
    case AppMenuAnchor.auto:
      break;
    case AppMenuAnchor.start:
      // 左右边距相等时 `popup_menu.dart` 走「沿阅读方向展开」分支，
      // 即左缘对齐锚点左缘向右长；右边界不够时它会自己平移回来。
      position = RelativeRect.fromLTRB(left, top, left, bottom);
    case AppMenuAnchor.end:
      // 该分支只在 `position.left > position.right` 时右缘对齐；
      // 锚点在窗口左半边时把 left 顶到 right 右侧 1px 来强制走这一支，
      // 展开宽度仍然由 right 决定，所以菜单右缘正好压在锚点右缘。
      if (left <= right) {
        position = RelativeRect.fromLTRB(right + 1, top, right, bottom);
      }
  }

  return showMenu<T>(
    context: context,
    position: position,
    // 不传 initialValue：一旦传了，_PopupMenu 会给选中项包一层通栏
    // `ColoredBox(highlightColor)`，选中样式改由 _AppMenuRow 自己画。
    color: AppColors.panel,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_kMenuRadius),
      side: BorderSide(color: AppColors.border),
    ),
    constraints: BoxConstraints(
      // 输入框式的下拉（enum、模板）让菜单和锚点同宽，看起来才像同一个 select；
      // 图标按钮的菜单维持 120 的最小宽度。
      minWidth: matchAnchorWidth
          ? math.max(anchorRect.width, _kMenuMinWidth)
          : _kMenuMinWidth,
      maxHeight:
          maxVisibleItems * (_kItemHeight + _kItemGap) + kAppMenuInset * 2,
    ),
    items: [
      for (final option in options)
        _AppMenuItem<T>(option: option, selected: option.value == selected),
    ],
  );
}

class _AppMenuItem<T> extends PopupMenuEntry<T> {
  const _AppMenuItem({required this.option, required this.selected});

  final AppMenuOption<T> option;
  final bool selected;

  @override
  double get height => _kItemHeight + _kItemGap;

  @override
  bool represents(T? value) => value == option.value;

  @override
  State<_AppMenuItem<T>> createState() => _AppMenuItemState<T>();
}

class _AppMenuItemState<T> extends State<_AppMenuItem<T>> {
  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    final selected = widget.selected;
    final foreground =
        option.color ?? (selected ? AppColors.teal : AppColors.text);
    return Padding(
      padding: const EdgeInsets.only(bottom: _kItemGap),
      child: Material(
        color: selected ? AppColors.tealDim : Colors.transparent,
        borderRadius: BorderRadius.circular(_kItemRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.pop<T>(context, option.value),
          hoverColor: AppColors.surface2,
          splashColor: AppColors.teal.withValues(alpha: 0.10),
          child: SizedBox(
            height: _kItemHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  if (option.icon != null) ...[
                    Icon(option.icon, size: 14, color: foreground),
                    const SizedBox(width: 7),
                  ],
                  Expanded(
                    child: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: foreground,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.check_rounded, size: 14, color: AppColors.teal),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
