import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/native_editor/editor_controller.dart';
import 'package:ui/native_editor/editor_style.dart';
import 'package:ui/native_editor/editor_view.dart';
import 'package:ui/native_editor/render_editor.dart';
import 'package:ui/native_editor/scrollbar_layout.dart';

const _style = EditorStyle(
  textStyle: TextStyle(fontFamily: 'Roboto', fontSize: 14, height: 1.5),
);

String get _long => List.generate(200, (i) => 'line $i').join('\n');

Future<RenderEditor> _pump(
  WidgetTester tester,
  EditorController controller, {
  bool softWrap = true,
  bool showScrollbars = true,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 500,
          height: 300,
          child: EditorView(
            controller: controller,
            style: _style,
            softWrap: softWrap,
            showScrollbars: showScrollbars,
            autofocus: true,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.allRenderObjects.whereType<RenderEditor>().single;
}

Future<void> _finish(WidgetTester tester, EditorController controller) async {
  for (var i = 0; i < 200 && controller.display.isRewrapping; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  await tester.pumpWidget(const SizedBox());
  controller.dispose();
}

void main() {
  group('scrollbars', () {
    testWidgets('a long text has a thumb in the track at the right', (
      tester,
    ) async {
      final controller = EditorController(text: _long);
      final render = await _pump(tester, controller);
      final bar = render.scrollbar(ScrollbarAxis.vertical)!;
      expect(bar.track.right, 500);
      expect(bar.track.width, _style.scrollbarWidth);
      expect(bar.track.height, 300);
      expect(bar.thumb!.top, 0);
      expect(bar.thumb!.height, lessThan(300));
      controller.setScroll(y: 2000);
      await tester.pump();
      final moved = render.scrollbar(ScrollbarAxis.vertical)!;
      expect(moved.thumb!.top, greaterThan(0));
      await _finish(tester, controller);
    });

    testWidgets(
      'a short text can still scroll until its last line is at the top',
      (tester) async {
        final controller = EditorController(text: 'one\ntwo');
        final render = await _pump(tester, controller);
        final bar = render.scrollbar(ScrollbarAxis.vertical)!;
        expect(bar.track.width, _style.scrollbarWidth);
        // there is a page of room under the text, so the thumb is most of the track
        expect(bar.thumb!.height, greaterThan(200));
        await _finish(tester, controller);
      },
    );

    testWidgets('the text does not go under the scrollbar', (tester) async {
      final controller = EditorController(text: 'word ' * 100);
      final render = await _pump(tester, controller);
      final columns =
          ((500 -
                      render.textLeft -
                      _style.textPadding -
                      _style.scrollbarWidth) /
                  render.charWidth)
              .floor();
      expect(controller.display.wrapWidth, columns.toDouble());
      await _finish(tester, controller);
    });

    testWidgets('pressing the track off the thumb scrolls there', (
      tester,
    ) async {
      final controller = EditorController(text: _long);
      final render = await _pump(tester, controller);
      expect(controller.scrollY, 0);
      final bar = render.scrollbar(ScrollbarAxis.vertical)!;
      final at = Offset(bar.track.center.dx, 250);
      expect(bar.thumb!.contains(at), isFalse);
      final cursorBefore = controller.selections.first.head;
      await tester.tapAt(at);
      await tester.pump();
      expect(controller.scrollY, greaterThan(0));
      // the press did not put the cursor anywhere
      expect(controller.selections.first.head, cursorBefore);
      await _finish(tester, controller);
    });

    testWidgets('dragging the thumb scrolls by what it moved', (tester) async {
      final controller = EditorController(text: _long);
      final render = await _pump(tester, controller);
      final bar = render.scrollbar(ScrollbarAxis.vertical)!;
      final gesture = await tester.startGesture(bar.thumb!.center);
      await tester.pump();
      expect(render.thumbState(ScrollbarAxis.vertical), ThumbState.dragging);
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      // 20 pixels of the thumb are this many rows of the text
      final rows = 20 / bar.unitSize;
      expect(controller.scrollY, closeTo(rows * render.lineHeight, 1e-6));
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      expect(controller.scrollY, closeTo(3 * rows * render.lineHeight, 1e-6));
      await gesture.up();
      await tester.pump();
      expect(
        render.thumbState(ScrollbarAxis.vertical),
        isNot(ThumbState.dragging),
      );
      await _finish(tester, controller);
    });

    testWidgets('the thumb is lit when the mouse is over it', (tester) async {
      final controller = EditorController(text: _long);
      final render = await _pump(tester, controller);
      final bar = render.scrollbar(ScrollbarAxis.vertical)!;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(100, 100));
      await tester.pump();
      expect(render.thumbState(ScrollbarAxis.vertical), ThumbState.idle);
      await mouse.moveTo(bar.thumb!.center);
      await tester.pump();
      expect(render.thumbState(ScrollbarAxis.vertical), ThumbState.hovered);
      await mouse.moveTo(const Offset(100, 100));
      await tester.pump();
      expect(render.thumbState(ScrollbarAxis.vertical), ThumbState.idle);
      await mouse.removePointer();
      await _finish(tester, controller);
    });

    testWidgets('without wrapping, a scrollbar goes along the bottom', (
      tester,
    ) async {
      final controller = EditorController(text: 'x' * 500);
      final render = await _pump(tester, controller, softWrap: false);
      final bar = render.scrollbar(ScrollbarAxis.horizontal)!;
      expect(bar.track.bottom, 300);
      expect(bar.track.height, _style.scrollbarWidth);
      expect(bar.thumb, isNotNull);
      final gesture = await tester.startGesture(bar.thumb!.center);
      await gesture.moveBy(const Offset(30, 0));
      await gesture.up();
      await tester.pump();
      expect(controller.scrollX, greaterThan(0));
      await _finish(tester, controller);
    });

    testWidgets('wrapped text has no scrollbar along the bottom', (
      tester,
    ) async {
      final controller = EditorController(text: 'x' * 500);
      final render = await _pump(tester, controller);
      expect(render.scrollbar(ScrollbarAxis.horizontal), isNull);
      await _finish(tester, controller);
    });

    testWidgets('when they are off there are none, and the text is as wide', (
      tester,
    ) async {
      final controller = EditorController(text: _long + 'word ' * 100);
      final render = await _pump(tester, controller, showScrollbars: false);
      expect(render.scrollbarLayouts(), isEmpty);
      final columns =
          ((500 - render.textLeft - _style.textPadding) / render.charWidth)
              .floor();
      expect(controller.display.wrapWidth, columns.toDouble());
      await _finish(tester, controller);
    });
  });
}
