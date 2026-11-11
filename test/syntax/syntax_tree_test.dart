import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor_core/buffer.dart';
import 'package:ui/editor_core/highlight.dart';
import 'package:ui/editor_core/rope.dart';
import 'package:ui/syntax/lua_pattern.dart';
import 'package:ui/syntax/syntax_tree.dart';
import 'package:ui/syntax/ts_bindings.dart';

final _library = TreeSitter.instance;

final _queryText = File('native/tree_sitter/queries/luau/highlights.scm')
    .readAsStringSync();

const _keyword = HighlightStyle(color: 1);
const _number = HighlightStyle(color: 2);
const _comment = HighlightStyle(color: 3);
const _string = HighlightStyle(color: 4);
const _function = HighlightStyle(color: 5);
const _type = HighlightStyle(color: 6);

final _theme = SyntaxTheme({
  'keyword': _keyword,
  'number': _number,
  'comment': _comment,
  'string': _string,
  'function': _function,
  'type': _type,
});

SyntaxTree _tree(String text) {
  final errors = <String>[];
  final tree = SyntaxTree.create(Rope(text), _queryText, error: errors.add);
  expect(tree, isNotNull, reason: errors.join());
  return tree!;
}

/// the style of the character at [offset], or null
HighlightStyle? _styleAt(SyntaxTree tree, int offset) {
  for (final span in tree.spans(0, tree.text.length, _theme)) {
    if (span.start <= offset && offset < span.end) {
      return span.style;
    }
  }
  return null;
}

void main() {
  group('lua patterns', () {
    bool matches(String pattern, String text) =>
        luaPatternToRegExp(pattern)!.hasMatch(text);

    test('the patterns of the highlight queries', () {
      expect(matches('^[A-Z]', 'Players'), isTrue);
      expect(matches('^[A-Z]', 'players'), isFalse);
      expect(matches('^[A-Z][A-Z_0-9]+\$', 'MAX_SPEED'), isTrue);
      expect(matches('^[A-Z][A-Z_0-9]+\$', 'MaxSpeed'), isFalse);
      expect(matches('^[-][-][-]', '--- doc'), isTrue);
      expect(matches('^[-][-][-]', '-- not'), isFalse);
      expect(matches('^[-][-](%s?)@', '-- @param'), isTrue);
      expect(matches('^[-][-](%s?)@', '--@param'), isTrue);
      expect(matches('^[-][-](%s?)@', '--  @param'), isFalse);
    });

    test('classes, quantifiers and what is not understood', () {
      expect(matches('^%d+\$', '12345'), isTrue);
      expect(matches('^%d+\$', '12a45'), isFalse);
      expect(matches('^%a-x', 'abx'), isTrue);
      expect(matches('%.', 'a.b'), isTrue);
      expect(luaPatternToRegExp('%b()'), isNull);
      expect(luaPatternToRegExp('[abc'), isNull);
    });
  });

  group('syntax tree', () {
    test('what a script is made of is drawn by its names', () {
      final text = 'local x = 5 -- hi\nprint("a")\n';
      final tree = _tree(text);
      expect(tree.hasErrors, isFalse);
      expect(_styleAt(tree, text.indexOf('local')), _keyword);
      expect(_styleAt(tree, text.indexOf('5')), _number);
      expect(_styleAt(tree, text.indexOf('-- hi')), _comment);
      expect(_styleAt(tree, text.indexOf('"a"')), _string);
      expect(_styleAt(tree, text.indexOf('x')), isNull);
      tree.dispose();
    }, skip: _library == null);

    test('the conditions of the query are checked on the text', () {
      final text = 'local Players = 1\nlocal players = 2\n';
      final tree = _tree(text);
      expect(_styleAt(tree, text.indexOf('Players')), _type);
      expect(_styleAt(tree, text.indexOf('players')), isNot(_type));
      tree.dispose();
    }, skip: _library == null);

    test('a block that has no end yet is drawn as one that has', () {
      for (final text in [
        'function foo()\n',
        'local function foo(a: number)\n\tprint(a)\n',
        'if x then\n\tprint(1)\n',
      ]) {
        final tree = _tree(text);
        expect(tree.hasErrors, isTrue, reason: text);
        final first = text.startsWith('local')
            ? 'local'
            : text.split(' ').first;
        expect(
          _styleAt(tree, text.indexOf(first.replaceAll('(', ''))),
          _keyword,
          reason: text,
        );
        tree.dispose();
      }
    }, skip: _library == null);

    test('the spans are in order, and one style covers a part of text', () {
      final text = 'for i = 1, 10 do\n\tprint(i, "text")\nend\n';
      final tree = _tree(text);
      final spans = tree.spans(0, text.length, _theme);
      expect(spans, isNotEmpty);
      for (var i = 1; i < spans.length; i++) {
        expect(spans[i].start, greaterThanOrEqualTo(spans[i - 1].end));
      }
      // only the part that is asked for
      final part = tree.spans(text.indexOf('print'), text.length, _theme);
      expect(part.first.start, greaterThanOrEqualTo(text.indexOf('print')));
      tree.dispose();
    }, skip: _library == null);

    test('after edits, it is what a new tree of the text would be', () {
      final random = Random(7);
      final snippets = [
        'local a = 1\n',
        'function f(x: number): string\n',
        'end\n',
        '"str😀"',
        '-- c\n',
        'Players',
        ' + 2',
        'if x then\n',
        '\n',
        '`n{x}`',
      ];
      final buffer = TextBuffer('local x = 5\nprint(x)\n');
      final subscription = buffer.subscribe();
      final tree = _tree(buffer.text.toString());
      for (var step = 0; step < 150; step++) {
        final old = buffer.text;
        final length = old.length;
        final start = random.nextInt(length + 1);
        final end = min(
          length,
          start + (random.nextBool() ? 0 : random.nextInt(8)),
        );
        final inserted = random.nextInt(4) == 0
            ? ''
            : snippets[random.nextInt(snippets.length)];
        buffer.edit([Replacement(start, end, inserted)]);
        tree.update(old, buffer.text, subscription.consume());
        final fresh = _tree(buffer.text.toString());
        final a = tree.spans(0, buffer.length, _theme).join(';');
        final b = fresh.spans(0, buffer.length, _theme).join(';');
        expect(a, b, reason: 'step $step, ${buffer.text}');
        fresh.dispose();
      }
      tree.dispose();
    }, skip: _library == null);
  });
}
