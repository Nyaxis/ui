import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/editor_core/buffer.dart';
import 'package:ui/editor_core/patch.dart' show Bias;
import 'package:ui/native_editor/editor_controller.dart';
import 'package:ui/native_editor/editor_style.dart';
import 'package:ui/native_editor/editor_view.dart';
import 'package:ui/native_editor/wavy_underline.dart';

void main() {
  group('the wave', () {
    test('is a sine of 0.8 strokes in height, as long as nine strokes', () {
      final bounds = wavyUnderlinePath(18).getBounds();
      expect(bounds.left, 0);
      expect(bounds.right, 18);
      // the bounds are three strokes high, and the wave is in the middle
      expect(bounds.top, closeTo(1.5 - 0.8, 0.05));
      expect(bounds.bottom, closeTo(1.5 + 0.8, 0.05));
    });

    test(
      'starts in the middle and goes down first, to its peak at a quarter',
      () {
        // y grows downward: the first half period is below the middle line
        final half = wavyUnderlinePath(4.5).getBounds();
        expect(half.top, closeTo(1.5, 0.01));
        expect(half.bottom, closeTo(1.5 + 0.8, 0.05));
        // and the second half is above it
        final whole = wavyUnderlinePath(9).getBounds();
        expect(whole.top, closeTo(1.5 - 0.8, 0.05));
        expect(whole.bottom, closeTo(1.5 + 0.8, 0.05));
      },
    );

    test('scales with the stroke', () {
      final bounds = wavyUnderlinePath(36, thickness: 2).getBounds();
      expect(bounds.top, closeTo(3 - 1.6, 0.1));
      expect(bounds.bottom, closeTo(3 + 1.6, 0.1));
    });
  });

  testWidgets('an editor with diagnostics paints their waves', (tester) async {
    final controller = EditorController(text: 'local x = nope\nlocal y = 1\n');
    AnchorRange range(int start, int end) => AnchorRange(
      controller.buffer.anchorAt(start, Bias.right),
      controller.buffer.anchorAt(end, Bias.left),
    );
    controller.setDiagnostics(
      DiagnosticRanges(errors: [range(10, 14)], warnings: [range(21, 22)]),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 200,
            child: EditorView(
              controller: controller,
              style: const EditorStyle(
                textStyle: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              softWrap: true,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    // one wave for each of the two places
    final editor = find.byType(EditorView);
    expect(
      editor,
      paints
        ..path()
        ..path(),
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
