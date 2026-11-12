import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/theme/app_theme.dart';
import 'package:ui/ui/hover_tooltip.dart';

void main() {
  const theme = AppTheme();
  const window = Size(800, 600);

  group('where it goes', () {
    test('is one pixel under and to the right of the pointer', () {
      expect(
        placeTooltip(const Offset(100, 100), const Size(50, 20), window),
        const Offset(101, 101),
      );
    });

    test('is to the left of the pointer when the right edge is in the way', () {
      expect(
        placeTooltip(const Offset(790, 100), const Size(50, 20), window),
        const Offset(739, 101),
      );
    });

    test('is above the pointer when the bottom edge is in the way', () {
      expect(
        placeTooltip(const Offset(100, 590), const Size(50, 20), window),
        const Offset(101, 569),
      );
    });

    test('is at the corner of the window when it fits neither way', () {
      expect(
        placeTooltip(
          const Offset(20, 10),
          const Size(50, 20),
          const Size(40, 15),
        ),
        Offset.zero,
      );
    });

    test('keeps to the right of the pointer when it just fits', () {
      expect(
        placeTooltip(const Offset(700, 500), const Size(99, 98), window),
        const Offset(701, 501),
      );
    });
  });

  group('the panel', () {
    Future<void> pumpPanel(WidgetTester tester, Widget panel) =>
        tester.pumpWidget(
          MaterialApp(
            home: Align(alignment: Alignment.topLeft, child: panel),
          ),
        );

    testWidgets('has the room at the left and the top, and a box inside it', (
      tester,
    ) async {
      await pumpPanel(tester, const TooltipPanel(theme: theme, title: 'Close'));
      final panel = tester.getRect(find.byType(TooltipPanel));
      final box = tester.getRect(find.text('Close'));
      // the room, the border, and the padding of the box
      expect(box.left - panel.left, 8 + 1 + 8);
      expect(box.top - panel.top, closeTo(10 + 1 + 4, 0.5));
      expect(tester.widget<Text>(find.text('Close')).style!.fontSize, 14);
    });

    testWidgets('has the keys of what it names, with 16 between', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        const TooltipPanel(
          theme: theme,
          title: 'Go to Line/Column',
          keys: 'ctrl-g',
        ),
      );
      final title = tester.getRect(find.text('Go to Line/Column'));
      final keys = tester.getRect(find.text('Ctrl-G'));
      expect(keys.left - title.right, 16);
      expect(
        tester.widget<Text>(find.text('Ctrl-G')).style!.color,
        theme.textDim,
      );
    });

    testWidgets('has a line of meta under the title, smaller and dim', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        const TooltipPanel(theme: theme, title: 'Name', meta: 'More about it'),
      );
      final title = tester.getRect(find.text('Name'));
      final meta = tester.getRect(find.text('More about it'));
      expect(meta.top, greaterThanOrEqualTo(title.bottom));
      final style = tester.widget<Text>(find.text('More about it')).style!;
      expect(style.fontSize, 12);
      expect(style.color, theme.textDim);
    });

    testWidgets('has a title that is at most 288 wide, and goes on below', (
      tester,
    ) async {
      await pumpPanel(tester, TooltipPanel(theme: theme, title: 'word ' * 60));
      final title = tester.getRect(find.textContaining('word'));
      expect(title.width, lessThanOrEqualTo(288));
      expect(title.height, greaterThan(40));
    });

    testWidgets('is on the surface of the theme, with the subtle border', (
      tester,
    ) async {
      await pumpPanel(tester, const TooltipPanel(theme: theme, title: 'Close'));
      final box = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((b) => b.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.border != null);
      expect(box.color, theme.surface);
      expect((box.border! as Border).top.color, theme.borderVariant);
      expect(box.borderRadius, BorderRadius.circular(8));
    });
  });

  group('when it comes', () {
    Future<(TestGesture, HoverTooltipState)> pump(
      WidgetTester tester, {
      bool enabled = true,
      Alignment alignment = Alignment.center,
      String title = 'Go to Line/Column',
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: alignment,
            child: HoverTooltip(
              theme: theme,
              title: title,
              keys: 'ctrl-g',
              enabled: enabled,
              child: const SizedBox(width: 100, height: 40),
            ),
          ),
        ),
      );
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(5, 5));
      addTearDown(gesture.removePointer);
      await tester.pump();
      return (
        gesture,
        tester.state<HoverTooltipState>(find.byType(HoverTooltip)),
      );
    }

    testWidgets('is shown half a second after the pointer moves onto it', (
      tester,
    ) async {
      final (gesture, tip) = await pump(tester);
      await gesture.moveTo(tester.getCenter(find.byType(HoverTooltip)));
      await tester.pump(const Duration(milliseconds: 499));
      expect(tip.isShown, isFalse);
      await tester.pump(const Duration(milliseconds: 2));
      expect(tip.isShown, isTrue);
      expect(find.text('Go to Line/Column'), findsOneWidget);
      expect(find.text('Ctrl-G'), findsOneWidget);
    });

    testWidgets('is one pixel under and right of where the pointer is', (
      tester,
    ) async {
      final (gesture, _) = await pump(tester);
      final at = tester.getCenter(find.byType(HoverTooltip));
      await gesture.moveTo(at);
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        tester.getTopLeft(find.byType(TooltipPanel)),
        at + const Offset(1, 1),
      );
    });

    testWidgets('counts from the first move, and stays where it was shown', (
      tester,
    ) async {
      final (gesture, tip) = await pump(tester);
      final at = tester.getCenter(find.byType(HoverTooltip));
      await gesture.moveTo(at);
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveTo(at + const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 201));
      expect(tip.isShown, isTrue);
      // it was shown where the pointer was by then
      expect(
        tester.getTopLeft(find.byType(TooltipPanel)),
        at + const Offset(11, 1),
      );
      await gesture.moveTo(at + const Offset(20, 5));
      await tester.pump();
      expect(
        tester.getTopLeft(find.byType(TooltipPanel)),
        at + const Offset(11, 1),
      );
    });

    testWidgets('does not come when the pointer leaves before', (tester) async {
      final (gesture, tip) = await pump(tester);
      await gesture.moveTo(tester.getCenter(find.byType(HoverTooltip)));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveTo(const Offset(5, 5));
      await tester.pump(const Duration(seconds: 1));
      expect(tip.isShown, isFalse);
    });

    testWidgets('goes when the pointer leaves', (tester) async {
      final (gesture, tip) = await pump(tester);
      await gesture.moveTo(tester.getCenter(find.byType(HoverTooltip)));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tip.isShown, isTrue);
      await gesture.moveTo(const Offset(5, 5));
      await tester.pump();
      expect(tip.isShown, isFalse);
      expect(find.byType(TooltipPanel), findsNothing);
    });

    testWidgets('goes when it is pressed, and comes again on the next move', (
      tester,
    ) async {
      final (gesture, tip) = await pump(tester);
      final at = tester.getCenter(find.byType(HoverTooltip));
      await gesture.moveTo(at);
      await tester.pump(const Duration(milliseconds: 600));
      expect(tip.isShown, isTrue);
      await gesture.down(at);
      await tester.pump();
      expect(tip.isShown, isFalse);
      await gesture.up();
      await gesture.moveTo(at + const Offset(1, 0));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tip.isShown, isTrue);
    });

    testWidgets('goes when the wheel turns', (tester) async {
      final (gesture, tip) = await pump(tester);
      final at = tester.getCenter(find.byType(HoverTooltip));
      await gesture.moveTo(at);
      await tester.pump(const Duration(milliseconds: 600));
      expect(tip.isShown, isTrue);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: at,
          scrollDelta: const Offset(0, 20),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pump();
      expect(tip.isShown, isFalse);
    });

    testWidgets('is not shown when it is disabled, or when that comes', (
      tester,
    ) async {
      final (gesture, tip) = await pump(tester, enabled: false);
      await gesture.moveTo(tester.getCenter(find.byType(HoverTooltip)));
      await tester.pump(const Duration(seconds: 1));
      expect(tip.isShown, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            child: HoverTooltip(
              theme: theme,
              title: 'x',
              child: const SizedBox(width: 100, height: 40),
            ),
          ),
        ),
      );
      await gesture.moveTo(const Offset(5, 5));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.byType(HoverTooltip)));
      await tester.pump(const Duration(milliseconds: 600));
      final shown = tester.state<HoverTooltipState>(find.byType(HoverTooltip));
      expect(shown.isShown, isTrue);
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            child: HoverTooltip(
              theme: theme,
              title: 'x',
              enabled: false,
              child: const SizedBox(width: 100, height: 40),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(TooltipPanel), findsNothing);
    });

    testWidgets('is to the left of the pointer near the right edge', (
      tester,
    ) async {
      final (gesture, _) = await pump(tester, alignment: Alignment.centerRight);
      final at = tester.getCenter(find.byType(HoverTooltip));
      await gesture.moveTo(at);
      await tester.pump(const Duration(milliseconds: 600));
      final panel = tester.getRect(find.byType(TooltipPanel));
      expect(panel.right, at.dx - 1);
    });

    testWidgets('does not take the pointer, so what is under it still does', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            child: HoverTooltip(
              theme: theme,
              title: 'Tap',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: const SizedBox(width: 100, height: 40),
              ),
            ),
          ),
        ),
      );
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(5, 5));
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(HoverTooltip)));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byType(HoverTooltip));
      expect(taps, 1);
    });
  });
}
