import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/editor_core/buffer.dart';
import 'package:ui/editor_core/patch.dart' show Bias;
import 'package:ui/lsp/lsp_client.dart';
import 'package:ui/native_editor/diagnostic_hover.dart';
import 'package:ui/native_editor/editor_controller.dart';
import 'package:ui/native_editor/editor_style.dart';
import 'package:ui/native_editor/editor_view.dart';
import 'package:ui/native_editor/render_editor.dart';
import 'package:ui/settings/editor_settings.dart';

const _style = EditorStyle(
  textStyle: TextStyle(fontFamily: 'Roboto', fontSize: 14, height: 1.5),
);

DiagnosticDetail _detail(
  EditorController controller,
  int start,
  int end, {
  DetailSeverity level = DetailSeverity.warning,
  String message = 'Variable x is never used',
  String? source = 'Luau',
  String? code = '7',
  String? codeHref,
}) => DiagnosticDetail(
  range: AnchorRange(
    controller.buffer.anchorAt(start, Bias.right),
    controller.buffer.anchorAt(end, Bias.left),
  ),
  level: level,
  message: message,
  source: source,
  code: code,
  codeHref: codeHref,
);

void main() {
  group('where the popover goes', () {
    const area = Size(400, 300);
    const size = Size(100, 40);

    test('is directly above the row when it fits there', () {
      expect(
        placePopover(const Rect.fromLTWH(50, 100, 8, 20), size, area),
        const Offset(50, 60),
      );
    });

    test('is directly below the row when there is no room above', () {
      expect(
        placePopover(const Rect.fromLTWH(50, 10, 8, 20), size, area),
        const Offset(50, 30),
      );
    });

    test('is moved to the left to keep clear of the right edge', () {
      final at = placePopover(const Rect.fromLTWH(380, 100, 8, 20), size, area);
      expect(at.dx + size.width, area.width - popoverRightMargin);
      expect(at.dy, 60);
    });

    test('is kept inside the area when it fits neither above nor below', () {
      final at = placePopover(
        const Rect.fromLTWH(50, 130, 8, 20),
        const Size(100, 260),
        area,
      );
      expect(at.dy, inInclusiveRange(0, 300 - 260));
    });

    test(
      'has a text of 120 columns and 16 rows at most, and half the area',
      () {
        expect(
          popoverContentLimit(
            area: const Size(2000, 1000),
            charWidth: 8,
            lineHeight: 20,
          ),
          const Size(960, 320),
        );
        expect(
          popoverContentLimit(
            area: const Size(600, 300),
            charWidth: 8,
            lineHeight: 20,
          ),
          const Size(300, 150),
        );
        expect(
          popoverContentLimit(
            area: const Size(100, 40),
            charWidth: 8,
            lineHeight: 20,
          ),
          const Size(160, 80),
        );
      },
    );
  });

  group('the text', () {
    final controller = EditorController(text: 'local x = 1');
    const link = TextStyle(decoration: TextDecoration.underline);

    test('is the message, and in parentheses the source and the code', () {
      final span = diagnosticText(
        _detail(controller, 6, 7),
        const TextStyle(),
        link,
      );
      expect(span.toPlainText(), 'Variable x is never used (Luau 7)');
    });

    test('leaves out what the server did not say', () {
      expect(
        diagnosticText(
          _detail(controller, 6, 7, code: null),
          const TextStyle(),
          link,
        ).toPlainText(),
        'Variable x is never used (Luau)',
      );
      expect(
        diagnosticText(
          _detail(controller, 6, 7, source: null),
          const TextStyle(),
          link,
        ).toPlainText(),
        'Variable x is never used (7)',
      );
      expect(
        diagnosticText(
          _detail(controller, 6, 7, source: null, code: null),
          const TextStyle(),
          link,
        ).toPlainText(),
        'Variable x is never used',
      );
    });

    test('has the code as a link only where the server says where it is', () {
      final recognizer = TapGestureRecognizer();
      addTearDown(recognizer.dispose);
      TextSpan code(InlineSpan span) =>
          ((span as TextSpan).children!.whereType<TextSpan>()).firstWhere(
            (s) => s.text == '7',
          );
      final linked = code(
        diagnosticText(
          _detail(controller, 6, 7, codeHref: 'https://example.com/7'),
          const TextStyle(),
          link,
          onLink: recognizer,
        ),
      );
      expect(linked.recognizer, recognizer);
      expect(linked.style, link);
      final plain = code(
        diagnosticText(
          _detail(controller, 6, 7),
          const TextStyle(),
          link,
          onLink: recognizer,
        ),
      );
      expect(plain.recognizer, isNull);
      expect(plain.style, isNull);
    });
  });

  group('the diagnostic at a place', () {
    late EditorController controller;

    setUp(() => controller = EditorController(text: 'local x = nope()'));
    tearDown(() => controller.dispose());

    test('is the one that has the place between its ends', () {
      final x = _detail(controller, 6, 7, message: 'x');
      controller.setDiagnostics(DiagnosticRanges(details: [x]));
      expect(controller.diagnosticAt(6), x);
      expect(controller.diagnosticAt(7), x);
      expect(controller.diagnosticAt(5), isNull);
      expect(controller.diagnosticAt(8), isNull);
    });

    test('is the one with the shortest range where they cover the same', () {
      final wide = _detail(controller, 0, 16, message: 'wide');
      final narrow = _detail(controller, 10, 14, message: 'narrow');
      controller.setDiagnostics(DiagnosticRanges(details: [wide, narrow]));
      expect(controller.diagnosticAt(11)!.message, 'narrow');
      expect(controller.diagnosticAt(2)!.message, 'wide');
    });

    test('moves with the text', () {
      final nope = _detail(controller, 10, 14, message: 'nope');
      controller.setDiagnostics(DiagnosticRanges(details: [nope]));
      controller.buffer.edit([const Replacement.insert(0, '-- ')]);
      expect(controller.diagnosticAt(13)!.message, 'nope');
      expect(controller.diagnosticAt(11), isNull);
    });
  });

  group('what the server sends', () {
    test('has the page that explains the code', () {
      final diagnostic = LspDiagnostic.fromJson({
        'range': {
          'start': {'line': 0, 'character': 0},
          'end': {'line': 0, 'character': 1},
        },
        'severity': 1,
        'message': 'TypeError: nope',
        'source': 'Luau',
        'code': 1002,
        'codeDescription': {'href': 'https://luau.org/types'},
      })!;
      expect(diagnostic.codeHref, 'https://luau.org/types');
      expect(diagnostic.code, '1002');
      expect(diagnostic.source, 'Luau');
    });

    test('has none without a code description', () {
      final diagnostic = LspDiagnostic.fromJson({
        'range': {
          'start': {'line': 0, 'character': 0},
          'end': {'line': 0, 'character': 1},
        },
        'message': 'x',
      })!;
      expect(diagnostic.codeHref, isNull);
    });
  });

  group('the settings', () {
    test('are on, and wait 300 ms and hide after 300 ms, as they stick', () {
      const hover = HoverSettings();
      expect(hover.enabled, isTrue);
      expect(hover.sticky, isTrue);
      expect(hover.delay, const Duration(milliseconds: 300));
      expect(hover.hidingDelay, const Duration(milliseconds: 300));
      expect(EditorPrefs.fromJson(null).hover, hover);
    });

    test('are read, kept within 0 and 2 s, and saved', () {
      final prefs = EditorPrefs.fromJson({
        'hoverPopoverEnabled': false,
        'hoverPopoverDelay': 120,
        'hoverPopoverSticky': false,
        'hoverPopoverHidingDelay': 99999,
      });
      expect(prefs.hover.enabled, isFalse);
      expect(prefs.hover.sticky, isFalse);
      expect(prefs.hover.delay, const Duration(milliseconds: 120));
      expect(prefs.hover.hidingDelay, const Duration(seconds: 2));
      final json = prefs.toJson();
      expect(json['hoverPopoverEnabled'], false);
      expect(json['hoverPopoverDelay'], 120);
      expect(json['hoverPopoverSticky'], false);
      expect(json['hoverPopoverHidingDelay'], 2000);
    });

    test('are kept when another setting changes', () {
      const hover = HoverSettings(delay: Duration(milliseconds: 50));
      final prefs = const EditorPrefs().copyWith(hover: hover);
      expect(prefs.copyWith(tabSize: 2).hover, hover);
      expect(prefs.withFontSize(12).hover, hover);
    });
  });

  group('the view', () {
    late EditorController controller;

    setUp(() => controller = EditorController(text: 'local x = 1\nab'));
    tearDown(() => controller.dispose());

    Future<(EditorViewState, RenderEditor)> pump(
      WidgetTester tester, {
      HoverSettings hover = const HoverSettings(),
      List<DiagnosticDetail>? details,
    }) async {
      controller.setDiagnostics(
        DiagnosticRanges(details: details ?? [_detail(controller, 6, 7)]),
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
                hover: hover,
                autofocus: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return (
        tester.state<EditorViewState>(find.byType(EditorView)),
        tester.allRenderObjects.whereType<RenderEditor>().first,
      );
    }

    /// the middle of the character at [offset], on the screen
    Offset at(RenderEditor render, int offset) {
      final caret = render.caretRectForOffset(offset);
      return render.localToGlobal(
        Offset(caret.left + render.charWidth / 2, caret.center.dy),
      );
    }

    Future<TestGesture> mouse(WidgetTester tester) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(450, 250));
      addTearDown(gesture.removePointer);
      return gesture;
    }

    const rests = Duration(milliseconds: 350);

    testWidgets('shows what the server said once the pointer has rested', (
      tester,
    ) async {
      final (view, render) = await pump(tester);
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(const Duration(milliseconds: 200));
      expect(view.popover, isNull);
      await tester.pump(rests);
      expect(view.popover, isNotNull);
      expect(find.textContaining('Variable x is never used'), findsOneWidget);
      expect(
        find.textContaining('(Luau 7)', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('waits again when the pointer moves before it is shown', (
      tester,
    ) async {
      final (view, render) = await pump(tester);
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveBy(const Offset(1, 0));
      await tester.pump(const Duration(milliseconds: 200));
      expect(view.popover, isNull);
      await tester.pump(const Duration(milliseconds: 150));
      expect(view.popover, isNotNull);
    });

    testWidgets('is not shown where the server said nothing', (tester) async {
      final (view, render) = await pump(tester);
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 1));
      await tester.pump(rests);
      expect(view.popover, isNull);
    });

    testWidgets('is not shown away from the text', (tester) async {
      final (view, render) = await pump(tester);
      final gesture = await mouse(tester);
      // past the end of the row, and below the last row
      await gesture.moveTo(render.localToGlobal(const Offset(400, 10)));
      await tester.pump(rests);
      expect(view.popover, isNull);
      await gesture.moveTo(render.localToGlobal(const Offset(100, 200)));
      await tester.pump(rests);
      expect(view.popover, isNull);
    });

    testWidgets('is not shown when the setting is off', (tester) async {
      final (view, render) = await pump(
        tester,
        hover: const HoverSettings(enabled: false),
      );
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(rests);
      expect(view.popover, isNull);
    });

    testWidgets('waits as long as the setting says', (tester) async {
      final (view, render) = await pump(
        tester,
        hover: const HoverSettings(delay: Duration(milliseconds: 1000)),
      );
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(const Duration(milliseconds: 900));
      expect(view.popover, isNull);
      await tester.pump(const Duration(milliseconds: 150));
      expect(view.popover, isNotNull);
    });

    testWidgets('stays a moment after the pointer goes, and then goes', (
      tester,
    ) async {
      final (view, render) = await pump(tester);
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(rests);
      expect(view.popover, isNotNull);
      await gesture.moveTo(render.localToGlobal(const Offset(450, 280)));
      await tester.pump(const Duration(milliseconds: 200));
      expect(view.popover, isNotNull);
      await tester.pump(const Duration(milliseconds: 150));
      expect(view.popover, isNull);
    });

    testWidgets('goes at once when it does not stick', (tester) async {
      final (view, render) = await pump(
        tester,
        hover: const HoverSettings(sticky: false),
      );
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(rests);
      expect(view.popover, isNotNull);
      await gesture.moveTo(render.localToGlobal(const Offset(450, 280)));
      await tester.pump();
      expect(view.popover, isNull);
    });

    testWidgets('stays while the pointer is on it', (tester) async {
      final (view, render) = await pump(tester);
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(rests);
      await gesture.moveTo(render.localToGlobal(const Offset(450, 280)));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(tester.getCenter(find.byType(DiagnosticPopover)));
      await tester.pump(const Duration(milliseconds: 600));
      expect(view.popover, isNotNull);
    });

    testWidgets('is not shown for another place while one is shown', (
      tester,
    ) async {
      final (view, render) = await pump(
        tester,
        details: [
          _detail(controller, 6, 7, message: 'first'),
          _detail(controller, 10, 11, message: 'second'),
        ],
      );
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(rests);
      expect(view.popover!.message, 'first');
      await gesture.moveTo(at(render, 10));
      await tester.pump(rests);
      expect(view.popover!.message, 'first');
    });

    testWidgets('goes with escape', (tester) async {
      final (view, render) = await pump(tester);
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(rests);
      expect(view.popover, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(view.popover, isNull);
    });

    testWidgets('goes when the selection changes', (tester) async {
      final (view, render) = await pump(tester);
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(rests);
      expect(view.popover, isNotNull);
      controller.clickAt(2);
      await tester.pump();
      expect(view.popover, isNull);
    });

    testWidgets('goes when the text scrolls', (tester) async {
      controller.buffer.edit([Replacement.insert(14, '\n' * 60)]);
      final (view, render) = await pump(tester);
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(rests);
      expect(view.popover, isNotNull);
      controller.setScroll(y: 200);
      await tester.pump();
      await tester.pump();
      expect(view.popover, isNull);
      // the scrollbars that the scroll showed go a second later
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('copies the message, and says that it did', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final (view, render) = await pump(tester);
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(rests);
      expect(find.byIcon(Icons.content_copy), findsOneWidget);
      await tester.tap(find.byIcon(Icons.content_copy));
      await tester.pump();
      expect(copied, ['Variable x is never used']);
      expect(find.byIcon(Icons.check), findsOneWidget);
      // the editor did not take the click
      expect(controller.selections.newest.head, 0);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byIcon(Icons.content_copy), findsOneWidget);
      expect(view.popover, isNotNull);
    });
  });
}
