import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/theme/app_theme.dart';
import 'package:ui/ui/picker.dart';

void main() {
  const theme = AppTheme();

  Future<BuildContext> host(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    return tester.element(find.byType(Scaffold));
  }

  testWidgets('typing filters a list, and enter picks the highlighted item', (
    tester,
  ) async {
    final context = await host(tester);
    int? picked;
    showListPicker(
      context,
      theme: theme,
      hint: 'Reopen with encoding...',
      items: const [
        PickerItem('UTF-8'),
        PickerItem('UTF-16 LE'),
        PickerItem('Big5'),
      ],
      onSelected: (i) => picked = i,
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'utf-16');
    await tester.pumpAndSettle();
    expect(find.text('UTF-8'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked, 1);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('the arrow keys move the highlight', (tester) async {
    final context = await host(tester);
    int? picked;
    showListPicker(
      context,
      theme: theme,
      hint: 'Pick',
      items: const [PickerItem('LF'), PickerItem('CRLF')],
      onSelected: (i) => picked = i,
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked, 1);
  });

  testWidgets('a list without a field starts on the checked item', (
    tester,
  ) async {
    final context = await host(tester);
    int? picked;
    showListPicker(
      context,
      theme: theme,
      items: const [PickerItem('LF'), PickerItem('CRLF', checked: true)],
      onSelected: (i) => picked = i,
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked, 1);
  });

  testWidgets('an input describes what is typed, and enter submits it', (
    tester,
  ) async {
    final context = await host(tester);
    String? submitted;
    showInputPicker(
      context,
      theme: theme,
      hint: '10:5',
      describe: (text) => 'typed "$text"',
      onSubmitted: (text) => submitted = text,
    );
    await tester.pumpAndSettle();

    expect(find.text('typed ""'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '12:3');
    await tester.pumpAndSettle();
    expect(find.text('typed "12:3"'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(submitted, '12:3');
  });

  testWidgets('escape closes it without choosing', (tester) async {
    final context = await host(tester);
    var picked = false;
    showListPicker(
      context,
      theme: theme,
      hint: 'Pick',
      items: const [PickerItem('LF')],
      onSelected: (_) => picked = true,
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('LF'), findsNothing);
    expect(picked, isFalse);
  });
}
