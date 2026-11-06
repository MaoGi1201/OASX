import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/modules/args/index.dart';

/// 打开「分项修改」弹窗，跑完关闭动画，并断言过程中没有抛异常。
Future<void> _openEditor(
  WidgetTester tester, {
  required String value,
  required void Function(String) onChange,
  required bool confirm,
  Future<void> Function()? edit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: DateTimePicker(value: value, onChange: onChange),
        ),
      ),
    ),
  );
  await tester.tap(find.byIcon(Icons.av_timer_rounded));
  await tester.pumpAndSettle();
  expect(find.text('分项修改时间'), findsOneWidget);

  if (edit != null) {
    await edit();
  }

  // 弹窗的 FocusNode 由弹窗自己释放；这里跑完退出动画，确保不会出现
  // "A FocusNode was used after being disposed"。
  await tester.tap(
    confirm ? find.byType(FilledButton) : find.byType(TextButton),
  );
  await tester.pumpAndSettle();
  expect(find.text('分项修改时间'), findsNothing);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('分项修改弹窗按分量拼接出完整的日期时间', (tester) async {
    String? changed;
    await _openEditor(
      tester,
      value: '2026-11-04 12:34:56',
      onChange: (value) => changed = value,
      confirm: true,
      // 第 4 个输入框是「时」。
      edit: () => tester.enterText(find.byType(TextField).at(3), '08'),
    );

    expect(changed, '2026-11-04 08:34:56');
  });

  testWidgets('分项修改弹窗取消后不回调，也不留下已释放的焦点节点', (tester) async {
    var called = false;
    await _openEditor(
      tester,
      value: '2026-11-04 12:34:56',
      onChange: (_) => called = true,
      confirm: false,
    );

    expect(called, isFalse);
  });
}
