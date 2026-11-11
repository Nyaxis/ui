import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor_core/buffer.dart' show AnchorRange;
import 'package:ui/editor_core/patch.dart' show Bias;
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
  ScrollbarSettings scrollbars = const ScrollbarSettings(),
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
            scrollbars: scrollbars,
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
      final render = await _pump(
        tester,
        controller,
        scrollbars: const ScrollbarSettings(show: ScrollbarVisibility.never),
      );
      expect(render.scrollbarLayouts(), isEmpty);
      final columns =
          ((500 - render.textLeft - _style.textPadding) / render.charWidth)
              .floor();
      expect(controller.display.wrapWidth, columns.toDouble());
      await _finish(tester, controller);
    });

    testWidgets('the thumb reaches the end of the track at the end', (
      tester,
    ) async {
      for (final text in [_long, 'one\ntwo\nthree']) {
        final controller = EditorController(text: text);
        final render = await _pump(tester, controller);
        controller.setScroll(y: 1e9);
        await tester.pump();
        final bar = render.scrollbar(ScrollbarAxis.vertical)!;
        expect(bar.thumb!.bottom, closeTo(bar.track.bottom, 1e-6));
        await _finish(tester, controller);
      }
    });
  });

  group('marks of the cursors', () {
    testWidgets('each cursor has a line in the track at its row', (
      tester,
    ) async {
      final controller = EditorController(text: _long);
      final render = await _pump(tester, controller);
      // the first cursor is on the first row, which is at the top
      var marks = render.cursorMarkers();
      expect(marks, hasLength(1));
      expect(marks.single.rect.top, 0);
      expect(marks.single.rect.height, 2);
      expect(marks.single.rect.left, 485 + 1);
      expect(marks.single.rect.right, 500);

      final bar = render.scrollbar(ScrollbarAxis.vertical)!;
      final text = controller.text;
      final at100 = text.indexOf('line 100');
      controller.selections.selectRanges([(0, 0), (at100, at100)]);
      await tester.pump();
      marks = render.cursorMarkers();
      expect(marks, hasLength(2));
      expect(marks.last.rect.top, closeTo(100 * bar.unitSize, 1e-6));
      await _finish(tester, controller);
    });

    testWidgets('cursors on rows next to each other are one line', (
      tester,
    ) async {
      final controller = EditorController(text: _long);
      final render = await _pump(tester, controller);
      final text = controller.text;
      final a = text.indexOf('line 10\n');
      final b = text.indexOf('line 11\n');
      controller.selections.selectRanges([(a, a), (b, b)]);
      await tester.pump();
      expect(render.cursorMarkers(), hasLength(1));
      await _finish(tester, controller);
    });
  });

  group('marks of the other places the selected text is', () {
    String text() => 'alpha\n${'x\n' * 50}alpha\n${'x\n' * 50}alpha';

    testWidgets('each is a mark in the middle third of the track', (
      tester,
    ) async {
      final controller = EditorController(text: text());
      final render = await _pump(tester, controller);
      expect(render.occurrenceMarkers(), isEmpty);
      controller.selections.selectRanges([(0, 5)]);
      controller.notifyListeners();
      await tester.pump();
      final marks = render.occurrenceMarkers();
      expect(marks, hasLength(2));
      final bar = render.scrollbar(ScrollbarAxis.vertical)!;
      // a third of the track after its line, less the line
      expect(marks.first.rect.left, bar.track.left + 1 + 4);
      expect(marks.first.rect.right, bar.track.left + 1 + 8);
      expect(marks.first.rect.height, greaterThanOrEqualTo(5));
      expect(marks.first.rect.top, closeTo(51 * bar.unitSize, 1e-6));
      expect(marks.last.rect.top, closeTo(102 * bar.unitSize, 1e-6));
      await _finish(tester, controller);
    });

    testWidgets('they keep the scrollbars while there are some', (
      tester,
    ) async {
      final controller = EditorController(text: text());
      final render = await _pump(
        tester,
        controller,
        scrollbars: const ScrollbarSettings(show: ScrollbarVisibility.auto),
      );
      // the cursor is in sight, and the text is scrolled a little
      controller.selections.selectRanges([(0, 5)]);
      controller.setScroll(y: 10);
      controller.notifyListeners();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1100));
      expect(render.scrollbarsVisible, isTrue);
      // with nothing selected, they go
      controller.selections.selectRanges([(0, 0)]);
      controller.notifyListeners();
      await tester.pump();
      expect(controller.occurrences, isEmpty);
      expect(render.scrollbarsVisible, isFalse);
      await _finish(tester, controller);
    });
  });

  group('showing and hiding', () {
    testWidgets(
      'with auto they stay when the system does not hide scrollbars',
      (tester) async {
        EditorController.systemAutoHide = false;
        addTearDown(() => EditorController.systemAutoHide = true);
        final controller = EditorController(text: _long);
        final render = await _pump(
          tester,
          controller,
          scrollbars: const ScrollbarSettings(show: ScrollbarVisibility.auto),
        );
        expect(render.scrollbarsVisible, isTrue);
        controller.setScroll(y: 10);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1100));
        expect(render.scrollbarsVisible, isTrue);
        await _finish(tester, controller);
      },
    );

    testWidgets('with auto they go a moment after the text was scrolled', (
      tester,
    ) async {
      final controller = EditorController(text: _long);
      final render = await _pump(
        tester,
        controller,
        scrollbars: const ScrollbarSettings(show: ScrollbarVisibility.auto),
      );
      expect(render.scrollbarsVisible, isTrue);
      controller.setScroll(y: 10);
      await tester.pump();
      expect(render.scrollbarsVisible, isTrue);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(render.scrollbarsVisible, isFalse);
      // still there for the pointer, which brings them back
      expect(render.scrollbar(ScrollbarAxis.vertical), isNotNull);
      final bar = render.scrollbar(ScrollbarAxis.vertical)!;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(100, 100));
      await mouse.moveTo(bar.track.center);
      await tester.pump();
      expect(render.scrollbarsVisible, isTrue);
      await mouse.removePointer();
      await tester.pump(const Duration(milliseconds: 1100));
      await _finish(tester, controller);
    });

    testWidgets('asking to scroll past the ends does not bring them back', (
      tester,
    ) async {
      final controller = EditorController(text: _long);
      final render = await _pump(
        tester,
        controller,
        scrollbars: const ScrollbarSettings(show: ScrollbarVisibility.auto),
      );
      controller.setScroll(y: 10);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1100));
      expect(render.scrollbarsVisible, isFalse);
      // back to the top is a scroll
      controller.setScroll(y: 0);
      await tester.pump();
      expect(render.scrollbarsVisible, isTrue);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(render.scrollbarsVisible, isFalse);
      // above the top is not: the text does not move
      controller.setScroll(y: -50);
      await tester.pump();
      expect(controller.scrollY, 0);
      expect(render.scrollbarsVisible, isFalse);
      await _finish(tester, controller);
    });

    testWidgets('and they stay while a cursor is out of sight', (tester) async {
      final controller = EditorController(text: _long);
      final render = await _pump(
        tester,
        controller,
        scrollbars: const ScrollbarSettings(show: ScrollbarVisibility.auto),
      );
      controller.setScroll(y: 2000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1100));
      // the cursor is on the first row, which is not on the screen
      expect(render.scrollbarsVisible, isTrue);
      await _finish(tester, controller);
    });

    testWidgets('always keeps them, and never has none', (tester) async {
      final controller = EditorController(text: _long);
      final render = await _pump(tester, controller);
      controller.setScroll(y: 10);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(render.scrollbarsVisible, isTrue);
      await _finish(tester, controller);
      final other = EditorController(text: _long);
      final never = await _pump(
        tester,
        other,
        scrollbars: const ScrollbarSettings(show: ScrollbarVisibility.never),
      );
      expect(never.scrollbarsVisible, isFalse);
      await _finish(tester, other);
    });
  });

  group('the settings of the scrollbar', () {
    AnchorRange place(EditorController controller, int row) {
      final from = controller.text.indexOf('line $row\n');
      return AnchorRange(
        controller.buffer.anchorAt(from, Bias.right),
        controller.buffer.anchorAt(from + 4, Bias.left),
      );
    }

    const colors = DiagnosticColors(
      error: 0xFFAA0000,
      warning: 0xFFBB0000,
      information: 0xFFCC0000,
      hint: 0xFFDD0000,
    );

    DiagnosticRanges every(EditorController controller) => DiagnosticRanges(
      errors: [place(controller, 50)],
      warnings: [place(controller, 80)],
      information: [place(controller, 110)],
      hints: [place(controller, 140)],
    );

    testWidgets('diagnostics are marks in the last third, in their colors', (
      tester,
    ) async {
      final controller = EditorController(text: _long)
        ..diagnosticColors = colors;
      final render = await _pump(tester, controller);
      controller.setDiagnostics(every(controller));
      await tester.pump();
      final marks = render.diagnosticMarkers();
      // the least bad first, so that the worst is painted last
      expect(marks.map((m) => m.color.toARGB32()), [
        0xFFDD0000,
        0xFFCC0000,
        0xFFBB0000,
        0xFFAA0000,
      ]);
      final bar = render.scrollbar(ScrollbarAxis.vertical)!;
      for (final mark in marks) {
        expect(mark.rect.left, bar.track.left + 1 + 8);
        expect(mark.rect.right, bar.track.left + 1 + 12);
        expect(mark.rect.height, greaterThanOrEqualTo(5));
      }
      expect(marks.last.rect.top, closeTo(50 * bar.unitSize, 1e-6));
      await _finish(tester, controller);
    });

    testWidgets('the setting says which diagnostics are marked', (
      tester,
    ) async {
      final controller = EditorController(text: _long)
        ..diagnosticColors = colors;
      final render = await _pump(tester, controller);
      controller.setDiagnostics(every(controller));
      await tester.pump();
      for (final (level, count) in [
        (ScrollbarDiagnostics.all, 4),
        (ScrollbarDiagnostics.information, 3),
        (ScrollbarDiagnostics.warning, 2),
        (ScrollbarDiagnostics.error, 1),
        (ScrollbarDiagnostics.none, 0),
      ]) {
        render.scrollbars = ScrollbarSettings(diagnostics: level);
        expect(render.diagnosticMarkers(), hasLength(count), reason: '$level');
      }
      await _finish(tester, controller);
    });

    testWidgets('marks next to each other are one when they are of a color', (
      tester,
    ) async {
      final controller = EditorController(text: _long)
        ..diagnosticColors = colors;
      final render = await _pump(tester, controller);
      controller.setDiagnostics(
        DiagnosticRanges(
          errors: [place(controller, 10), place(controller, 11)],
          warnings: [place(controller, 12)],
        ),
      );
      await tester.pump();
      // two errors that are next to each other, and a warning that is not
      // of their color
      expect(render.diagnosticMarkers(), hasLength(2));
      await _finish(tester, controller);
    });

    testWidgets('auto shows the scrollbars for what there is to mark', (
      tester,
    ) async {
      final controller = EditorController(text: _long)
        ..diagnosticColors = colors;
      final render = await _pump(
        tester,
        controller,
        scrollbars: const ScrollbarSettings(show: ScrollbarVisibility.auto),
      );
      // not shown for a moment, with the cursor in sight
      controller.scrollbarsShown = false;
      expect(render.scrollbarsVisible, isFalse);
      controller.setDiagnostics(every(controller));
      await tester.pump();
      expect(render.scrollbarsVisible, isTrue);
      render.scrollbars = const ScrollbarSettings(
        show: ScrollbarVisibility.auto,
        diagnostics: ScrollbarDiagnostics.none,
      );
      expect(render.scrollbarsVisible, isFalse);
      await _finish(tester, controller);
    });

    testWidgets('system does not show them for what there is to mark', (
      tester,
    ) async {
      final controller = EditorController(text: _long)
        ..diagnosticColors = colors;
      final render = await _pump(
        tester,
        controller,
        scrollbars: const ScrollbarSettings(show: ScrollbarVisibility.system),
      );
      controller.setDiagnostics(every(controller));
      await tester.pump();
      controller.scrollbarsShown = false;
      expect(render.scrollbarsVisible, isFalse);
      controller.scrollbarsShown = true;
      expect(render.scrollbarsVisible, isTrue);
      await _finish(tester, controller);
    });

    testWidgets('the other places of the selected text, by their setting', (
      tester,
    ) async {
      final controller = EditorController(
        text: 'alpha\n${'x\n' * 50}alpha\n${'x\n' * 50}alpha',
      );
      final render = await _pump(
        tester,
        controller,
        scrollbars: const ScrollbarSettings(show: ScrollbarVisibility.auto),
      );
      controller.selections.selectRanges([(0, 5)]);
      controller.notifyListeners();
      await tester.pump();
      controller.scrollbarsShown = false;
      expect(render.occurrenceMarkers(), hasLength(2));
      expect(render.scrollbarsVisible, isTrue);
      render.scrollbars = const ScrollbarSettings(
        show: ScrollbarVisibility.auto,
        selectedText: false,
      );
      expect(render.occurrenceMarkers(), isEmpty);
      expect(render.scrollbarsVisible, isFalse);
      await _finish(tester, controller);
    });

    testWidgets('the cursors are marked when the setting says so', (
      tester,
    ) async {
      final controller = EditorController(text: _long);
      final render = await _pump(tester, controller);
      expect(render.cursorMarkers(), hasLength(1));
      render.scrollbars = const ScrollbarSettings(cursors: false);
      expect(render.cursorMarkers(), isEmpty);
      await _finish(tester, controller);
    });

    testWidgets('a scrollbar can be forced off by its axis', (tester) async {
      final controller = EditorController(text: '${'x' * 2000}\n$_long');
      final render = await _pump(tester, controller, softWrap: false);
      expect(render.scrollbar(ScrollbarAxis.vertical), isNotNull);
      expect(render.scrollbar(ScrollbarAxis.horizontal), isNotNull);
      render.scrollbars = const ScrollbarSettings(horizontal: false);
      expect(render.scrollbar(ScrollbarAxis.vertical), isNotNull);
      expect(render.scrollbar(ScrollbarAxis.horizontal), isNull);
      render.scrollbars = const ScrollbarSettings(vertical: false);
      expect(render.scrollbar(ScrollbarAxis.vertical), isNull);
      expect(render.scrollbar(ScrollbarAxis.horizontal), isNotNull);
      await _finish(tester, controller);
    });
  });

  group('a tab that is switched to', () {
    const auto = ScrollbarSettings(show: ScrollbarVisibility.auto);

    testWidgets('keeps its scrollbars as they were when it was left', (
      tester,
    ) async {
      final controller = EditorController(text: _long);
      final render = await _pump(tester, controller, scrollbars: auto);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(render.scrollbarsVisible, isFalse);
      // the view is made again, as when another tab is shown and this one is
      // switched back to
      await tester.pumpWidget(const SizedBox());
      final again = await _pump(tester, controller, scrollbars: auto);
      expect(again.scrollbarsVisible, isFalse);
      await _finish(tester, controller);
    });

    testWidgets('shows them for a moment when it is made, and then hides', (
      tester,
    ) async {
      final controller = EditorController(text: _long);
      final render = await _pump(tester, controller, scrollbars: auto);
      expect(render.scrollbarsVisible, isTrue);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(render.scrollbarsVisible, isFalse);
      await _finish(tester, controller);
    });

    testWidgets('goes on hiding them while it is not shown', (tester) async {
      final controller = EditorController(text: _long);
      final render = await _pump(tester, controller, scrollbars: auto);
      expect(render.scrollbarsVisible, isTrue);
      // left within the moment, and come back to after it
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1100));
      final again = await _pump(tester, controller, scrollbars: auto);
      expect(again.scrollbarsVisible, isFalse);
      await _finish(tester, controller);
    });
  });
}
