import 'package:flutter/gestures.dart';
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

  group('how it looks', () {
    Future<void> openList(
      WidgetTester tester, {
      int count = 3,
      String? hint = 'Pick',
    }) async {
      final context = await host(tester);
      showListPicker(
        context,
        theme: theme,
        hint: hint,
        items: [for (var i = 0; i < count; i++) PickerItem('Item $i')],
        onSelected: (_) {},
      );
      await tester.pumpAndSettle();
    }

    Rect panel(WidgetTester tester) => tester.getRect(
      find
          .ancestor(
            of: find.byType(TextField),
            matching: find.byType(Container),
          )
          .last,
    );

    testWidgets('is 544 wide for a list, with a field of 36 and a line of 1', (
      tester,
    ) async {
      await openList(tester);
      final box = panel(tester);
      expect(box.width, PickerMetrics.listWidth);
      final field = tester.getRect(
        find
            .ancestor(
              of: find.byType(TextField),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(field.height, 36);
      final first = tester.getRect(find.text('Item 0'));
      // the border, the field, the line, and four above the rows
      expect(first.top, greaterThan(box.top + 1 + 36 + 1 + 4));
    });

    testWidgets('is 384 wide for a line of text', (tester) async {
      final context = await host(tester);
      showInputPicker(
        context,
        theme: theme,
        hint: '10:5',
        describe: (_) => '',
        onSubmitted: (_) {},
      );
      await tester.pumpAndSettle();
      expect(panel(tester).width, PickerMetrics.inputWidth);
    });

    testWidgets('has rows of one line of 14 pixel text with four around it', (
      tester,
    ) async {
      await openList(tester);
      final a = tester.getRect(find.text('Item 0'));
      final b = tester.getRect(find.text('Item 1'));
      expect(b.top - a.top, closeTo(PickerMetrics.rowHeight, 0.01));
      expect(tester.widget<Text>(find.text('Item 0')).style!.fontSize, 14);
      // the border, four of inset, and six in the fill
      expect(a.left - panel(tester).left, closeTo(1 + 4 + 6, 0.5));
    });

    testWidgets('is at most 384 high in the list, which scrolls', (
      tester,
    ) async {
      await openList(tester, count: 40);
      expect(find.byType(ListView), findsOneWidget);
      expect(
        tester.getSize(find.byType(ListView)).height,
        lessThanOrEqualTo(PickerMetrics.maxListHeight),
      );
    });

    testWidgets('has the chosen row filled as the theme says for it', (
      tester,
    ) async {
      await openList(tester);
      Color? fill(String label) {
        final box =
            find
                    .ancestor(
                      of: find.text(label),
                      matching: find.byType(Container),
                    )
                    .evaluate()
                    .first
                    .widget
                as Container;
        final color = (box.decoration! as BoxDecoration).color;
        return color == Colors.transparent ? null : color;
      }

      expect(fill('Item 0'), theme.chosen.withValues(alpha: 0x66 / 255));
      expect(fill('Item 1'), isNull);
    });
  });

  group('with the keys', () {
    Future<List<int>> openList(
      WidgetTester tester, {
      String? hint = 'Pick',
    }) async {
      final context = await host(tester);
      final picked = <int>[];
      showListPicker(
        context,
        theme: theme,
        hint: hint,
        items: const [PickerItem('A'), PickerItem('B'), PickerItem('C')],
        onSelected: picked.add,
      );
      await tester.pumpAndSettle();
      return picked;
    }

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }

    testWidgets(
      'down from the last row goes to the first, and up the other way',
      (tester) async {
        var picked = await openList(tester);
        for (var i = 0; i < 3; i++) {
          await press(tester, LogicalKeyboardKey.arrowDown);
        }
        await press(tester, LogicalKeyboardKey.enter);
        expect(picked, [0]);

        await tester.pumpAndSettle();
        picked = await openList(tester);
        await press(tester, LogicalKeyboardKey.arrowUp);
        await press(tester, LogicalKeyboardKey.enter);
        expect(picked, [2]);
      },
    );

    testWidgets('tab and shift tab, and control with n and p, move too', (
      tester,
    ) async {
      final picked = await openList(tester);
      await press(tester, LogicalKeyboardKey.tab);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await press(tester, LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await press(tester, LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await press(tester, LogicalKeyboardKey.enter);
      expect(picked, [1]);
    });

    testWidgets('page down goes to the last row, and page up to the first', (
      tester,
    ) async {
      final picked = await openList(tester);
      await press(tester, LogicalKeyboardKey.pageDown);
      await press(tester, LogicalKeyboardKey.pageUp);
      await press(tester, LogicalKeyboardKey.pageDown);
      await press(tester, LogicalKeyboardKey.enter);
      expect(picked, [2]);
    });

    testWidgets('home and end are for the field, unless there is none', (
      tester,
    ) async {
      var picked = await openList(tester);
      await press(tester, LogicalKeyboardKey.end);
      await press(tester, LogicalKeyboardKey.enter);
      // the field took it, so the first row is still the highlighted
      expect(picked, [0]);

      await tester.pumpAndSettle();
      picked = await openList(tester, hint: null);
      await press(tester, LogicalKeyboardKey.end);
      await press(tester, LogicalKeyboardKey.enter);
      expect(picked, [2]);
    });

    testWidgets('the pointer going over a row chooses it', (tester) async {
      final picked = await openList(tester);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(700, 500));
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('C')));
      await tester.pump();
      await press(tester, LogicalKeyboardKey.enter);
      expect(picked, [2]);
    });
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
