import 'package:flutter/gestures.dart';
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

Future<void> _pump(
  WidgetTester tester,
  EditorController controller, {
  required bool zoom,
  required List<int> steps,
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
            mouseWheelZoom: zoom,
            onZoom: steps.add,
            autofocus: true,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _finish(WidgetTester tester, EditorController controller) async {
  for (var i = 0; i < 200 && controller.display.isRewrapping; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  await tester.pumpWidget(const SizedBox());
  controller.dispose();
}

Future<void> _wheel(WidgetTester tester, double dy) async {
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  final at = tester.getCenter(find.byType(EditorView));
  await tester.sendEventToBinding(pointer.hover(at));
  await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
}

String get _long => List.generate(200, (i) => 'line $i').join('\n');

void main() {
  tearDown(() => ModifierKeys.instance.forget());

  group('zooming with the wheel', () {
    testWidgets('control and the wheel up is one step in, and down one out', (
      tester,
    ) async {
      final controller = EditorController(text: _long);
      final steps = <int>[];
      await _pump(tester, controller, zoom: true, steps: steps);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await _wheel(tester, -100);
      await _wheel(tester, -100);
      await _wheel(tester, 100);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(steps, [1, 1, -1]);
      // it did not scroll
      expect(controller.scrollY, 0);
      await _finish(tester, controller);
    });

    testWidgets('without control it scrolls, and does not zoom', (
      tester,
    ) async {
      final controller = EditorController(text: _long);
      final steps = <int>[];
      await _pump(tester, controller, zoom: true, steps: steps);
      await _wheel(tester, 100);
      expect(steps, isEmpty);
      expect(controller.scrollY, 100);
      await _finish(tester, controller);
    });

    testWidgets('when it is off, control and the wheel only scroll', (
      tester,
    ) async {
      final controller = EditorController(text: _long);
      final steps = <int>[];
      await _pump(tester, controller, zoom: false, steps: steps);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await _wheel(tester, 100);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(steps, isEmpty);
      expect(controller.scrollY, 100);
      await _finish(tester, controller);
    });
  });
}
