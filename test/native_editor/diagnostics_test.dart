import 'package:flutter_test/flutter_test.dart';
import 'package:ui/editor_core/buffer.dart';
import 'package:ui/editor_core/highlight.dart';
import 'package:ui/editor_core/patch.dart' show Bias;
import 'package:ui/native_editor/editor_controller.dart';

void main() {
  late EditorController controller;

  AnchorRange range(int start, int end) => AnchorRange(
    controller.buffer.anchorAt(start, Bias.right),
    controller.buffer.anchorAt(end, Bias.left),
  );

  setUp(() {
    controller = EditorController(text: 'local x = nope');
    controller.diagnosticColors = const DiagnosticColors(
      error: 0xFF111111,
      warning: 0xFF222222,
      information: 0xFF333333,
      hint: 0xFF444444,
    );
  });

  tearDown(() => controller.dispose());

  List<HighlightStyle> styles() => [
    for (final key
        in controller.highlights.textHighlights.keys.toList()..sort())
      controller.highlights.textHighlights[key]!.style,
  ];

  test('a diagnostic is a wavy underline in the color of how bad it is', () {
    controller.setDiagnostics(
      DiagnosticRanges(
        errors: [range(10, 14)],
        warnings: [range(6, 7)],
        information: [range(0, 5)],
        hints: [range(8, 9)],
      ),
    );
    expect(styles(), [
      const HighlightStyle(
        underline: true,
        underlineColor: 0xFF444444,
        wavy: true,
      ),
      const HighlightStyle(
        underline: true,
        underlineColor: 0xFF333333,
        wavy: true,
      ),
      const HighlightStyle(
        underline: true,
        underlineColor: 0xFF222222,
        wavy: true,
      ),
      const HighlightStyle(
        underline: true,
        underlineColor: 0xFF111111,
        wavy: true,
      ),
    ]);
    for (final style in styles()) {
      expect(style.background, isNull);
      expect(style.color, isNull);
    }
  });

  test('the worse one is on top where they cover the same text', () {
    controller.setDiagnostics(
      DiagnosticRanges(errors: [range(10, 14)], warnings: [range(10, 14)]),
    );
    expect(styles().last.underlineColor, 0xFF111111);
  });

  test('a change of colors is drawn at once, and none is no highlight', () {
    controller.setDiagnostics(DiagnosticRanges(errors: [range(10, 14)]));
    controller.diagnosticColors = const DiagnosticColors(error: 0xFF999999);
    expect(styles().single.underlineColor, 0xFF999999);
    controller.setDiagnostics(const DiagnosticRanges());
    expect(styles(), isEmpty);
  });
}
