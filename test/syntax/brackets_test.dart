import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor_core/rope.dart';
import 'package:ui/native_editor/editor_controller.dart';
import 'package:ui/syntax/syntax_layer.dart';
import 'package:ui/syntax/syntax_tree.dart';
import 'package:ui/syntax/ts_bindings.dart';

final _library = TreeSitter.instance;

final _highlights = File('native/tree_sitter/queries/luau/highlights.scm')
    .readAsStringSync();
final _brackets = File('native/tree_sitter/queries/luau/brackets.scm')
    .readAsStringSync();

const _function =
    'local function distance(a: Point, b: Point): number\n'
    '\tlocal dx = a.x - b.x\n'
    '\tlocal dy = a.y - b.y\n'
    '\treturn math.sqrt(dx * dx + dy * dy)\n'
    'end\n';

/// the text of the two ends of the pair that [head] is in, or null
String? _pair(String text, int head, [int? tail]) {
  final tree = SyntaxTree.create(
    Rope(text),
    _highlights,
    bracketsText: _brackets,
  )!;
  try {
    final found = tree.enclosingBrackets(head, tail ?? head);
    if (found == null) {
      return null;
    }
    return '${text.substring(found.openStart, found.openEnd)}'
        ' ${text.substring(found.closeStart, found.closeEnd)}';
  } finally {
    tree.dispose();
  }
}

void main() {
  group('the pair that the cursor is in', () {
    test('is function and end, in the body of a function', () {
      final inBody = _function.indexOf('local dy');
      expect(_pair(_function, inBody), 'function end');
      // anywhere in the body
      expect(
        _pair(_function, _function.indexOf('math.sqrt') + 3),
        'function end',
      );
    });

    test('is also that when the cursor is at an edge of the function', () {
      // at the start of the word function, and after the end
      expect(_pair(_function, _function.indexOf('function')), 'function end');
      expect(_pair(_function, _function.length - 1), 'function end');
      // inside the word end
      expect(
        _pair(_function, _function.lastIndexOf('end') + 1),
        'function end',
      );
    });

    test('is none outside of it', () {
      expect(_pair('local x = 1\n$_function', 3), isNull);
      expect(_pair('$_function\nlocal y = 2\n', _function.length + 5), isNull);
    });

    test('is the smaller one, for a block in a block', () {
      const text =
          'local function f()\n'
          '\tfor i = 1, 3 do\n'
          '\t\tprint(i)\n'
          '\tend\n'
          'end\n';
      // in the call, which has parentheses
      expect(_pair(text, text.indexOf('i)')), '( )');
      // at the edge of the call, which counts as being in it
      expect(_pair(text, text.indexOf('\n\tend')), '( )');
      // in the loop, away from the call
      expect(_pair(text, text.indexOf('\tend')), 'for end');
      // in the function, outside the loop
      expect(_pair(text, text.indexOf('local function') + 14), 'function end');
    });

    test('is a pair of parentheses, braces, or square brackets', () {
      const text = 'local t = { a = (1 + 2), b = f(x), [y] = t[3] }\n';
      expect(_pair(text, text.indexOf('1 +')), '( )');
      expect(_pair(text, text.indexOf('x)')), '( )');
      expect(_pair(text, text.indexOf('a =')), '{ }');
      expect(_pair(text, text.indexOf('3]')), '[ ]');
    });

    test('is the one of if, while, for, do and repeat', () {
      expect(_pair('if x then\n\ty()\nend\n', 11), 'if end');
      expect(_pair('while x do\n\ty()\nend\n', 12), 'while end');
      expect(_pair('for i = 1, 2 do\n\ty()\nend\n', 17), 'for end');
      expect(_pair('do\n\ty()\nend\n', 4), 'do end');
      expect(_pair('repeat\n\ty()\nuntil x\n', 8), 'repeat until');
    });

    test('is the one of a function that is an expression', () {
      const text = 'local f = function(a)\n\treturn a\nend\n';
      expect(_pair(text, text.indexOf('return')), 'function end');
    });

    test('takes a range, and holds all of it', () {
      const text = 'local function f()\n\tg(1)\nend\n';
      final tree = SyntaxTree.create(
        Rope(text),
        _highlights,
        bracketsText: _brackets,
      )!;
      // from inside the call to its closing parenthesis and out of it
      final inCall = tree.enclosingBrackets(
        text.indexOf('1'),
        text.indexOf(')') + 1,
      );
      expect(inCall, isNotNull);
      expect(text.substring(inCall!.openStart, inCall.openEnd), '(');
      // a range that goes out of the call is held by the function
      final wider = tree.enclosingBrackets(
        text.indexOf('g'),
        text.indexOf(')') + 1,
      );
      expect(text.substring(wider!.openStart, wider.openEnd), 'function');
      tree.dispose();
    });

    test('has offsets of the text, also after characters of two units', () {
      const text = '-- \u{1F600}\n$_function';
      final inBody = text.indexOf('local dy');
      expect(_pair(text, inBody), 'function end');
    });

    test('is none for text that is not finished, and does not fail', () {
      expect(() => _pair('local function f(\n', 10), returnsNormally);
      expect(() => _pair('if x then\n', 4), returnsNormally);
      expect(() => _pair('', 0), returnsNormally);
    });

    test('is none without the query of pairs', () {
      final tree = SyntaxTree.create(Rope(_function), _highlights)!;
      expect(tree.enclosingBrackets(40, 40), isNull);
      tree.dispose();
    });

    test('is none when the query of pairs does not compile', () {
      final tree = SyntaxTree.create(
        Rope(_function),
        _highlights,
        bracketsText: '(not_a_node "x" @open "y" @close)',
      )!;
      expect(tree.enclosingBrackets(40, 40), isNull);
      tree.dispose();
    });
  }, skip: _library == null);

  group('the editor lights the pair', () {
    EditorController editor(String text) {
      final controller = EditorController(text: text);
      final layer = SyntaxLayer.attach(
        controller.buffer,
        SyntaxTheme({}),
        _highlights,
        bracketsText: _brackets,
      );
      expect(layer, isNotNull);
      controller.setSyntax(layer);
      return controller;
    }

    /// the text of the two ends that are lit
    List<String> lit(EditorController controller) {
      final text = controller.text;
      final snapshot = controller.buffer.snapshot;
      return [
        for (final range in controller.matchingBrackets)
          text.substring(
            snapshot.offsetForAnchor(range.start),
            snapshot.offsetForAnchor(range.end),
          ),
      ];
    }

    test('both ends of the function that the cursor is in', () {
      final controller = editor(_function);
      controller.clickAt(_function.indexOf('local dy'));
      expect(lit(controller), ['function', 'end']);
      controller.dispose();
    });

    test('moves with the cursor, and goes out of the function', () {
      const text = 'local x = 1\n$_function';
      final controller = editor(text);
      // in the word end, which is at the end of the text
      controller.clickAt(text.length - 3);
      expect(lit(controller), ['function', 'end']);
      controller.clickAt(3);
      expect(lit(controller), isEmpty);
      controller.dispose();
    });

    test('is not lit while something is selected', () {
      final controller = editor(_function);
      controller.clickAt(_function.indexOf('local dy'));
      expect(lit(controller), isNotEmpty);
      controller.selectWordAt(_function.indexOf('dy'));
      expect(controller.selections.newest.isEmpty, isFalse);
      expect(lit(controller), isEmpty);
      controller.dispose();
    });

    test('is lit again for the text that was edited', () async {
      final controller = editor('local function f()\n\tg()\nend\n');
      controller.clickAt(controller.text.indexOf('g()'));
      expect(lit(controller), ['function', 'end']);
      // an edit, after which the tree is told of it later than the editor is
      controller.replaceSelections('x = 1\n\t');
      await Future<void>.delayed(Duration.zero);
      expect(lit(controller), ['function', 'end']);
      final snapshot = controller.buffer.snapshot;
      final end = controller.matchingBrackets.last;
      expect(
        controller.text.substring(
          snapshot.offsetForAnchor(end.start),
          snapshot.offsetForAnchor(end.end),
        ),
        'end',
      );
      controller.dispose();
    });

    test('is not lit when it is turned off, and is when it is turned on', () {
      final controller = editor(_function);
      controller.highlightMatchingBrackets = false;
      controller.clickAt(_function.indexOf('local dy'));
      expect(lit(controller), isEmpty);
      controller.highlightMatchingBrackets = true;
      controller.clickAt(_function.indexOf('local dx'));
      expect(lit(controller), ['function', 'end']);
      controller.dispose();
    });

    test('is in the color that is set for it', () {
      final controller = editor(_function);
      controller.bracketBackground = 0xFF123456;
      controller.clickAt(_function.indexOf('local dy'));
      final highlight = controller.highlights.textHighlights.values.where(
        (h) => h.style.background == 0xFF123456,
      );
      expect(highlight, hasLength(1));
      expect(highlight.single.ranges, hasLength(2));
      // and a color that is set while it is lit is taken at once
      controller.bracketBackground = 0xFF654321;
      expect(
        controller.highlights.textHighlights.values.where(
          (h) => h.style.background == 0xFF654321,
        ),
        hasLength(1),
      );
      controller.dispose();
    });
  }, skip: _library == null);
}
