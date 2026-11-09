import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor_core/point.dart';
import 'package:ui/editor_core/rope.dart';

/// the lines of [text] by the same rules as the rope, to check it against
List<int> _lineStarts(String text) => [
  0,
  for (var i = 0; i < text.length; i++)
    if (text.codeUnitAt(i) == 0x0A) i + 1,
];

void _expectSame(Rope rope, String text) {
  expect(rope.length, text.length);
  expect(rope.toString(), text);
  final starts = _lineStarts(text);
  expect(rope.lineCount, starts.length);
  for (var row = 0; row < starts.length; row++) {
    expect(rope.lineStart(row), starts[row], reason: 'start of line $row');
    final end = row + 1 < starts.length ? starts[row + 1] - 1 : text.length;
    expect(rope.lineEnd(row), end, reason: 'end of line $row');
    expect(rope.lineText(row), text.substring(starts[row], end));
  }
}

void main() {
  group('Rope', () {
    test('an empty rope has one empty line', () {
      expect(Rope.empty.length, 0);
      expect(Rope.empty.lineCount, 1);
      expect(Rope.empty.toString(), '');
      expect(Rope.empty.lineText(0), '');
      expect(Rope.empty.offsetToPoint(0), Point.zero);
      expect(Rope.empty.pointToOffset(const Point(3, 4)), 0);
    });

    test('lines end at a newline, and the last line may be empty', () {
      final rope = Rope('one\ntwo\n\nfour\n');
      expect(rope.lineCount, 5);
      expect(rope.lineText(0), 'one');
      expect(rope.lineText(2), '');
      expect(rope.lineText(3), 'four');
      expect(rope.lineText(4), '');
      expect(rope.lineLength(1), 3);
    });

    test('a point and its offset find each other', () {
      final rope = Rope('ab\ncde\n\nf');
      expect(rope.offsetToPoint(0), const Point(0, 0));
      expect(rope.offsetToPoint(2), const Point(0, 2));
      expect(rope.offsetToPoint(3), const Point(1, 0));
      expect(rope.offsetToPoint(9), const Point(3, 1));
      expect(rope.pointToOffset(const Point(1, 2)), 5);
      // columns and rows that are too big stop at the end
      expect(rope.pointToOffset(const Point(1, 99)), 6);
      expect(rope.pointToOffset(const Point(99, 0)), rope.length);
      expect(rope.pointToOffset(const Point(0, -4)), 0);
    });

    test('a pair of surrogates stays in one chunk when a text is cut', () {
      final text = '${'a' * 1023}\u{1F600}${'b' * 10}';
      final rope = Rope(text);
      expect(rope.chunks.every((c) => !c.endsWith('\uD83D')), isTrue);
      expect(rope.toString(), text);
    });

    test('it can be split and joined at every offset', () {
      final text = 'first\nsecond line\n\nthird\n' * 3;
      final rope = Rope(text);
      for (var at = 0; at <= text.length; at++) {
        final (a, b) = rope.split(at);
        expect(a.toString(), text.substring(0, at));
        expect(b.toString(), text.substring(at));
        _expectSame(a + b, text);
      }
    });

    test('a replaced range is read back, and the old rope is unchanged', () {
      final rope = Rope('hello world');
      final edited = rope.replaceRange(6, 11, 'there\nfriend');
      expect(edited.toString(), 'hello there\nfriend');
      expect(rope.toString(), 'hello world');
    });

    test('substring and code units follow the text', () {
      final text = List.generate(3000, (i) => 'line $i\n').join();
      final rope = Rope(text);
      expect(rope.substring(10, 5000), text.substring(10, 5000));
      expect(rope.substring(0, 0), '');
      for (final at in [0, 1, 1023, 1024, 1025, 5000, text.length - 1]) {
        expect(rope.codeUnitAt(at), text.codeUnitAt(at));
      }
      expect(() => rope.substring(5, 3), throwsRangeError);
      expect(() => rope.codeUnitAt(text.length), throwsRangeError);
    });

    test('random edits give the text a string would give', () {
      final random = Random(7);
      final pieces = ['a', 'bc', '\n', 'xyz\n', '\u{1F600}', '', 'long ' * 40];
      var text = '';
      var rope = Rope.empty;
      for (var step = 0; step < 600; step++) {
        final start = random.nextInt(text.length + 1);
        final end = start + random.nextInt(min(30, text.length - start) + 1);
        final insert = List.generate(
          random.nextInt(4),
          (_) => pieces[random.nextInt(pieces.length)],
        ).join();
        // an edit does not cut a pair of surrogates in two
        if (start > 0 && start < text.length && _splitsPair(text, start)) {
          continue;
        }
        if (end > 0 && end < text.length && _splitsPair(text, end)) {
          continue;
        }
        text = text.replaceRange(start, end, insert);
        rope = rope.replaceRange(start, end, insert);
        if (step % 25 == 0) {
          _expectSame(rope, text);
        }
        if (text.isNotEmpty) {
          final at = random.nextInt(text.length + 1);
          final row = rope.rowAt(at);
          expect(row, _lineStarts(text).where((s) => s <= at).length - 1);
          expect(rope.offsetToPoint(at).row, row);
          expect(rope.pointToOffset(rope.offsetToPoint(at)), at);
        }
      }
      _expectSame(rope, text);
    });

    test('it stays shallow and quick through many edits of a big text', () {
      final text = List.generate(40000, (i) => 'line number $i\n').join();
      var rope = Rope(text);
      final random = Random(3);
      final timer = Stopwatch()..start();
      for (var i = 0; i < 4000; i++) {
        final at = random.nextInt(rope.length);
        rope = rope.replaceRange(at, at, 'x');
        rope.lineStart(random.nextInt(rope.lineCount));
      }
      expect(rope.length, text.length + 4000);
      expect(timer.elapsed.inSeconds, lessThan(5));
    });

    test('ropes with the same text are equal', () {
      expect(Rope('abc'), Rope('ab') + Rope('c'));
      expect(Rope('abc') == Rope('abd'), isFalse);
      expect(Rope('abc').hashCode, (Rope('ab') + Rope('c')).hashCode);
    });
  });
}

bool _splitsPair(String text, int at) =>
    text.codeUnitAt(at - 1) >= 0xD800 &&
    text.codeUnitAt(at - 1) <= 0xDBFF &&
    text.codeUnitAt(at) >= 0xDC00 &&
    text.codeUnitAt(at) <= 0xDFFF;
