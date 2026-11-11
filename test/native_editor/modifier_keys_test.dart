import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/native_editor/editor_controller.dart';
import 'package:ui/native_editor/editor_style.dart';
import 'package:ui/native_editor/editor_view.dart';
import 'package:ui/native_editor/modifier_keys.dart';

const _style = EditorStyle(
  textStyle: TextStyle(fontFamily: 'Roboto', fontSize: 14, height: 1.5),
);

Future<void> _pump(WidgetTester tester, EditorController controller) async {
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
            autofocus: true,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  tearDown(() => ModifierKeys.instance.forget());

  group('the modifier keys', () {
    testWidgets('are followed as they go down and up', (tester) async {
      final controller = EditorController(text: 'abc');
      await _pump(tester, controller);
      final keys = ModifierKeys.instance;
      expect(keys.isAltPressed, isFalse);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftRight);
      expect(keys.isAltPressed, isTrue);
      expect(keys.isShiftPressed, isTrue);
      expect(keys.isControlPressed, isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expect(keys.isAltPressed, isFalse);
      expect(keys.isShiftPressed, isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftRight);
      controller.dispose();
    });

    testWidgets('are not down after the window was left with one down', (
      tester,
    ) async {
      final controller = EditorController(text: 'one\ntwo\nthree');
      await _pump(tester, controller);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      // alt tab: the window loses the focus, and never sees the key go up
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(ModifierKeys.instance.isAltPressed, isFalse);

      // so a click is a plain click, and does not add a cursor
      final origin = tester.getTopLeft(find.byType(EditorView));
      await tester.tapAt(origin + const Offset(60, 12));
      await tester.pump();
      await tester.tapAt(origin + const Offset(60, 50));
      await tester.pump();
      expect(controller.selections.all, hasLength(1));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      controller.dispose();
    });

    testWidgets('alt held down still adds a cursor', (tester) async {
      final controller = EditorController(text: 'one\ntwo\nthree');
      await _pump(tester, controller);
      final origin = tester.getTopLeft(find.byType(EditorView));
      await tester.tapAt(origin + const Offset(60, 12));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(origin + const Offset(60, 50));
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expect(controller.selections.all, hasLength(2));
      controller.dispose();
    });
  });
}
