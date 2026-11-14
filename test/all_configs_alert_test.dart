import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/config/theme.dart';
import 'package:oasx/modules/common/widgets/app_warning_badge.dart';
import 'package:oasx/modules/home/models/all_configs_filter.dart';
import 'package:oasx/modules/home/widgets/dashboard_home.dart';

void main() {
  group('filterAllConfigs', () {
    const names = ['CDB', 'YZJ', 'TST', 'Wanted'];

    test('no warning keeps the backend order', () {
      expect(filterAllConfigs(names), names);
    });

    test('stuck configs float to the top without reordering the rest', () {
      final ordered = filterAllConfigs(names, warnings: {'TST', 'CDB'});
      // 两个异常在前，各自的相对顺序仍按原列表（CDB 在 TST 之前）。
      expect(ordered, ['CDB', 'TST', 'YZJ', 'Wanted']);
    });

    test('onlyWarning keeps just the stuck configs', () {
      expect(
        filterAllConfigs(names, onlyWarning: true, warnings: {'YZJ'}),
        ['YZJ'],
      );
    });

    test('query matches case-insensitively and trims spaces', () {
      expect(filterAllConfigs(names, query: '  wanted '), ['Wanted']);
      expect(filterAllConfigs(names, query: 'zzz'), isEmpty);
    });

    test('query and onlyWarning are intersected', () {
      expect(
        filterAllConfigs(
          names,
          query: 'st',
          onlyWarning: true,
          warnings: {'CDB', 'TST'},
        ),
        ['TST'],
      );
    });
  });

  group('AppWarningBadge', () {
    Future<void> pumpBadge(WidgetTester tester, int count) {
      return tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          home: Scaffold(body: Center(child: AppWarningBadge(count: count))),
        ),
      );
    }

    testWidgets('shows the count on a 15px pill', (tester) async {
      await pumpBadge(tester, 3);
      expect(find.text('3'), findsOneWidget);
      expect(tester.getSize(find.byType(AppWarningBadge)).height, 15);
    });

    testWidgets('caps long counts so the badge stays narrow', (tester) async {
      await pumpBadge(tester, 128);
      expect(find.text('99+'), findsOneWidget);
    });
  });

  group('AllConfigsButton', () {
    Future<void> pumpButton(
      WidgetTester tester, {
      required List<String> warnings,
      int count = 12,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          home: Scaffold(
            body: Center(
              child: AllConfigsButton(
                count: count,
                warningNames: warnings,
                onTap: () {},
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('no badge and no widening when every config is healthy', (
      tester,
    ) async {
      await pumpButton(tester, warnings: const []);
      expect(find.byType(AppWarningBadge), findsNothing);
      expect(find.text('全部 12'), findsOneWidget);
    });

    testWidgets('badge rides on the grid icon and never covers the label', (
      tester,
    ) async {
      await pumpButton(tester, warnings: const ['YZJ', 'TST']);

      final badge = tester.getRect(find.byType(AppWarningBadge));
      final label = tester.getRect(find.text('全部 12'));
      final button = tester.getRect(find.byType(AllConfigsButton));

      // 回归：角标曾经挂在按钮右上角，R 之后落在图标与「全」之间压住文字。
      expect(
        badge.right,
        lessThanOrEqualTo(label.left),
        reason: 'badge must not overlap the "全部 N" label',
      );
      // 角标整体留在黄色描边之内，不溢出按钮、不碰到右侧方形按钮。
      expect(badge.left, greaterThan(button.left));
      expect(badge.top, greaterThan(button.top));
      expect(badge.bottom, lessThan(button.bottom));
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('tooltip reports the count without naming configs', (
      tester,
    ) async {
      await pumpButton(tester, warnings: const ['YZJ', 'TST']);
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip).first);
      expect(tooltip.message, contains('2'));
      // 名字不列出来：异常配置多时浮层会过长。
      expect(tooltip.message, isNot(contains('YZJ')));
      expect(tooltip.message, isNot(contains('TST')));
    });

    testWidgets('tooltip stays short even with many stuck configs', (
      tester,
    ) async {
      final many = [for (var i = 1; i <= 14; i++) 'Config$i'];
      await pumpButton(tester, warnings: many);
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip).first);
      expect(tooltip.message, contains('14'));
      expect(tooltip.message, isNot(contains('Config')));
    });
  });
}
