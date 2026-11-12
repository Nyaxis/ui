import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/theme/app_theme.dart';
import 'package:ui/ui/context_menu.dart';

void main() {
  const theme = AppTheme();

  Future<void> open(
    WidgetTester tester,
    List<ContextMenuEntry> entries, {
    Offset position = const Offset(20, 20),
  }) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    showContextMenu(
      tester.element(find.byType(Scaffold)),
      position: position,
      entries: entries,
      theme: theme,
      keysFor: (action) => {'tab::Close': 'ctrl-k w'}[action],
    );
    await tester.pump();
  }

  testWidgets('an item runs and closes the menu', (tester) async {
    var closed = 0;
    await open(tester, [
      ContextMenuItem('Close', onPressed: () => closed++),
      const ContextMenuSeparator(),
      const ContextMenuItem('Pin Tab', onPressed: null),
    ]);

    await tester.tap(find.text('Close'));
    await tester.pump();

    expect(closed, 1);
    expect(find.text('Close'), findsNothing);
  });

  testWidgets('a greyed out item does nothing', (tester) async {
    await open(tester, [const ContextMenuItem('Pin Tab')]);

    await tester.tap(find.text('Pin Tab'));
    await tester.pump();

    expect(find.text('Pin Tab'), findsOneWidget);
  });

  testWidgets('pressing outside or escape closes it', (tester) async {
    await open(tester, [ContextMenuItem('Close', onPressed: () {})]);
    await tester.tapAt(const Offset(700, 500));
    await tester.pump();
    expect(find.text('Close'), findsNothing);

    showContextMenu(
      tester.element(find.byType(Scaffold)),
      position: Offset.zero,
      entries: [ContextMenuItem('Close', onPressed: () {})],
      theme: theme,
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Close'), findsNothing);
  });

  testWidgets('the keys of an item\'s action are shown beside it', (
    tester,
  ) async {
    await open(tester, [
      ContextMenuItem('Close', onPressed: () {}, action: 'tab::Close'),
      ContextMenuItem('Pin Tab', onPressed: () {}, action: 'tab::Pin'),
    ]);

    expect(find.text('Ctrl-K W'), findsOneWidget);
    // an action without keys shows nothing
    expect(find.byType(Text), findsNWidgets(3));
  });

  testWidgets('a menu opened at the edge stays inside the window', (
    tester,
  ) async {
    await open(tester, [
      ContextMenuItem('Close', onPressed: () {}),
    ], position: const Offset(100000, 100000));

    final box = tester.getRect(find.byType(DecoratedBox).last);
    const window = Rect.fromLTWH(0, 0, 800, 600);
    expect(window.contains(box.topLeft), isTrue);
    expect(window.contains(box.bottomRight - const Offset(1, 1)), isTrue);
  });

  group('where it opens', () {
    const window = Size(800, 600);
    const size = Size(200, 100);

    test('has its top left at the position when it is inside the window', () {
      expect(
        placeContextMenu(const Offset(300, 200), size, window),
        const Offset(300, 200),
      );
    });

    test('is not moved from near an edge when it does not go past it', () {
      // three pixels from the left and the top is inside, so it stays
      expect(
        placeContextMenu(const Offset(3, 3), size, window),
        const Offset(3, 3),
      );
      expect(
        placeContextMenu(const Offset(598, 498), size, window),
        const Offset(598, 498),
      );
    });

    test(
      'is eight pixels from the right and bottom edges when it goes past',
      () {
        expect(
          placeContextMenu(const Offset(700, 560), size, window),
          const Offset(592, 492),
        );
      },
    );

    test(
      'is eight pixels from the left and the top when it goes past them',
      () {
        expect(
          placeContextMenu(
            const Offset(20, 10),
            size,
            window,
            anchor: ContextMenuAnchor.bottomRight,
          ),
          const Offset(8, 8),
        );
      },
    );

    test('has its bottom left at the position of a button below it', () {
      expect(
        placeContextMenu(
          const Offset(300, 580),
          size,
          window,
          anchor: ContextMenuAnchor.bottomLeft,
        ),
        const Offset(300, 480),
      );
    });

    test('has its bottom right at the position of a button on the right', () {
      expect(
        placeContextMenu(
          const Offset(780, 580),
          size,
          window,
          anchor: ContextMenuAnchor.bottomRight,
        ),
        const Offset(580, 480),
      );
    });

    test(
      'is at the margin of the left and the top when bigger than the window',
      () {
        expect(
          placeContextMenu(
            const Offset(100, 100),
            const Size(900, 700),
            window,
          ),
          const Offset(8, 8),
        );
      },
    );

    testWidgets('opens above a button when the bottom left is at its top', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      showContextMenu(
        tester.element(find.byType(Scaffold)),
        position: const Offset(100, 580),
        anchor: ContextMenuAnchor.bottomLeft,
        entries: [ContextMenuItem('Left', onPressed: () {})],
        theme: theme,
      );
      await tester.pump();
      await tester.pump();
      final box = tester.getRect(find.byType(DecoratedBox).first);
      expect(box.bottomLeft, const Offset(100, 580));
    });
  });

  group('how it looks', () {
    testWidgets('is at least 200 wide, and an item is a line of text high', (
      tester,
    ) async {
      await open(tester, [ContextMenuItem('A', onPressed: () {})]);
      final panel = tester.getRect(find.byType(DecoratedBox).first);
      expect(panel.width, 200);
      // the item, and four pixels above and below it, and the border
      expect(
        panel.height,
        closeTo(ContextMenuMetrics.itemHeight + 2 * 4 + 2, 0.5),
      );
    });

    testWidgets('is as wide as its widest item when that is more than 200', (
      tester,
    ) async {
      await open(tester, [
        ContextMenuItem('A', onPressed: () {}),
        ContextMenuItem('x' * 60, onPressed: () {}),
      ]);
      expect(
        tester.getRect(find.byType(DecoratedBox).first).width,
        greaterThan(200),
      );
    });

    testWidgets('has the text at 14 pixels, and the fill of an item inset', (
      tester,
    ) async {
      await open(tester, [ContextMenuItem('Close', onPressed: () {})]);
      final text = tester.widget<Text>(find.text('Close'));
      final style = DefaultTextStyle.of(tester.element(find.text('Close')));
      expect(style.style.fontSize, 14);
      expect(style.style.height, 1.618);
      expect(text.style!.color, theme.textPrimary);
      final panel = tester.getRect(find.byType(DecoratedBox).first);
      final label = tester.getRect(find.text('Close'));
      // 1 border, 4 inset, 6 in the fill
      expect(label.left - panel.left, closeTo(1 + 4 + 6, 0.5));
    });

    testWidgets('has a separator of one pixel with six above and below', (
      tester,
    ) async {
      await open(tester, [
        ContextMenuItem('A', onPressed: () {}),
        const ContextMenuSeparator(),
        ContextMenuItem('B', onPressed: () {}),
      ]);
      final a = tester.getRect(find.text('A'));
      final b = tester.getRect(find.text('B'));
      expect(
        b.top - a.top,
        closeTo(ContextMenuMetrics.itemHeight + 6 + 1 + 6, 0.5),
      );
    });

    testWidgets('keeps the room of a check mark for the items without one', (
      tester,
    ) async {
      await open(tester, [
        ContextMenuItem('A', onPressed: () {}, checked: true),
        ContextMenuItem('B', onPressed: () {}, checked: false),
      ]);
      expect(
        tester.getRect(find.text('A')).left,
        tester.getRect(find.text('B')).left,
      );
    });

    testWidgets('greys out an item with the color for what cannot be used', (
      tester,
    ) async {
      await open(tester, [const ContextMenuItem('Pin Tab')]);
      expect(
        tester.widget<Text>(find.text('Pin Tab')).style!.color,
        theme.disabled,
      );
    });
  });

  group('with the keys', () {
    List<String> log() => <String>[];

    Future<List<String>> menu(WidgetTester tester) async {
      final pressed = log();
      await open(tester, [
        ContextMenuItem('A', onPressed: () => pressed.add('A')),
        const ContextMenuSeparator(),
        const ContextMenuItem('Off'),
        ContextMenuItem('B', onPressed: () => pressed.add('B')),
        ContextMenuItem('C', onPressed: () => pressed.add('C')),
      ]);
      return pressed;
    }

    testWidgets('down chooses the first item, and then the next', (
      tester,
    ) async {
      final pressed = await menu(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      // the separator and the greyed out item are passed
      expect(pressed, ['B']);
      expect(find.text('A'), findsNothing);
    });

    testWidgets('down from the last goes to the first, and up the other way', (
      tester,
    ) async {
      final pressed = await menu(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      // up with none chosen is the last, and down from it is the first
      expect(pressed, ['A']);
    });

    testWidgets('up goes to the item before', (tester) async {
      final pressed = await menu(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(pressed, ['B']);
    });

    testWidgets('home and end choose the first and the last', (tester) async {
      final pressed = await menu(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(pressed, ['A']);
    });

    testWidgets('tab and shift tab go down and up', (tester) async {
      final pressed = await menu(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(pressed, ['B']);
    });

    testWidgets('enter with none chosen only closes the menu', (tester) async {
      final pressed = await menu(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(pressed, isEmpty);
      expect(find.text('A'), findsNothing);
    });

    testWidgets('the pointer going over an item takes the choice away', (
      tester,
    ) async {
      final pressed = await menu(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(700, 500));
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('C')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(pressed, isEmpty);
    });

    testWidgets('the chosen item has a fill of its own', (tester) async {
      await menu(tester);
      Color? fill(String label) {
        // the nearest box around the label is the fill of its item
        final box = find
            .ancestor(of: find.text(label), matching: find.byType(DecoratedBox))
            .evaluate()
            .first
            .widget;
        final color = ((box as DecoratedBox).decoration as BoxDecoration).color;
        return color == Colors.transparent ? null : color;
      }

      expect(fill('A'), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(fill('A'), ContextMenuColors(theme).selected);
      expect(fill('B'), isNull);
    });

    testWidgets('control with n, p and c do what down, up and escape do', (
      tester,
    ) async {
      final pressed = await menu(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(pressed, ['A']);

      await menu(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(find.text('A'), findsNothing);
    });
  });

  group('colors', () {
    test('are the fills of an item as the theme says', () {
      final colors = ContextMenuColors(theme);
      expect(colors.hover, theme.hover.withValues(alpha: 0x4D / 255));
      expect(colors.pressed, theme.active.withValues(alpha: 0x99 / 255));
      expect(colors.selected.a, closeTo(0x66 / 255, 1e-3));
    });
  });

  group('a long menu', () {
    testWidgets('is at most three quarters of the window high, and scrolls', (
      tester,
    ) async {
      await open(tester, [
        for (var i = 0; i < 60; i++)
          ContextMenuItem('Item $i', onPressed: () {}),
      ]);
      await tester.pump();
      final panel = tester.getRect(find.byType(DecoratedBox).first);
      expect(panel.height, lessThanOrEqualTo(600 * 0.75 + 1));
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('scrolls to the item that the keys choose', (tester) async {
      await open(tester, [
        for (var i = 0; i < 60; i++)
          ContextMenuItem('Item $i', onPressed: () {}),
      ]);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scrollable.position.pixels, greaterThan(0));
      final item = tester.getRect(find.text('Item 59'));
      final panel = tester.getRect(find.byType(DecoratedBox).first);
      expect(panel.contains(item.center), isTrue);
    });

    testWidgets('does not scroll when everything fits', (tester) async {
      await open(tester, [ContextMenuItem('A', onPressed: () {})]);
      await tester.pump();
      expect(find.byType(SingleChildScrollView), findsNothing);
    });
  });
}
