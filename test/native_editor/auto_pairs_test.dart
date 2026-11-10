import 'package:flutter_test/flutter_test.dart';

import 'package:ui/native_editor/editor_controller.dart';

/// an editor with [text], where `|` marks the cursor, and `[` `]` a selection
EditorController _editor(String text) {
  final bar = text.indexOf('|');
  final open = text.indexOf('<');
  final controller = EditorController(
    text: text.replaceAll('|', '').replaceAll('<', '').replaceAll('>', ''),
  )..autoClose = true;
  if (open >= 0) {
    final close = text.indexOf('>') - 1;
    controller.selections.selectRanges([(open, close)]);
  } else {
    controller.selections.selectRanges([(bar, bar)]);
  }
  return controller;
}

/// the text with the cursor, or the selection, shown the way [_editor] takes it
String _show(EditorController controller) {
  final text = controller.text;
  final s = controller.selections.first;
  if (s.isEmpty) {
    return '${text.substring(0, s.start)}|${text.substring(s.start)}';
  }
  return '${text.substring(0, s.start)}<${text.substring(s.start, s.end)}>${text.substring(s.end)}';
}

void _type(EditorController controller, String characters) {
  for (final c in characters.split('')) {
    controller.typeText(c);
  }
}

void main() {
  group('closers come with openers', () {
    test('a bracket brings its closer when the end or a blank follows', () {
      final controller = _editor('|');
      _type(controller, '(');
      expect(_show(controller), '(|)');
      controller.dispose();
      final other = _editor('a |');
      _type(other, '{');
      expect(_show(other), 'a {|}');
      other.dispose();
    });

    test('only before a blank, the end of the text or a closer', () {
      final before = _editor('|word');
      _type(before, '(');
      expect(_show(before), '(|word');
      before.dispose();
      final inside = _editor('f(|)');
      _type(inside, '[');
      expect(_show(inside), 'f([|])');
      inside.dispose();
      // what the languages of code allow a closer before
      final comma = _editor('f(|, x)');
      _type(comma, '{');
      expect(_show(comma), 'f({|}, x)');
      comma.dispose();
      final letter = _editor('f(|x)');
      _type(letter, '{');
      expect(_show(letter), 'f({|x)');
      letter.dispose();
    });

    test('quotes do not come after a word, and not when they end a string', () {
      final apostrophe = _editor("don|");
      _type(apostrophe, "'");
      expect(_show(apostrophe), "don'|");
      apostrophe.dispose();
      final string = _editor('print(|)');
      _type(string, '"');
      expect(_show(string), 'print("|")');
      string.dispose();
      final ending = _editor('x = "abc|');
      _type(ending, '"');
      expect(_show(ending), 'x = "abc"|');
      ending.dispose();
    });
  });

  group('typing over a closer', () {
    test('the one that came with the opener is passed over', () {
      final controller = _editor('|');
      _type(controller, '(a)');
      expect(_show(controller), '(a)|');
      expect(controller.text, '(a)');
      controller.dispose();
    });

    test('one that was there before is typed again', () {
      final controller = _editor('f(|)');
      _type(controller, ')');
      expect(_show(controller), 'f()|)');
      controller.dispose();
    });

    test('nested pairs and quotes are passed over in turn', () {
      final controller = _editor('|');
      _type(controller, 'f({"a"})');
      expect(controller.text, 'f({"a"})');
      expect(_show(controller), 'f({"a"})|');
      controller.dispose();
    });

    test('moving out of the pair forgets it', () {
      final controller = _editor('|');
      _type(controller, '(');
      // out of the pair, and back between its brackets
      controller.moveHorizontally(forward: true, extend: false);
      controller.moveHorizontally(forward: false, extend: false);
      _type(controller, ')');
      expect(controller.text, '())');
      controller.dispose();
    });
  });

  group('selected text', () {
    test('is put between the pair, and stays selected', () {
      final controller = _editor('a <bc>d');
      _type(controller, '(');
      expect(controller.text, 'a (bc)d');
      expect(_show(controller), 'a (<bc>)d');
      controller.dispose();
    });

    test('is replaced by a character that is not an opener', () {
      final controller = _editor('a <bc>d');
      _type(controller, 'x');
      expect(controller.text, 'a xd');
      controller.dispose();
    });
  });

  group('backspace', () {
    test('takes the pair that came together, while nothing is in it', () {
      final controller = _editor('|');
      _type(controller, '(');
      controller.backspace();
      expect(controller.text, '');
      controller.dispose();
    });

    test('takes one character of a pair that was there before', () {
      final controller = _editor('(|)');
      controller.backspace();
      expect(controller.text, ')');
      controller.dispose();
    });

    test('and undo brings the pair back in one step', () {
      final controller = _editor('|');
      _type(controller, '[');
      expect(controller.text, '[]');
      controller.undo();
      expect(controller.text, '');
      controller.dispose();
    });
  });

  group('enter between brackets', () {
    test('puts the cursor on a line of its own, and the closer below', () {
      final controller = _editor('|');
      _type(controller, '{');
      controller.insertNewline();
      expect(controller.text, '{\n    \n}');
      expect(controller.selections.first.head, 6);
      controller.dispose();
    });

    test('keeps the indent of the line', () {
      final controller = _editor('  f(|)');
      controller.insertNewline();
      expect(controller.text, '  f(\n      \n  )');
      controller.dispose();
    });

    test('is the same with blanks between them', () {
      final controller = _editor('{ | }');
      controller.insertNewline();
      expect(controller.text, '{ \n    \n }');
      controller.dispose();
    });

    test('is not done between quotes', () {
      final controller = _editor('"|"');
      controller.insertNewline();
      expect(controller.text, '"\n"');
      controller.dispose();
    });
  });

  group('several cursors', () {
    test('each one is given its pair', () {
      final controller = EditorController(text: 'a\nb')..autoClose = true;
      controller.selections.selectRanges([(1, 1), (3, 3)]);
      controller.typeText('(');
      expect(controller.text, 'a()\nb()');
      controller.dispose();
    });
  });

  group('without the setting', () {
    test('a bracket is just typed', () {
      final controller = EditorController();
      controller.typeText('(');
      expect(controller.text, '(');
      controller.dispose();
    });
  });
}
