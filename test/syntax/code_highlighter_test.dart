import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor_core/highlight.dart';
import 'package:ui/syntax/code_highlighter.dart';
import 'package:ui/syntax/syntax_tree.dart';
import 'package:ui/syntax/ts_bindings.dart';

final _library = TreeSitter.instance;

const _keyword = HighlightStyle(color: 1);
const _string = HighlightStyle(color: 2);

CodeHighlighter _highlighter() => CodeHighlighter(
  File('native/tree_sitter/queries/luau/highlights.scm').readAsStringSync(),
  SyntaxTheme({'keyword': _keyword, 'string': _string}),
);

void main() {
  group('the languages that are read', () {
    test('are luau and lua', () {
      expect(CodeHighlighter.reads('luau'), isTrue);
      expect(CodeHighlighter.reads('lua'), isTrue);
      expect(CodeHighlighter.reads('rust'), isFalse);
      expect(CodeHighlighter.reads(''), isFalse);
      expect(CodeHighlighter.reads(null), isFalse);
    });
  });

  group('the colors of a code', () {
    test('are those that the grammar says', () {
      final spans = _highlighter().spans('local s = "a"');
      expect(
        [for (final s in spans) (s.start, s.end, s.style.color)],
        [(0, 5, 1), (10, 13, 2)],
      );
    }, skip: _library == null);

    test('are kept for the code that comes again', () {
      final highlighter = _highlighter();
      final first = highlighter.spans('local s = "a"');
      expect(identical(highlighter.spans('local s = "a"'), first), isTrue);
    }, skip: _library == null);

    test('keep no more than a number of codes, the oldest going', () {
      final highlighter = _highlighter();
      final first = highlighter.spans('local a = 1');
      for (var i = 0; i < CodeHighlighter.cacheSize; i++) {
        highlighter.spans('local b$i = 1');
      }
      // the first was read again, as it was not kept
      expect(identical(highlighter.spans('local a = 1'), first), isFalse);
    }, skip: _library == null);

    test('are none where the parser is not there', () {
      expect(_highlighter().spans('local s = 1'), isEmpty);
    }, skip: _library != null);
  });
}
