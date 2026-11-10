import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/native_editor/editor_controller.dart';
import 'package:ui/native_editor/editor_style.dart';
import 'package:ui/native_editor/editor_view.dart';
import 'package:ui/native_editor/render_editor.dart';

const _style = EditorStyle(
  textStyle: TextStyle(fontFamily: 'Roboto', fontSize: 14, height: 1.5),
);

Future<RenderEditor> _pump(
  WidgetTester tester,
  EditorController controller,
) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 500,
          height: 300,
          child: EditorView(
            controller: controller,
            style: _style,
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

Future<void> _key(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
  bool control = false,
}) async {
  if (control) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  }
  if (shift) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.sendKeyEvent(key);
  if (shift) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  }
  if (control) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }
}

void main() {
  group('keys', () {
    testWidgets('arrows move the cursor, and shift selects', (tester) async {
      final controller = EditorController(text: 'one two\nthree');
      await _pump(tester, controller);
      await _key(tester, LogicalKeyboardKey.arrowRight);
      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(controller.selections.first.head, 2);
      await _key(tester, LogicalKeyboardKey.arrowRight, shift: true);
      expect(
        (controller.selections.first.start, controller.selections.first.end),
        (2, 3),
      );
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(controller.selections.first.isEmpty, isTrue);
      expect(controller.selections.first.head, 8 + 3);
      await _key(tester, LogicalKeyboardKey.home);
      expect(controller.selections.first.head, 8);
      await _key(tester, LogicalKeyboardKey.end, control: true);
      expect(controller.selections.first.head, controller.buffer.length);
      await _finish(tester, controller);
    });

    testWidgets('the column is kept going over a short line', (tester) async {
      final controller = EditorController(text: 'abcdef\nab\nabcdef');
      await _pump(tester, controller);
      controller.selections.selectRanges([(5, 5)]);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(controller.selections.first.head, 9);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(controller.selections.first.head, 10 + 5);
      await _finish(tester, controller);
    });

    testWidgets('control moves and deletes by words', (tester) async {
      final controller = EditorController(text: 'hello big_world, again');
      await _pump(tester, controller);
      await _key(tester, LogicalKeyboardKey.arrowRight, control: true);
      expect(controller.selections.first.head, 5);
      await _key(tester, LogicalKeyboardKey.arrowRight, control: true);
      expect(controller.selections.first.head, 15);
      await _key(tester, LogicalKeyboardKey.arrowRight, control: true);
      expect(controller.selections.first.head, 16);
      await _key(tester, LogicalKeyboardKey.backspace, control: true);
      expect(controller.text, 'hello big_world again');
      await _finish(tester, controller);
    });

    testWidgets('enter keeps the indent, and tab and shift tab move it', (
      tester,
    ) async {
      final controller = EditorController(text: '  one');
      await _pump(tester, controller);
      controller.selections.selectRanges([(5, 5)]);
      await _key(tester, LogicalKeyboardKey.enter);
      expect(controller.text, '  one\n  ');
      await _key(tester, LogicalKeyboardKey.tab);
      expect(controller.text, '  one\n    ');
      await _key(tester, LogicalKeyboardKey.tab, shift: true);
      expect(controller.text, '  one\n');
      await _finish(tester, controller);
    });

    testWidgets('tab indents the lines that are selected', (tester) async {
      final controller = EditorController(text: 'a\nb\nc');
      await _pump(tester, controller);
      controller.selectAll();
      await _key(tester, LogicalKeyboardKey.tab);
      expect(controller.text, '    a\n    b\n    c');
      await _key(tester, LogicalKeyboardKey.tab, shift: true);
      expect(controller.text, 'a\nb\nc');
      await _finish(tester, controller);
    });

    testWidgets('select all, undo and redo', (tester) async {
      final controller = EditorController(text: 'text');
      await _pump(tester, controller);
      await _key(tester, LogicalKeyboardKey.keyA, control: true);
      expect(controller.selections.first.length, 4);
      await _key(tester, LogicalKeyboardKey.delete);
      expect(controller.text, '');
      await _key(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(controller.text, 'text');
      await _key(tester, LogicalKeyboardKey.keyZ, control: true, shift: true);
      expect(controller.text, '');
      await _finish(tester, controller);
    });

    testWidgets('copy, cut and paste use the clipboard', (tester) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          } else if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': clipboard};
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
      final controller = EditorController(text: 'one two');
      await _pump(tester, controller);
      controller.selections.selectRanges([(0, 3)]);
      await _key(tester, LogicalKeyboardKey.keyC, control: true);
      await tester.pump();
      expect(clipboard, 'one');
      await _key(tester, LogicalKeyboardKey.keyX, control: true);
      await tester.pump();
      expect(controller.text, ' two');
      controller.selections.selectRanges([(4, 4)]);
      await _key(tester, LogicalKeyboardKey.keyV, control: true);
      await tester.pump();
      expect(controller.text, ' twoone');
      await _finish(tester, controller);
    });

    testWidgets('typing goes in at every cursor', (tester) async {
      final controller = EditorController(text: 'a\nb\nc');
      await _pump(tester, controller);
      controller.selections.selectRanges([(1, 1), (3, 3), (5, 5)]);
      controller.replaceSelections('!');
      expect(controller.text, 'a!\nb!\nc!');
      expect(controller.selections.all.map((s) => s.head), [2, 5, 8]);
      await _finish(tester, controller);
    });
  });

  group('input method', () {
    testWidgets('typed text and compositions change the text', (tester) async {
      final controller = EditorController(text: 'ab');
      await _pump(tester, controller);
      expect(tester.testTextInput.isRegistered, isTrue);
      controller.selections.selectRanges([(1, 1)]);
      await tester.pump();

      final input = tester
          .state<EditorViewState>(find.byType(EditorView))
          .input;
      input.updateEditingValueWithDeltas([
        const TextEditingDeltaInsertion(
          oldText: 'ab',
          textInserted: 'X',
          insertionOffset: 1,
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange.empty,
        ),
      ]);
      await tester.pump();
      expect(controller.text, 'aXb');
      expect(controller.selections.first.head, 2);

      // a composition is text that is replaced as it is typed
      input.updateEditingValueWithDeltas([
        const TextEditingDeltaInsertion(
          oldText: 'aXb',
          textInserted: 'に',
          insertionOffset: 2,
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 2, end: 3),
        ),
      ]);
      await tester.pump();
      expect(controller.text, 'aXにb');
      input.updateEditingValueWithDeltas([
        const TextEditingDeltaReplacement(
          oldText: 'aXにb',
          replacementText: '日',
          replacedRange: TextRange(start: 2, end: 3),
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange.empty,
        ),
      ]);
      await tester.pump();
      expect(controller.text, 'aX日b');
      expect(controller.selections.first.head, 3);
      await _finish(tester, controller);
    });

    testWidgets('the input method is told of the line of the cursor', (
      tester,
    ) async {
      final controller = EditorController(text: 'first\nsecond');
      await _pump(tester, controller);
      controller.clickAt(8);
      await tester.pump();
      expect(tester.testTextInput.editingState!['text'], 'second');
      expect(tester.testTextInput.editingState!['selectionBase'], 2);
      await _finish(tester, controller);
    });
  });

  group('mouse', () {
    testWidgets('a click puts the cursor there, a double click a word', (
      tester,
    ) async {
      final controller = EditorController(text: 'alpha beta\ngamma');
      final render = await _pump(tester, controller);
      final origin = tester.getTopLeft(find.byType(EditorView));
      Offset at(int column, int row) =>
          origin +
          Offset(
            render.textLeft + render.charWidth * (column + 0.4),
            render.lineHeight * (row + 0.5),
          );

      await tester.tapAt(at(3, 0));
      await tester.pump(const Duration(seconds: 1));
      expect(controller.selections.first.head, 3);

      await tester.tapAt(at(7, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at(7, 0));
      await tester.pump(const Duration(seconds: 1));
      expect(
        (controller.selections.first.start, controller.selections.first.end),
        (6, 10),
      );
      await _finish(tester, controller);
    });

    testWidgets('dragging selects, and shift click extends', (tester) async {
      final controller = EditorController(text: 'alpha beta\ngamma');
      final render = await _pump(tester, controller);
      final origin = tester.getTopLeft(find.byType(EditorView));
      Offset at(int column, int row) =>
          origin +
          Offset(
            render.textLeft + render.charWidth * (column + 0.4),
            render.lineHeight * (row + 0.5),
          );

      final gesture = await tester.startGesture(at(2, 0));
      await gesture.moveTo(at(3, 1));
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      expect(
        (controller.selections.first.start, controller.selections.first.end),
        (2, 11 + 3),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tapAt(at(5, 1));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump(const Duration(seconds: 1));
      expect(
        (controller.selections.first.start, controller.selections.first.end),
        (2, 11 + 5),
      );
      await _finish(tester, controller);
    });
  });
}
