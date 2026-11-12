import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/editor_core/buffer.dart';
import 'package:ui/editor_core/patch.dart' show Bias;
import 'package:ui/native_editor/diagnostic_hover.dart';
import 'package:ui/native_editor/editor_controller.dart';
import 'package:ui/native_editor/editor_style.dart';
import 'package:ui/native_editor/editor_view.dart';
import 'package:ui/native_editor/hover_markdown.dart';
import 'package:ui/native_editor/render_editor.dart';

const _style = EditorStyle(
  textStyle: TextStyle(fontFamily: 'Roboto', fontSize: 14, height: 1.5),
);

void main() {
  group('what the server says of a symbol', () {
    late EditorController controller;
    late List<int> asked;

    /// the words of the text, as the symbols that the server knows
    HoverInfo? symbolAt(int offset) {
      final text = controller.text;
      for (final match in RegExp(r'[a-z]+').allMatches(text)) {
        if (offset >= match.start && offset <= match.end) {
          return HoverInfo(
            range: AnchorRange(
              controller.buffer.anchorAt(match.start, Bias.right),
              controller.buffer.anchorAt(match.end, Bias.left),
            ),
            markdown: '```luau\nlocal ${match.group(0)}: number\n```\n\nIt.',
          );
        }
      }
      return null;
    }

    setUp(() {
      controller = EditorController(text: 'local x = 1\nab = x');
      asked = [];
      controller.hoverProvider = (offset) async {
        asked.add(offset);
        return symbolAt(offset);
      };
    });
    tearDown(() => controller.dispose());

    Future<(EditorViewState, RenderEditor)> pump(
      WidgetTester tester, {
      HoverSettings hover = const HoverSettings(),
    }) async {
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

    testWidgets('is shown once the pointer has rested, and lights it', (
      tester,
    ) async {
      final (view, render) = await pump(tester);
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(const Duration(milliseconds: 200));
      expect(view.info, isNull);
      await tester.pump(rests);
      expect(view.info, isNotNull);
      expect(find.byType(InfoPopover), findsOneWidget);
      expect(
        find.textContaining('local x: number', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('local x: number'), findsOneWidget);
      // the symbol is lit, and is the range that the server gave
      final range = controller.hoverRange!;
      final snapshot = controller.buffer.snapshot;
      expect(snapshot.offsetForAnchor(range.start), 6);
      expect(snapshot.offsetForAnchor(range.end), 7);
    });

    testWidgets('is asked for the character that the pointer is on', (
      tester,
    ) async {
      final (_, render) = await pump(tester);
      final caret = render.caretRectForOffset(6);
      final width = render.charWidth;
      Offset inRow(double left, double top) => Offset(left, top);
      final y = caret.center.dy;
      // the left part of the character, and then its right part
      expect(render.hoverOffsetAt(inRow(caret.left + width * 0.1, y)), 6);
      expect(render.hoverOffsetAt(inRow(caret.left + width * 0.9, y)), 6);
      // the next one
      expect(render.hoverOffsetAt(inRow(caret.left + width * 1.1, y)), 7);
      // and the first of a row is not taken for the end of the one before it
      final second = render.caretRectForOffset(12);
      expect(
        render.hoverOffsetAt(
          inRow(second.left + width * 0.1, second.center.dy),
        ),
        12,
      );
      expect(
        render.hoverOffsetAt(
          inRow(second.left + width * 0.9, second.center.dy),
        ),
        12,
      );
    });

    testWidgets('is asked for halfway through the wait', (tester) async {
      final (_, render) = await pump(tester);
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(const Duration(milliseconds: 140));
      expect(asked, isEmpty);
      await tester.pump(const Duration(milliseconds: 20));
      expect(asked, [6]);
      await tester.pump(rests);
    });

    testWidgets('goes, and the light with it, when the pointer leaves', (
      tester,
    ) async {
      final (view, render) = await pump(tester);
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(rests);
      expect(view.info, isNotNull);
      await gesture.moveTo(const Offset(450, 250));
      await tester.pump(rests);
      expect(view.info, isNull);
      expect(controller.hoverRange, isNull);
      expect(find.byType(InfoPopover), findsNothing);
    });

    testWidgets('goes for another symbol, and is shown for it', (tester) async {
      final (view, render) = await pump(tester);
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(rests);
      expect(find.text('local x: number'), findsOneWidget);
      // the other row
      await gesture.moveTo(at(render, 12));
      await tester.pump(const Duration(milliseconds: 10));
      expect(view.info, isNull, reason: 'it goes at once');
      expect(controller.hoverRange, isNull);
      await tester.pump(rests);
      expect(find.text('local ab: number'), findsOneWidget);
      final snapshot = controller.buffer.snapshot;
      expect(snapshot.offsetForAnchor(controller.hoverRange!.start), 12);
    });

    testWidgets('stays while the pointer moves in the symbol', (tester) async {
      final provider = controller.hoverProvider;
      controller.dispose();
      controller = EditorController(text: 'local variable = 1')
        ..hoverProvider = provider;
      final (view, render) = await pump(tester);
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 7));
      await tester.pump(rests);
      final shown = view.info;
      expect(shown, isNotNull);
      await gesture.moveTo(at(render, 10));
      await tester.pump(rests);
      expect(view.info, same(shown));
      expect(asked, [7]);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('is not shown where the server says nothing', (tester) async {
      final (view, render) = await pump(tester);
      final gesture = await mouse(tester);
      // the equals sign, which has no symbol
      await gesture.moveTo(at(render, 8));
      await tester.pump(rests);
      expect(view.info, isNull);
      expect(controller.hoverRange, isNull);
      expect(find.byType(InfoPopover), findsNothing);
    });

    testWidgets('is not shown when the server cannot answer', (tester) async {
      controller.hoverProvider = (_) async => throw StateError('gone');
      final (view, render) = await pump(tester);
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(rests);
      expect(view.info, isNull);
    });

    testWidgets('is not shown when there is no server', (tester) async {
      controller.hoverProvider = null;
      final (view, render) = await pump(tester);
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(rests);
      expect(view.info, isNull);
    });

    testWidgets('is not shown for a pointer that has moved on', (tester) async {
      final answer = Completer<HoverInfo?>();
      controller.hoverProvider = (offset) {
        asked.add(offset);
        return answer.future;
      };
      final (view, render) = await pump(tester);
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(const Duration(milliseconds: 160));
      expect(asked, [6]);
      // away from the text, while the answer is not there
      await gesture.moveTo(const Offset(450, 250));
      await tester.pump(const Duration(milliseconds: 20));
      answer.complete(symbolAt(6));
      await tester.pump(rests);
      expect(view.info, isNull);
      expect(controller.hoverRange, isNull);
    });

    testWidgets('is not shown when the setting is off', (tester) async {
      final (view, render) = await pump(
        tester,
        hover: const HoverSettings(enabled: false),
      );
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(rests);
      expect(view.info, isNull);
      expect(asked, isEmpty);
    });

    testWidgets('goes with escape', (tester) async {
      final (view, render) = await pump(tester);
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(rests);
      expect(view.info, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(view.info, isNull);
      expect(controller.hoverRange, isNull);
    });

    testWidgets('stays while the pointer is on it', (tester) async {
      final (view, render) = await pump(tester);
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(rests);
      await gesture.moveTo(tester.getCenter(find.byType(InfoPopover)));
      await tester.pump(const Duration(seconds: 2));
      expect(view.info, isNotNull);
    });

    testWidgets('is shown with what was found wrong, which is nearer', (
      tester,
    ) async {
      controller.setDiagnostics(
        DiagnosticRanges(
          details: [
            DiagnosticDetail(
              range: AnchorRange(
                controller.buffer.anchorAt(6, Bias.right),
                controller.buffer.anchorAt(7, Bias.left),
              ),
              level: DetailSeverity.warning,
              message: 'Variable x is never used',
            ),
          ],
        ),
      );
      final (view, render) = await pump(tester);
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(rests);
      expect(view.popover, isNotNull);
      expect(view.info, isNotNull);
      final wrong = tester.getRect(find.byType(DiagnosticPopover));
      final symbol = tester.getRect(find.byType(InfoPopover));
      // there is no room above the first row, so both are below it, and what
      // was found wrong is the nearer, with the gap between them
      expect(wrong.top, lessThan(symbol.top));
      expect(symbol.top - wrong.bottom, closeTo(popoverGap, 0.01));
    });

    testWidgets('is shown alone where nothing is wrong', (tester) async {
      final (view, render) = await pump(tester);
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(rests);
      expect(view.popover, isNull);
      expect(find.byType(DiagnosticPopover), findsNothing);
      expect(find.byType(InfoPopover), findsOneWidget);
    });

    testWidgets('is lit in the color that is set for it', (tester) async {
      controller.hoverBackground = 0xFF123456;
      final (_, render) = await pump(tester);
      final gesture = await mouse(tester);
      await gesture.moveTo(at(render, 6));
      await tester.pump(rests);
      final highlight = controller.highlights.textHighlights.values
          .expand((h) => [h])
          .where((h) => h.style.background == 0xFF123456);
      expect(highlight, hasLength(1));
    });
  });
}
