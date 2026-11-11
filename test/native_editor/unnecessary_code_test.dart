import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/editor_core/buffer.dart';
import 'package:ui/editor_core/highlight.dart';
import 'package:ui/editor_core/patch.dart' show Bias;
import 'package:ui/lsp/lsp_client.dart';
import 'package:ui/native_editor/editor_controller.dart';
import 'package:ui/native_editor/editor_style.dart';
import 'package:ui/settings/editor_settings.dart';

const _style = EditorStyle(
  textStyle: TextStyle(color: Color(0xFFFFFFFF), fontSize: 14),
);

Map<String, Object?> _diagnostic(Object? tags) => {
  'range': {
    'start': {'line': 0, 'character': 6},
    'end': {'line': 0, 'character': 7},
  },
  'severity': 2,
  'message': 'LocalUnused: Variable x is never used',
  'tags': ?tags,
};

void main() {
  group('the tag of a diagnostic', () {
    test('unnecessary is the number 1 of the protocol', () {
      expect(LspDiagnostic.fromJson(_diagnostic([1]))!.unnecessary, isTrue);
      expect(LspDiagnostic.fromJson(_diagnostic([2, 1]))!.unnecessary, isTrue);
    });

    test('deprecated, no tags and a tag that is not a list are not it', () {
      expect(LspDiagnostic.fromJson(_diagnostic([2]))!.unnecessary, isFalse);
      expect(LspDiagnostic.fromJson(_diagnostic(null))!.unnecessary, isFalse);
      expect(LspDiagnostic.fromJson(_diagnostic('1'))!.unnecessary, isFalse);
    });
  });

  group('the fade of a style', () {
    test('takes the share of the opacity of the color of the text', () {
      final faded = _style.apply(const HighlightStyle(fadeOut: 0.3));
      expect(faded.color!.a, closeTo(0.7, 1e-6));
      expect(faded.color!.toARGB32() & 0xFFFFFF, 0xFFFFFF);
    });

    test('keeps the color of the syntax, which it fades', () {
      final faded = _style.apply(
        const HighlightStyle(color: 0xFFFF0000, fadeOut: 0.5),
      );
      expect(faded.color!.toARGB32(), 0x80FF0000);
    });

    test('is no change without a fade, and none at 0', () {
      expect(_style.apply(const HighlightStyle(bold: true)).color!.a, 1.0);
      expect(_style.apply(const HighlightStyle(fadeOut: 0)).color!.a, 1.0);
    });

    test('two that meet add up within 0 and 1', () {
      const under = HighlightStyle(fadeOut: 0.3);
      expect(
        under.merge(const HighlightStyle(fadeOut: 0.5)).fadeOut,
        closeTo(0.45, 1e-9),
      );
      expect(under.merge(const HighlightStyle(fadeOut: 3)).fadeOut, 1.0);
      expect(under.merge(const HighlightStyle()).fadeOut, 0.3);
      expect(const HighlightStyle().merge(under).fadeOut, 0.3);
    });
  });

  group('the code that is not needed', () {
    late EditorController controller;

    AnchorRange range(int start, int end) => AnchorRange(
      controller.buffer.anchorAt(start, Bias.right),
      controller.buffer.anchorAt(end, Bias.left),
    );

    setUp(() => controller = EditorController(text: 'local x = 1'));
    tearDown(() => controller.dispose());

    List<HighlightStyle> fades() => [
      for (final highlight in controller.highlights.textHighlights.values)
        if (highlight.style.fadeOut != null) highlight.style,
    ];

    test('is faded by 0.3 unless set otherwise', () {
      controller.setDiagnostics(
        DiagnosticRanges(warnings: [range(6, 7)], unnecessary: [range(6, 7)]),
      );
      expect(fades().single.fadeOut, 0.3);
    });

    test('keeps its underline, as the diagnostic of how bad it is', () {
      controller.setDiagnostics(
        DiagnosticRanges(warnings: [range(6, 7)], unnecessary: [range(6, 7)]),
      );
      final underlined = [
        for (final highlight in controller.highlights.textHighlights.values)
          if (highlight.style.underline == true) highlight.style,
      ];
      expect(underlined, hasLength(1));
      expect(underlined.single.wavy, isTrue);
    });

    test('is faded by the setting as soon as it changes, to 0.9 at most', () {
      controller.setDiagnostics(DiagnosticRanges(unnecessary: [range(6, 7)]));
      controller.unnecessaryCodeFade = 0.6;
      expect(fades().single.fadeOut, 0.6);
      controller.unnecessaryCodeFade = 5;
      expect(controller.unnecessaryCodeFade, 0.9);
      expect(fades().single.fadeOut, 0.9);
      controller.unnecessaryCodeFade = -1;
      expect(controller.unnecessaryCodeFade, 0.0);
    });

    test('is not faded when there is none', () {
      controller.setDiagnostics(DiagnosticRanges(warnings: [range(6, 7)]));
      expect(fades(), isEmpty);
      controller.setDiagnostics(DiagnosticRanges(unnecessary: [range(6, 7)]));
      controller.setDiagnostics(const DiagnosticRanges());
      expect(fades(), isEmpty);
    });

    test('is faded in the text that is drawn', () {
      controller.setDiagnostics(DiagnosticRanges(unnecessary: [range(6, 7)]));
      final faded = [
        for (final chunk in controller.display.snapshot.highlightedRowChunks(
          0,
          controller.highlights,
        ))
          if (chunk.style?.fadeOut != null) chunk.text,
      ];
      expect(faded, ['x']);
    });
  });

  group('the setting', () {
    test('is 0.3 when the file does not say', () {
      expect(EditorPrefs.fromJson(null).unnecessaryCodeFade, 0.3);
      expect(EditorPrefs.fromJson({}).unnecessaryCodeFade, 0.3);
      expect(
        EditorPrefs.fromJson({'unnecessaryCodeFade': 'a lot'})
            .unnecessaryCodeFade,
        0.3,
      );
    });

    test('is read and saved, within 0 and 0.9', () {
      expect(
        EditorPrefs.fromJson({'unnecessaryCodeFade': 0.5}).unnecessaryCodeFade,
        0.5,
      );
      expect(
        EditorPrefs.fromJson({'unnecessaryCodeFade': 4}).unnecessaryCodeFade,
        0.9,
      );
      expect(
        EditorPrefs.fromJson({'unnecessaryCodeFade': -2}).unnecessaryCodeFade,
        0.0,
      );
      expect(
        const EditorPrefs(unnecessaryCodeFade: 0.2)
            .toJson()['unnecessaryCodeFade'],
        0.2,
      );
    });

    test('is kept when another setting changes', () {
      const prefs = EditorPrefs(unnecessaryCodeFade: 0.2);
      expect(prefs.copyWith(tabSize: 2).unnecessaryCodeFade, 0.2);
      expect(prefs.withFontSize(12).unnecessaryCodeFade, 0.2);
    });
  });
}
