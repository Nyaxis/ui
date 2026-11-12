import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/native_editor/cursor_blink.dart';
import 'package:ui/native_editor/editor_controller.dart';
import 'package:ui/native_editor/editor_style.dart';
import 'package:ui/native_editor/editor_view.dart';

void main() {
  group('the blinking', () {
    late List<String> log;
    late CursorBlink blink;

    setUp(() {
      log = [];
      blink = CursorBlink(
        show: () => log.add('show'),
        hide: () => log.add('hide'),
      );
    });

    /// a test that lets go of the blinking when it is done, as a timer that is
    /// left is a failure of the test, and the tear down is too late for it
    void blinking(String name, Future<void> Function(WidgetTester) body) =>
        testWidgets(name, (tester) async {
          await body(tester);
          blink.dispose();
        });

    blinking('shows the cursor at once, and then goes off and on', (
      tester,
    ) async {
      blink.enable();
      expect(log, ['show']);
      expect(blink.visible, isTrue);
      await tester.pump(const Duration(milliseconds: 499));
      expect(log, ['show']);
      await tester.pump(const Duration(milliseconds: 1));
      expect(log, ['show', 'hide']);
      await tester.pump(const Duration(milliseconds: 500));
      expect(log, ['show', 'hide', 'show']);
    });

    blinking('shows a cursor that is off at once, where something is done', (
      tester,
    ) async {
      blink.enable();
      await tester.pump(const Duration(milliseconds: 500));
      expect(blink.visible, isFalse);
      log.clear();
      blink.pause();
      expect(blink.visible, isTrue);
      expect(log, ['show']);
    });

    blinking('keeps it shown for the interval, and then goes on', (
      tester,
    ) async {
      blink.enable();
      await tester.pump(const Duration(milliseconds: 500));
      log.clear();
      blink.pause();
      await tester.pump(const Duration(milliseconds: 499));
      expect(blink.visible, isTrue);
      expect(log, ['show']);
      await tester.pump(const Duration(milliseconds: 1));
      // it goes off after the interval, and on again after another
      expect(log, ['show', 'hide']);
      await tester.pump(const Duration(milliseconds: 500));
      expect(log, ['show', 'hide', 'show']);
    });

    blinking('does not go off while the user goes on doing something', (
      tester,
    ) async {
      blink.enable();
      log.clear();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 400));
        blink.pause();
      }
      expect(log, isEmpty);
      expect(blink.visible, isTrue);
    });

    blinking('a cursor that is shown is not shown again', (tester) async {
      blink.enable();
      log.clear();
      blink.pause();
      blink.pause();
      expect(log, isEmpty);
    });

    blinking('stops when it is disabled, and is not started by what is done', (
      tester,
    ) async {
      blink.enable();
      blink.disable();
      log.clear();
      await tester.pump(const Duration(seconds: 3));
      expect(log, isEmpty);
      blink.pause();
      await tester.pump(const Duration(seconds: 3));
      // shown once, as the cursor was not, and then it stays as it is
      expect(log, ['show']);
      expect(blink.enabled, isFalse);
    });

    blinking('can be enabled again after it was disabled', (tester) async {
      blink.enable();
      blink.disable();
      log.clear();
      blink.enable();
      expect(log, ['show']);
      await tester.pump(const Duration(milliseconds: 500));
      expect(log, ['show', 'hide']);
    });
  });

  group('the editor', () {
    late EditorController controller;

    setUp(() => controller = EditorController(text: 'local x = 1\nab'));
    tearDown(() => controller.dispose());

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 500,
              height: 300,
              child: EditorView(
                controller: controller,
                style: const EditorStyle(
                  textStyle: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                autofocus: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('blinks while it is focused', (tester) async {
      await pump(tester);
      expect(controller.hasFocus, isTrue);
      expect(controller.cursorVisible, isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.cursorVisible, isFalse);
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.cursorVisible, isTrue);
    });

    testWidgets('shows the cursor at once for a click while it is off', (
      tester,
    ) async {
      await pump(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.cursorVisible, isFalse);
      // a click at the same place as the cursor, which changes no selection
      await tester.tapAt(const Offset(60, 10));
      await tester.pump();
      final first = controller.cursorVisible;
      expect(first, isTrue);
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.cursorVisible, isTrue);
      // and it goes off a half second after the click, as in a blink
      await tester.pump(const Duration(milliseconds: 150));
      expect(controller.cursorVisible, isFalse);
      // a second click, at the same place, while it is off
      await tester.tapAt(const Offset(60, 10));
      await tester.pump();
      expect(controller.cursorVisible, isTrue);
      // let the timers go
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('shows the cursor at once for typing while it is off', (
      tester,
    ) async {
      await pump(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.cursorVisible, isFalse);
      controller.replaceSelections('a');
      await tester.pump();
      expect(controller.cursorVisible, isTrue);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('does not blink when it is not focused', (tester) async {
      await pump(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(controller.hasFocus, isFalse);
      var changes = 0;
      controller.addListener(() => changes++);
      await tester.pump(const Duration(seconds: 3));
      expect(changes, 0);
    });
  });
}
