import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor_core/highlight.dart';
import 'package:ui/native_editor/editor_controller.dart';
import 'package:ui/syntax/syntax_layer.dart';
import 'package:ui/syntax/syntax_tree.dart';
import 'package:ui/syntax/ts_bindings.dart';

final _library = TreeSitter.instance;

const _keyword = HighlightStyle(color: 1);
const _string = HighlightStyle(color: 2);

final _theme = SyntaxTheme({'keyword': _keyword, 'string': _string});

EditorController _editor(String text) {
  final controller = EditorController(text: text);
  final layer = SyntaxLayer.attach(
    controller.buffer,
    _theme,
    File('native/tree_sitter/queries/luau/highlights.scm').readAsStringSync(),
  );
  expect(layer, isNotNull);
  controller.setSyntax(layer);
  return controller;
}

/// the style of each piece of row 0, as `text:color`
String _row(EditorController controller, [int row = 0]) => controller.snapshot
    .highlightedRowChunks(row, controller.highlights)
    .map((c) => '${c.text}:${c.style?.color}')
    .join(' ');

void main() {
  group('syntax layer', () {
    test('the text of a row is drawn by what the grammar says', () {
      final controller = _editor('local s = "a"');
      expect(_row(controller), 'local:1  s = :null "a":2');
      controller.dispose();
    }, skip: _library == null);

    test('the colors follow the text as it is edited', () {
      final controller = _editor('local s = "a"');
      // the keyword is not one any more
      controller.selections.selectRanges([(5, 5)]);
      controller.replaceSelections('s');
      expect(_row(controller), 'locals s = :null "a":2');
      controller.undo();
      expect(_row(controller), 'local:1  s = :null "a":2');
      // a string that is not ended
      controller.selections.selectRanges([(13, 13)]);
      controller.replaceSelections('\nlocal t = "b');
      expect(_row(controller, 1), 'local:1  t = :null "b:2');
      controller.dispose();
    }, skip: _library == null);

    test('a layer that is taken away leaves the text plain', () {
      final controller = _editor('local x');
      controller.setSyntax(null);
      expect(_row(controller), 'local x:null');
      controller.dispose();
    }, skip: _library == null);
  });
}
