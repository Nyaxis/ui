import 'package:flutter_test/flutter_test.dart';

import 'package:ui/native_editor/cursor_summary.dart';
import 'package:ui/native_editor/editor_controller.dart';

String _summary(EditorController controller) => cursorSummary(
  controller.buffer.text,
  controller.selections.all,
  controller.selections.newest,
);

void main() {
  group('cursor summary', () {
    test('a cursor is the line and the column, from 1', () {
      final controller = EditorController(text: 'one\ntwo three');
      expect(_summary(controller), '1:1');
      controller.selections.selectRanges([(8, 8)]);
      expect(_summary(controller), '2:5');
      controller.dispose();
    });

    test('a selection says how many characters, and lines it spans', () {
      final controller = EditorController(text: 'one\ntwo three\nfour');
      controller.selections.selectRanges([(1, 2)]);
      expect(_summary(controller), '1:3 (1 character)');
      controller.selections.selectRanges([(0, 3)]);
      expect(_summary(controller), '1:4 (3 characters)');
      controller.selections.selectRanges([(2, 6)]);
      expect(_summary(controller), '2:3 (2 lines, 4 characters)');
      // ending at the start of a line does not count that line
      controller.selections.selectRanges([(0, 4)]);
      expect(_summary(controller), '2:1 (4 characters)');
      controller.dispose();
    });

    test('several cursors are counted, and characters are not code units', () {
      final controller = EditorController(text: 'a😀b\nc');
      controller.selections.selectRanges([(3, 3)]);
      expect(_summary(controller), '1:3');
      controller.selections.selectRanges([(0, 0), (5, 5)]);
      expect(_summary(controller), '2:1 (2 selections)');
      controller.dispose();
    });
  });
}
