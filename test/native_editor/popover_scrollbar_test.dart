import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/editor_core/buffer.dart';
import 'package:ui/editor_core/patch.dart' show Bias;
import 'package:ui/native_editor/diagnostic_hover.dart';
import 'package:ui/native_editor/editor_controller.dart';
import 'package:ui/native_editor/editor_style.dart';
import 'package:ui/native_editor/editor_view.dart';
import 'package:ui/native_editor/popover_scrollbar.dart';
import 'package:ui/native_editor/render_editor.dart';
import 'package:ui/native_editor/scrollbar_layout.dart';

const _style = EditorStyle(
  textStyle: TextStyle(fontFamily: 'Roboto', fontSize: 14, height: 1.5),
);

void main() {
  group('where the thumb is', () {
    test('is none when everything is in view', () {
      expect(
        popoverThumb(viewport: 100, maxExtent: 0, offset: 0, length: 92),
        isNull,
      );
    });

    test('is as long as the share of the content that is in view', () {
      // 100 of 400 is a quarter, of the 92 that there is room for
      final thumb = popoverThumb(
        viewport: 100,
        maxExtent: 300,
        offset: 0,
        length: 92,
      )!;
      expect(thumb.start, 0);
      expect(thumb.length, closeTo(25 / 100 * 92, 1e-9));
    });

    test('is never shorter than 25 pixels of the view', () {
      final thumb = popoverThumb(
        viewport: 100,
        maxExtent: 9900,
        offset: 0,
        length: 100,
      )!;
      expect(thumb.length, 25);
    });

    test('goes to the end when the text is scrolled to its end', () {
      final thumb = popoverThumb(
        viewport: 100,
        maxExtent: 300,
        offset: 300,
        length: 100,
      )!;
      expect(thumb.start + thumb.length, closeTo(100, 1e-9));
    });

    test('is in the middle when the text is scrolled half way', () {
      final thumb = popoverThumb(
        viewport: 100,
        maxExtent: 300,
        offset: 150,
        length: 100,
      )!;
      expect(thumb.start, closeTo(37.5, 1e-9));
    });
  });

  group('the color of the thumb', () {
    const surface = Color(0xFF000000);
    const thumb = Color(0x80FFFFFF);

    test('is the thumb over the surface, at 70% opacity at most', () {
      final color = popoverThumbColor(
        thumb: thumb,
        surface: surface,
        hovered: false,
      );
      expect(color.a, closeTo(0.7, 1e-6));
      expect(color.r, closeTo(0.5019, 1e-3));
    });

    test('is not less opaque than the surface when that is', () {
      final color = popoverThumbColor(
        thumb: thumb,
        surface: const Color(0x4D000000),
        hovered: false,
      );
      expect(color.a, closeTo(0x4D / 255, 1e-6));
    });

    test('is as opaque as the surface when the pointer is on it', () {
      expect(
        popoverThumbColor(thumb: thumb, surface: surface, hovered: true).a,
        1.0,
      );
    });

    test(
      'is the thumb itself when that is opaque, and the surface when not',
      () {
        const solid = Color(0xFF123456);
        expect(
          popoverThumbColor(thumb: solid, surface: surface, hovered: false),
          solid,
        );
        expect(
          popoverThumbColor(
            thumb: const Color(0x00FFFFFF),
            surface: surface,
            hovered: true,
          ),
          surface,
        );
      },
    );
  });

  group('when it shows', () {
    test('follows the setting, and with system what the system does', () {
      PopoverScrollbarBehavior of(ScrollbarVisibility v, bool hides) =>
          popoverScrollbarBehavior(v, systemAutoHide: hides);
      expect(
        of(ScrollbarVisibility.auto, false),
        PopoverScrollbarBehavior.autoHide,
      );
      expect(
        of(ScrollbarVisibility.always, true),
        PopoverScrollbarBehavior.always,
      );
      expect(
        of(ScrollbarVisibility.never, false),
        PopoverScrollbarBehavior.never,
      );
      expect(
        of(ScrollbarVisibility.system, true),
        PopoverScrollbarBehavior.autoHide,
      );
      expect(
        of(ScrollbarVisibility.system, false),
        PopoverScrollbarBehavior.always,
      );
    });

    test('eases in and out', () {
      expect(popoverEase(0), 0);
      expect(popoverEase(0.25), closeTo(0.125, 1e-9));
      expect(popoverEase(0.5), closeTo(0.5, 1e-9));
      expect(popoverEase(0.75), closeTo(0.875, 1e-9));
      expect(popoverEase(1), 1);
    });
  });

  group('in the view', () {
    late EditorController controller;
    final message = [for (var i = 1; i <= 40; i++) 'line $i'].join('\n');

    setUp(() => controller = EditorController(text: 'local x = 1\nab'));
    tearDown(() => controller.dispose());

    Future<TestGesture> open(
      WidgetTester tester, {
      ScrollbarSettings scrollbars = const ScrollbarSettings(
        show: ScrollbarVisibility.auto,
      ),
      String? text,
    }) async {
      controller.setDiagnostics(
        DiagnosticRanges(
          details: [
            DiagnosticDetail(
              range: AnchorRange(
                controller.buffer.anchorAt(6, Bias.right),
                controller.buffer.anchorAt(7, Bias.left),
              ),
              level: DetailSeverity.warning,
              message: text ?? message,
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 500,
              height: 300,
              child: EditorView(
                controller: controller,
                style: _style,
                scrollbars: scrollbars,
                autofocus: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final render = tester.allRenderObjects.whereType<RenderEditor>().first;
      final caret = render.caretRectForOffset(6);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(450, 250));
      addTearDown(gesture.removePointer);
      await gesture.moveTo(
        render.localToGlobal(Offset(caret.left + 2, caret.center.dy)),
      );
      await tester.pump(const Duration(milliseconds: 350));
      return gesture;
    }

    PopoverScrollbarState bar(WidgetTester tester) =>
        tester.state<PopoverScrollbarState>(find.byType(PopoverScrollbar));

    /// lets [ms] pass a frame at a time, as the animation gets them
    Future<void> elapse(WidgetTester tester, int ms) async {
      for (var i = 0; i < ms ~/ 50; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    final thumb = find.byWidgetPredicate(
      (w) => w is Positioned && w.width == popoverThumbWidth,
    );

    testWidgets('is shown for a text that goes further than the popover', (
      tester,
    ) async {
      await open(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(bar(tester).isShown, isTrue);
      expect(thumb, findsOneWidget);
      final rect = tester.getRect(thumb);
      expect(rect.width, popoverThumbWidth);
      expect(rect.height, greaterThanOrEqualTo(popoverMinThumbLength - 1));
    });

    testWidgets('is not there for a text that fits', (tester) async {
      await open(tester, text: 'short');
      await tester.pump(const Duration(milliseconds: 100));
      expect(thumb, findsNothing);
    });

    testWidgets('goes a second after, fading for 400 ms', (tester) async {
      await open(tester);
      await elapse(tester, 100);
      expect(bar(tester).opacity, 0);
      var fadeBegan = -1;
      var gone = -1;
      for (var ms = 50; ms <= 3000 && gone < 0; ms += 50) {
        await tester.pump(const Duration(milliseconds: 50));
        if (fadeBegan < 0 && bar(tester).opacity > 0) {
          fadeBegan = ms;
        }
        if (!bar(tester).isShown) {
          gone = ms;
        }
      }
      // a second after the last time it was brought, with a fade of 400 ms
      expect(fadeBegan, inInclusiveRange(750, 1100));
      expect(gone - fadeBegan, inInclusiveRange(350, 500));
      expect(thumb, findsNothing);
    });

    testWidgets('comes back when the text scrolls', (tester) async {
      await open(tester);
      await elapse(tester, 2500);
      expect(thumb, findsNothing);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -40),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(bar(tester).isShown, isTrue);
      expect(thumb, findsOneWidget);
    });

    testWidgets('moves as the text scrolls', (tester) async {
      await open(tester);
      await tester.pump(const Duration(milliseconds: 100));
      final before = tester.getRect(thumb).top;
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -60),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getRect(thumb).top, greaterThan(before));
    });

    testWidgets('stays while the pointer is on it', (tester) async {
      final gesture = await open(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(tester.getCenter(thumb));
      await tester.pump();
      await elapse(tester, 3000);
      expect(bar(tester).isShown, isTrue);
      expect(bar(tester).opacity, 0);
    });

    testWidgets('scrolls the text when it is dragged', (tester) async {
      await open(tester);
      await tester.pump(const Duration(milliseconds: 100));
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(DiagnosticPopover),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrollable.position.pixels, 0);
      await tester.drag(thumb, const Offset(0, 30));
      await tester.pump();
      expect(scrollable.position.pixels, greaterThan(0));
    });

    testWidgets(
      'is always there with the setting always, and never with never',
      (tester) async {
        await open(
          tester,
          scrollbars: const ScrollbarSettings(show: ScrollbarVisibility.always),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(seconds: 3));
        expect(thumb, findsOneWidget);
      },
    );

    testWidgets('is never there with never', (tester) async {
      await open(
        tester,
        scrollbars: const ScrollbarSettings(show: ScrollbarVisibility.never),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(thumb, findsNothing);
    });
  });
}
