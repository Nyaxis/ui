import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor_core/buffer.dart';
import 'package:ui/editor_core/display/invisibles.dart';
import 'package:ui/editor_core/display_map.dart';
import 'package:ui/editor_core/patch.dart';

const _red = HighlightStyle(color: 0xFFFF0000);
const _blue = HighlightStyle(color: 0xFF0000FF);
const _bold = HighlightStyle(bold: true);

/// a row as `text[style]` pieces, the style as its color name
String _pieces(DisplaySnapshot snapshot, int row, Highlights highlights) {
  String name(HighlightStyle? style) {
    if (style == null) {
      return '';
    }
    final parts = <String>[
      if (style.color == 0xFFFF0000) 'red',
      if (style.color == 0xFF0000FF) 'blue',
      if (style.bold == true) 'bold',
    ];
    return '[${parts.join('+')}]';
  }

  return [
    for (final c in snapshot.highlightedRowChunks(row, highlights))
      '${c.replacement ?? c.text}${name(c.style)}',
  ].join('|');
}

void main() {
  group('highlights', () {
    test('text highlights cut a row where they start and end', () {
      final buffer = TextBuffer('let value = 42;');
      final map = DisplayMap(buffer);
      final highlights = Highlights(
        textHighlights: {
          1: TextHighlight(_red, [buffer.snapshot.anchorRangeInside(4, 9)]),
        },
      );
      expect(_pieces(map.snapshot, 0, highlights), 'let |value[red]| = 42;');
    });

    test('highlights that overlap are laid over each other by their keys', () {
      final buffer = TextBuffer('abcdefghij');
      final map = DisplayMap(buffer);
      final snapshot = buffer.snapshot;
      final highlights = Highlights(
        textHighlights: {
          1: TextHighlight(_red, [snapshot.anchorRangeInside(0, 6)]),
          2: TextHighlight(_bold, [snapshot.anchorRangeInside(3, 9)]),
          3: TextHighlight(_blue, [snapshot.anchorRangeInside(5, 7)]),
        },
      );
      expect(
        _pieces(map.snapshot, 0, highlights),
        // a piece is cut where any highlight ends, even if the look stays
        'abc[red]|de[red+bold]|f[blue+bold]|g[blue+bold]|hi[bold]|j',
      );
    });

    test('of semantic tokens that cover the same text the top one counts', () {
      final buffer = TextBuffer('foo(bar)');
      final map = DisplayMap(buffer);
      final snapshot = buffer.snapshot;
      final highlights = Highlights(
        semanticTokens: [
          SemanticToken(snapshot.anchorRangeInside(0, 3), _red, 1),
          SemanticToken(snapshot.anchorRangeInside(0, 3), _blue, 2),
          SemanticToken(snapshot.anchorRangeInside(4, 7), _bold, 1),
        ],
      );
      expect(_pieces(map.snapshot, 0, highlights), 'foo[blue]|(|bar[bold]|)');
    });

    test('highlights follow tabs, folds and inlays to the screen', () {
      final buffer = TextBuffer('a\tbc def');
      final map = DisplayMap(buffer, tabSize: 4);
      map.spliceInlays([], [
        Inlay(
          id: 1,
          position: buffer.anchorAt(5, Bias.left),
          text: '<I>',
          style: _blue,
        ),
      ]);
      final snapshot = buffer.snapshot;
      final highlights = Highlights(
        textHighlights: {
          1: TextHighlight(_red, [snapshot.anchorRangeInside(2, 7)]),
        },
      );
      // the tab is not part of what is highlighted; the inlay is its own
      expect(
        _pieces(map.snapshot, 0, highlights),
        'a|   |bc [red]|<I>[blue]|de[red]|f',
      );
    });

    test('highlights are anchored, so they stay with their text', () {
      final buffer = TextBuffer('one two three');
      final map = DisplayMap(buffer);
      final highlights = Highlights(
        textHighlights: {
          1: TextHighlight(_red, [buffer.snapshot.anchorRangeInside(4, 7)]),
        },
      );
      buffer.edit([const Replacement.insert(0, 'zero ')]);
      expect(_pieces(map.snapshot, 0, highlights), 'zero one |two[red]| three');
    });

    test('random highlights agree with a model that colors each character', () {
      for (var seed = 0; seed < 100; seed++) {
        final random = Random(seed);
        final text = List.generate(
          10 + random.nextInt(40),
          (_) => 'ab cd\n'[random.nextInt(6)],
        ).join();
        final buffer = TextBuffer(text);
        final map = DisplayMap(buffer, tabSize: 1);
        final snapshot = buffer.snapshot;
        final styles = [_red, _blue, _bold];
        final keyed = <int, TextHighlight>{};
        final colorOf = List<List<HighlightStyle>>.generate(
          text.length,
          (_) => [],
        );
        for (var key = 0; key < 3; key++) {
          final ranges = <AnchorRange>[];
          var at = random.nextInt(8);
          while (at < text.length) {
            final end = min(text.length, at + 1 + random.nextInt(8));
            ranges.add(snapshot.anchorRangeInside(at, end));
            for (var i = at; i < end; i++) {
              colorOf[i].add(styles[key]);
            }
            at = end + random.nextInt(8);
          }
          keyed[key] = TextHighlight(styles[key], ranges);
        }
        final highlights = Highlights(textHighlights: keyed);
        final shown = map.snapshot;
        var offset = 0;
        for (var row = 0; row < shown.rowCount; row++) {
          for (final chunk in shown.highlightedRowChunks(row, highlights)) {
            for (var i = 0; i < chunk.text.length; i++) {
              HighlightStyle? want;
              for (final style in colorOf[offset + i]) {
                want = want == null ? style : want.merge(style);
              }
              expect(
                chunk.style,
                want,
                reason: 'seed $seed offset ${offset + i}',
              );
            }
            offset += chunk.text.length;
          }
          offset++;
        }
      }
    });
  });

  group('invisible characters', () {
    test('control characters and odd spaces are shown as something else', () {
      expect(isInvisible(0x00), isTrue);
      expect(isInvisible(0x09), isFalse);
      expect(isInvisible(0x0A), isFalse);
      expect(isInvisible(0x20), isFalse);
      expect(isInvisible(0xA0), isTrue);
      expect(isInvisible(0x200B), isTrue);
      expect(isInvisible(0x3000), isFalse);
      expect(isInvisible(0x41), isFalse);
      expect(String.fromCharCode(replacement(0x00)!), '␀');
      expect(String.fromCharCode(replacement(0x1B)!), '␛');
      expect(String.fromCharCode(replacement(0x7F)!), '␡');
      expect(String.fromCharCode(replacement(0xA0)!), ' ');
      // a joiner is kept, as it builds other characters
      expect(replacement(0x200D), isNull);
    });

    test('a row has them as pieces of their own', () {
      final buffer = TextBuffer('a\u0001b c');
      final map = DisplayMap(buffer);
      expect(_pieces(map.snapshot, 0, Highlights.none), 'a|␁|b| |c');
    });

    test('a character shown as another has the width of that one', () {
      // `\u0001` is shown as one symbol, so a row of them wraps as symbols
      final buffer = TextBuffer('\u0001\u0001\u0001\u0001');
      final map = DisplayMap(buffer, wrapWidth: 2);
      expect(map.snapshot.rowCount, 2);
    });
  });
}
