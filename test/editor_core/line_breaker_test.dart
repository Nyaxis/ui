import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor_core/display/line_breaker.dart';

/// the places [text] may be broken at, as the text with `|` put in at them
String _marked(String text) {
  final breaks = LineBreaks.of(text);
  final out = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && breaks.canBreakAt(i)) {
      out.write('|');
    }
    out.writeCharCode(text.codeUnitAt(i));
  }
  return out.toString();
}

void main() {
  group('LineBreaks', () {
    test('words break after their spaces', () {
      expect(_marked('one two  three'), 'one |two  |three');
    });

    test('lines end where a new line starts', () {
      final breaks = LineBreaks.of('ab\ncd\r\nef');
      expect(breaks.mandatory, {3, 7});
      expect(_marked('ab\ncd'), 'ab\n|cd');
    });

    test('a hyphen can end a row, a number is kept whole', () {
      expect(_marked('well-known'), 'well-|known');
      expect(_marked('x 1,000.50 y'), 'x |1,000.50 |y');
      expect(_marked('-5 and -x'), '-5 |and |-x');
    });

    test('brackets and quotes stay with the words in them', () {
      expect(_marked('a (b c) d'), 'a |(b |c) |d');
      expect(_marked('say "hi there" now'), 'say |"hi |there" |now');
    });

    test('east asian text breaks between characters, not before closers', () {
      expect(_marked('日本語です。次'), '日|本|語|で|す。|次');
      expect(_marked('日本（語）'), '日|本|（語）');
    });

    test('a word with a mark, and an emoji with a joiner, are not split', () {
      expect(_marked('é a'), 'é |a');
      expect(_marked('a 👨‍👩 b'), 'a |👨‍👩 |b');
    });

    test('flags are pairs of regional indicators', () {
      expect(
        _marked('\u{1F1E9}\u{1F1EA}\u{1F1EB}\u{1F1F7}'),
        '\u{1F1E9}\u{1F1EA}|\u{1F1EB}\u{1F1F7}',
      );
    });

    test('a break is not made at the start or the end', () {
      final breaks = LineBreaks.of('ab ');
      expect(breaks.canBreakAt(0), isFalse);
      expect(breaks.allowed, isEmpty);
      expect(LineBreaks.of('').allowed, isEmpty);
    });

    test('a hangul syllable block, and a url, are not broken inside', () {
      expect(_marked('각 x'), '각 |x');
      expect(_marked('a/b'), 'a/|b');
    });
  });
}
