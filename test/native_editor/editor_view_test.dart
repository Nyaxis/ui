import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor_core/display_map.dart';
import 'package:ui/native_editor/editor_controller.dart';
import 'package:ui/native_editor/editor_style.dart';
import 'package:ui/native_editor/editor_view.dart';
import 'package:ui/native_editor/render_editor.dart';

const _style = EditorStyle(
  textStyle: TextStyle(fontFamily: 'Roboto', fontSize: 14, height: 1.5),
);

Future<RenderEditor> _pump(
  WidgetTester tester,
  EditorController controller, {
  double width = 400,
  double height = 200,
  bool softWrap = true,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: width,
          height: height,
          child: EditorView(
            controller: controller,
            style: _style,
            softWrap: softWrap,
            autofocus: true,
          ),
        ),
      ),
    ),
  );
  return tester.allRenderObjects.whereType<RenderEditor>().single;
}

/// lets rows that are still being wrapped in the background be done, and
/// ends the editor
Future<void> _finish(WidgetTester tester, EditorController controller) async {
  for (var i = 0; i < 200 && controller.display.isRewrapping; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  await tester.pumpWidget(const SizedBox());
  controller.dispose();
}

void main() {
  group('EditorView', () {
    testWidgets('it paints a text and lays it out in rows', (tester) async {
      final controller = EditorController(text: 'one\ntwo\nthree');
      final render = await _pump(tester, controller);
      expect(render.size, const Size(400, 200));
      expect(controller.snapshot.rowCount, 3);
      expect(render.charWidth, greaterThan(0));
      expect(render.lineHeight, greaterThan(0));
      await _finish(tester, controller);
    });

    testWidgets('long lines wrap to the width of the view', (tester) async {
      final controller = EditorController(text: 'word ' * 60);
      final render = await _pump(tester, controller, width: 300);
      final columns =
          ((300 - render.textLeft - _style.textPadding) / render.charWidth)
              .floor();
      expect(controller.display.wrapWidth, columns.toDouble());
      expect(controller.snapshot.rowCount, greaterThan(3));
      for (var row = 0; row < controller.snapshot.rowCount; row++) {
        expect(controller.snapshot.lineLen(row), lessThanOrEqualTo(columns));
      }
      await _finish(tester, controller);
    });

    testWidgets('without wrapping the view scrolls sideways', (tester) async {
      final controller = EditorController(text: 'x' * 500);
      final render = await _pump(tester, controller, softWrap: false);
      expect(controller.snapshot.rowCount, 1);
      expect(render.contentSize.width, greaterThan(400));
      controller.selections.selectRanges([(500, 500)]);
      controller.requestRevealCursor();
      await tester.pump();
      expect(controller.scrollX, greaterThan(0));
      await _finish(tester, controller);
    });

    testWidgets('a long text scrolls down to the cursor', (tester) async {
      final controller = EditorController(
        text: List.generate(200, (i) => 'line $i').join('\n'),
      );
      await _pump(tester, controller);
      expect(controller.scrollY, 0);
      controller.selections.selectRanges([
        (controller.buffer.length, controller.buffer.length),
      ]);
      controller.requestRevealCursor();
      await tester.pump();
      expect(controller.scrollY, greaterThan(1000));
      await _finish(tester, controller);
    });

    testWidgets('the position of a click is a place in the text', (
      tester,
    ) async {
      final controller = EditorController(text: 'abcdef\nghijkl');
      final render = await _pump(tester, controller);
      final x = render.textLeft + render.charWidth * 3 + 1;
      expect(render.offsetForPosition(Offset(x, 5)), 3);
      expect(render.offsetForPosition(Offset(x, render.lineHeight + 5)), 7 + 3);
      // the caret is where the position is
      final caret = render.caretRectForOffset(3);
      expect(caret.left, closeTo(render.textLeft + render.charWidth * 3, 1.5));
      expect(caret.top, 0);
      await _finish(tester, controller);
    });

    testWidgets('typing and moving change the text and the cursor', (
      tester,
    ) async {
      final controller = EditorController(text: 'ab\ncd');
      await _pump(tester, controller);
      controller.selections.selectRanges([(1, 1)]);
      controller.replaceSelections('XY');
      expect(controller.text, 'aXYb\ncd');
      expect(controller.selections.first.start, 3);
      controller.moveVertically(down: true);
      expect(controller.selections.first.start, 7);
      controller.backspace();
      expect(controller.text, 'aXYb\nc');
      // edits close in time are one, so undo takes back all of them
      controller.undo();
      expect(controller.text, 'ab\ncd');
      expect(controller.selections.first.start, 1);
      controller.redo();
      expect(controller.text, 'aXYb\nc');
      await tester.pump();
      await _finish(tester, controller);
    });

    testWidgets('highlights and folds are painted without trouble', (
      tester,
    ) async {
      final controller = EditorController(text: 'let x = 1;\nlet y = 2;\n');
      await _pump(tester, controller);
      controller.highlights = Highlights(
        textHighlights: {
          1: TextHighlight(
            const HighlightStyle(color: 0xFFFF0000, bold: true),
            [controller.buffer.snapshot.anchorRangeInside(0, 3)],
          ),
        },
      );
      controller.display.fold([(11, 21, null)]);
      await tester.pump();
      expect(controller.snapshot.rowText(1), contains('⋯'));
      expect(tester.takeException(), isNull);
      await _finish(tester, controller);
    });
  });
}
