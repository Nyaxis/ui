import 'package:flutter_test/flutter_test.dart';
import 'package:ui/editor_core/buffer.dart';
import 'package:ui/lsp/diagnostic_range.dart';
import 'package:ui/lsp/lsp_client.dart';

LspRange _range(int line, int from, int toLine, int to) =>
    LspRange(LspPosition(line, from), LspPosition(toLine, to));

(int, int) _offsets(String text, LspRange range) =>
    diagnosticOffsets(TextBuffer(text).text, range);

void main() {
  test('a range that has something in it is not changed', () {
    expect(_offsets('local x = 1', _range(0, 6, 0, 7)), (6, 7));
    expect(_offsets('ab\ncd', _range(0, 1, 1, 1)), (1, 4));
  });

  test('an empty range grows by one character to the right', () {
    expect(_offsets('abc', _range(0, 1, 0, 1)), (1, 2));
    expect(_offsets('ab\ncd', _range(1, 0, 1, 0)), (3, 4));
  });

  test('an empty range at the end of its line grows to the left', () {
    expect(_offsets('abc', _range(0, 3, 0, 3)), (2, 3));
    expect(_offsets('abc\ndef', _range(0, 3, 0, 3)), (2, 3));
    // the end of the text, after the space that ends the line
    expect(_offsets('local x = ', _range(0, 10, 0, 10)), (9, 10));
  });

  test('an empty range on an empty line has nothing to underline', () {
    final (start, end) = _offsets('a\n\nb', _range(1, 0, 1, 0));
    expect(end, start);
    final (emptyStart, emptyEnd) = _offsets('', _range(0, 0, 0, 0));
    expect(emptyEnd, emptyStart);
  });

  test('a range that is only the end of a line is its last character', () {
    expect(_offsets('abc\ndef', _range(0, 3, 1, 0)), (2, 3));
    expect(_offsets('abc\ndef', _range(0, 1, 1, 0)), (1, 4));
  });

  test('a range outside of the text is clipped to it', () {
    expect(_offsets('ab', _range(5, 0, 5, 5)), (1, 2));
    expect(_offsets('ab', _range(0, 1, 0, 99)), (1, 2));
  });

  test('a pair of code units is not split', () {
    // an emoji is two code units
    expect(_offsets('😀x', _range(0, 1, 0, 1)), (0, 2));
    expect(_offsets('😀x', _range(0, 0, 0, 1)), (0, 2));
  });
}
