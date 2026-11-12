import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/theme/app_theme.dart';
import 'package:ui/ui/dialog.dart';

void main() {
  const theme = AppTheme();

  /// opens the dialog, and returns what it resolves to: empty while open
  Future<List<int?>> open(
    WidgetTester tester, {
    List<String> buttons = const ['Save all', 'Discard all', 'Cancel'],
    String message = 'Save changes?',
    List<String> details = const ['a.luau', 'untitled'],
  }) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final context = tester.element(find.byType(Scaffold));
    final chosen = <int?>[];
    showConfirmDialog(
      context,
      theme: theme,
      message: message,
      details: details,
      buttons: buttons,
    ).then(chosen.add);
    await tester.pumpAndSettle();
    return chosen;
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  Future<void> enter(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
  }

  testWidgets('it shows the message, the files and the buttons', (
    tester,
  ) async {
    await open(tester);
    for (final text in [
      'Save changes?',
      'a.luau',
      'untitled',
      'Save all',
      'Discard all',
      'Cancel',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
  });

  testWidgets('a click chooses a button', (tester) async {
    final chosen = await open(tester);
    await tester.tap(find.text('Discard all'));
    await tester.pumpAndSettle();
    expect(chosen, [1]);
    expect(find.text('Save changes?'), findsNothing);
  });

  group('how it looks', () {
    testWidgets('is 320 wide, with 16 around and between what is in it', (
      tester,
    ) async {
      await open(tester, details: const []);
      final box = tester.getRect(
        find
            .ancestor(
              of: find.text('Save changes?'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(box.width, DialogMetrics(theme).width);
      final message = tester.getRect(find.text('Save changes?'));
      // the border, and the padding
      expect(message.left - box.left, 1 + 16);
      expect(message.top - box.top, 1 + 16);
      final first = tester.getRect(find.text('Save all'));
      final lastButton = find
          .ancestor(of: find.text('Cancel'), matching: find.byType(Container))
          .first;
      expect(tester.getRect(lastButton).bottom, box.bottom - 1 - 16);
      expect(first.top - message.bottom, greaterThanOrEqualTo(16));
    });

    testWidgets('goes with the size of the interface, as everything in rems', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      showConfirmDialog(
        tester.element(find.byType(Scaffold)),
        theme: theme.copyWith(uiFontSize: 20),
        message: 'Save changes?',
        buttons: const ['OK'],
      );
      await tester.pumpAndSettle();
      final box = tester.getRect(
        find
            .ancestor(
              of: find.text('Save changes?'),
              matching: find.byType(Container),
            )
            .first,
      );
      // 20 over 16 of 320
      expect(box.width, 400);
      expect(
        tester.widget<Text>(find.text('Save changes?')).style!.fontSize,
        20,
      );
      expect(tester.widget<Text>(find.text('OK')).style!.fontSize, 17.5);
      final button = tester.getRect(
        find
            .ancestor(of: find.text('OK'), matching: find.byType(Container))
            .first,
      );
      expect(button.height, 27.5);
    });

    testWidgets(
      'has the buttons one under the other, 22 high and as wide as it',
      (tester) async {
        await open(tester, details: const []);
        Rect button(String label) => tester.getRect(
          find
              .ancestor(of: find.text(label), matching: find.byType(Container))
              .first,
        );
        final a = button('Save all');
        final b = button('Discard all');
        final c = button('Cancel');
        expect(a.height, 22);
        expect(b.top - a.bottom, 4);
        expect(c.top - b.bottom, 4);
        expect(a.width, 320 - 2 - 2 * 16);
        expect(a.left, b.left);
      },
    );

    testWidgets(
      'has the message at 16, the lines under it at 12, labels at 14',
      (tester) async {
        await open(tester);
        expect(
          tester.widget<Text>(find.text('Save changes?')).style!.fontSize,
          16,
        );
        expect(tester.widget<Text>(find.text('a.luau')).style!.fontSize, 12);
        expect(tester.widget<Text>(find.text('Cancel')).style!.fontSize, 14);
        expect(
          tester.widget<Text>(find.text('a.luau')).style!.color,
          theme.textDim,
        );
      },
    );

    testWidgets('has the first button tinted, and the others outlined', (
      tester,
    ) async {
      await open(tester);
      BoxDecoration decoration(String label) =>
          (find
                          .ancestor(
                            of: find.text(label),
                            matching: find.byType(Container),
                          )
                          .first
                          .evaluate()
                          .single
                          .widget
                      as Container)
                  .decoration!
              as BoxDecoration;
      final colors = DialogButtonColors(theme);
      expect(decoration('Save all').color, colors.tintFill);
      expect(
        (decoration('Save all').border! as Border).top.color,
        colors.tintLine,
      );
      expect(decoration('Cancel').color, colors.fill);
      expect((decoration('Cancel').border! as Border).top.color, colors.line);
    });

    testWidgets('has a button with the pointer on it in the color for that', (
      tester,
    ) async {
      await open(tester);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('Discard all')));
      await tester.pump();
      final colors = DialogButtonColors(theme);
      final box =
          find
                  .ancestor(
                    of: find.text('Discard all'),
                    matching: find.byType(Container),
                  )
                  .first
                  .evaluate()
                  .single
                  .widget
              as Container;
      expect((box.decoration! as BoxDecoration).color, colors.hoverFill);
      // the pointer does not move what enter chooses
      await enter(tester);
    });

    test('has a tinted button that is darker with the pointer on it', () {
      final colors = DialogButtonColors(theme);
      expect(
        HSLColor.fromColor(colors.tintHoverFill).lightness,
        lessThan(HSLColor.fromColor(colors.tintFill).lightness),
      );
      expect(colors.tintHoverFill.a, closeTo(colors.tintFill.a, 0.01));
    });
  });

  group('with the keys', () {
    testWidgets('enter chooses the first button', (tester) async {
      final chosen = await open(tester);
      await enter(tester);
      expect(chosen, [0]);
    });

    testWidgets('down and up move the choice, round the ends', (tester) async {
      var chosen = await open(tester);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await enter(tester);
      expect(chosen, [1]);

      chosen = await open(tester);
      await key(tester, LogicalKeyboardKey.arrowUp);
      await enter(tester);
      // up from the first is the last
      expect(chosen, [2]);

      chosen = await open(tester);
      for (var i = 0; i < 3; i++) {
        await key(tester, LogicalKeyboardKey.arrowDown);
      }
      await enter(tester);
      // down from the last is the first
      expect(chosen, [0]);
    });

    testWidgets('tab and shift tab go down and up', (tester) async {
      var chosen = await open(tester);
      await key(tester, LogicalKeyboardKey.tab);
      await enter(tester);
      expect(chosen, [1]);

      chosen = await open(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await key(tester, LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await enter(tester);
      expect(chosen, [2]);
    });

    testWidgets('control with n and p go down and up', (tester) async {
      final chosen = await open(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await key(tester, LogicalKeyboardKey.keyN);
      await key(tester, LogicalKeyboardKey.keyN);
      await key(tester, LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await enter(tester);
      expect(chosen, [1]);
    });

    testWidgets('home chooses the last button, and end the first', (
      tester,
    ) async {
      var chosen = await open(tester);
      await key(tester, LogicalKeyboardKey.home);
      await enter(tester);
      expect(chosen, [2]);

      chosen = await open(tester);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.end);
      await enter(tester);
      expect(chosen, [0]);

      chosen = await open(tester);
      await key(tester, LogicalKeyboardKey.pageUp);
      await enter(tester);
      expect(chosen, [2]);
    });

    testWidgets('escape chooses the button that is labeled Cancel', (
      tester,
    ) async {
      final chosen = await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(chosen, [2]);
    });

    testWidgets('escape does nothing when no button is labeled Cancel', (
      tester,
    ) async {
      final chosen = await open(tester, buttons: const ['OK']);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(chosen, isEmpty);
      expect(find.text('Save changes?'), findsOneWidget);
      await enter(tester);
      expect(chosen, [0]);
    });

    testWidgets('control with c does what escape does', (tester) async {
      final chosen = await open(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(chosen, [2]);
    });
  });

  group('the message', () {
    testWidgets('has the text between two backticks as it is, without them', (
      tester,
    ) async {
      await open(
        tester,
        message: '`a.luau` has unsaved edits',
        buttons: const ['OK'],
        details: const [],
      );
      expect(find.text('a.luau has unsaved edits'), findsOneWidget);
    });

    testWidgets('keeps a backtick that has no other', (tester) async {
      await open(
        tester,
        message: 'a `b` c ` d',
        buttons: const ['OK'],
        details: const [],
      );
      expect(find.text('a b c ` d'), findsOneWidget);
    });
  });
}
