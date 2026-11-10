import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/config/theme.dart';
import 'package:oasx/modules/common/widgets/app_popup_menu.dart';

Widget _host({required void Function(BuildContext context) onOpen}) {
  return MaterialApp(
    theme: lightTheme,
    home: Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => onOpen(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('menu draws compact rows and returns the picked value', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      _host(
        onOpen: (context) async {
          picked = await showAppMenu<String>(
            context,
            options: const [
              AppMenuOption(value: 'a', label: 'Alpha'),
              AppMenuOption(value: 'b', label: 'Beta'),
              AppMenuOption(value: 'c', label: 'Gamma'),
            ],
            selected: 'b',
          );
        },
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    // 选中项用 check 图标标注，且不再依赖 PopupMenu 的通栏高亮矩形。
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    // 行高是 30（紧凑行），不是 Material 默认的 48。
    expect(tester.getSize(find.text('Alpha')).height, lessThanOrEqualTo(18));

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(picked, 'a');
    expect(find.text('Alpha'), findsNothing);
  });

  testWidgets('menu stays inside the window when anchored at the right edge', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, right: 4),
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    picked = await showAppMenu<String>(
                      context,
                      options: const [
                        AppMenuOption(value: 'x', label: 'First day'),
                        AppMenuOption(value: 'y', label: 'Second day'),
                      ],
                      selected: 'x',
                      anchor: AppMenuAnchor.start,
                    );
                  },
                  child: const Text('dates'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('dates'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final menuLeft = tester.getTopLeft(find.text('First day')).dx;
    final windowWidth = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(menuLeft, lessThan(windowWidth));

    await tester.tap(find.text('Second day'));
    await tester.pumpAndSettle();
    expect(picked, 'y');
  });

  testWidgets('menu hangs below the anchor and honours the anchor edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 300,
                top: 40,
                child: Builder(
                  builder: (context) => SizedBox.square(
                    dimension: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      tooltip: '',
                      onPressed: () => showAppMenu<String>(
                        context,
                        options: const [
                          AppMenuOption(value: 'a', label: 'Alpha'),
                          AppMenuOption(value: 'b', label: 'Beta'),
                        ],
                        anchor: AppMenuAnchor.end,
                      ),
                      icon: const Icon(Icons.more_vert_rounded, size: 18),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 40,
                top: 200,
                child: Builder(
                  builder: (context) => SizedBox(
                    height: 26,
                    child: TextButton(
                      onPressed: () => showAppMenu<String>(
                        context,
                        options: const [
                          AppMenuOption(value: 'a', label: 'Alpha'),
                          AppMenuOption(value: 'b', label: 'Beta'),
                        ],
                        anchor: AppMenuAnchor.start,
                      ),
                      child: const Text('days'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final buttonRect = tester.getRect(find.byType(IconButton));
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    final endRow = tester.getRect(find.text('Alpha'));
    // 菜单在按钮下方（不盖住按钮），右缘与按钮右缘对齐。
    expect(endRow.top, greaterThan(buttonRect.bottom));
    expect(buttonRect.right - endRow.right, closeTo(14, 1));
    expect(endRow.left, lessThan(buttonRect.left));
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    final chipRect = tester.getRect(find.byType(TextButton));
    await tester.tap(find.text('days'));
    await tester.pumpAndSettle();
    final startRow = tester.getRect(find.text('Alpha'));
    // 左缘对齐按钮左缘、向右展开（贴到窗口右边界时 showMenu 会整体左移，
    // 所以这里允许向左偏移几十像素，但绝不能是「右缘对齐」那种朝左长）。
    expect(startRow.top, greaterThan(chipRect.bottom));
    // 菜单从按钮左缘附近起、向右越过按钮右缘 —— 而不是右缘对齐朝左长。
    expect(startRow.left, lessThan(chipRect.left + 15));
    expect(startRow.right, greaterThan(chipRect.right));
  });

  testWidgets('matchAnchorWidth stretches the menu to the field width', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 40, top: 40),
              child: Builder(
                builder: (context) => GestureDetector(
                  onTap: () => showAppMenu<String>(
                    context,
                    options: const [
                      AppMenuOption(value: 'a', label: 'Alpha'),
                      AppMenuOption(value: 'b', label: 'Beta'),
                    ],
                    anchor: AppMenuAnchor.start,
                    matchAnchorWidth: true,
                  ),
                  child: Container(
                    width: 260,
                    height: 40,
                    alignment: Alignment.centerLeft,
                    color: const Color(0xFFEDEDED),
                    child: const Text('field'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('field'));
    await tester.pumpAndSettle();
    final fieldRect = tester.getRect(find.byType(Container).first);
    final rowRect = tester.getRect(find.text('Alpha'));
    // 菜单面板与输入框同宽：文字区 = 面板宽 - 左右各 14（6 inset + 8 item padding）。
    expect(rowRect.width, closeTo(fieldRect.width - 28, 2));
    expect(rowRect.left - fieldRect.left, closeTo(14, 1));
  });
}
