import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor_core/buffer.dart';
import 'package:ui/editor_core/display/fold_map.dart';
import 'package:ui/editor_core/display/inlay_map.dart';
import 'package:ui/editor_core/display/layer_edit.dart';
import 'package:ui/editor_core/display/tab_map.dart';
import 'package:ui/editor_core/patch.dart';
import 'package:ui/editor_core/point.dart';
import 'package:ui/editor_core/text_summary.dart';

import 'helpers.dart';

/// [text] with its tabs as spaces, worked out a line at a time
String _expand(String text, int tabSize, int maxExpansionColumn) {
  final out = StringBuffer();
  var column = 0;
  var chars = 0;
  for (final rune in text.runes) {
    if (rune == 0x0A) {
      out.write('\n');
      column = 0;
      chars = 0;
    } else if (rune == 0x09 && column < maxExpansionColumn) {
      final len = tabSize - chars % tabSize;
      out.write(' ' * len);
      chars += len;
      column++;
    } else if (rune == 0x09) {
      out.write(' ');
      chars++;
      column++;
    } else {
      out.writeCharCode(rune);
      chars++;
      column += rune > 0xFFFF ? 2 : 1;
    }
  }
  return out.toString();
}

String _applyEdits(String old, String now, List<PointEdit> edits) {
  var text = old;
  for (final edit in edits.reversed) {
    text = text.replaceRange(
      pointToOffsetIn(old, edit.oldStart),
      pointToOffsetIn(old, edit.oldEnd),
      now.substring(
        pointToOffsetIn(now, edit.newStart),
        pointToOffsetIn(now, edit.newEnd),
      ),
    );
  }
  return text;
}

class _Layers {
  _Layers(String text, this.tabSize) : buffer = TextBuffer(text) {
    inlays = InlayMap(buffer.snapshot);
    folds = FoldMap(inlays.snapshot);
    tabs = TabMap(folds.snapshot, tabSize);
  }

  final TextBuffer buffer;
  int tabSize;
  late final InlayMap inlays;
  late final FoldMap folds;
  late final TabMap tabs;

  List<PointEdit> edit(List<Replacement> replacements) {
    final bufferEdits = layerEditsFromPatch(buffer.edit(replacements));
    final (inlaySnapshot, inlayEdits) = inlays.sync(
      buffer.snapshot,
      bufferEdits,
    );
    final (foldSnapshot, foldEdits) = folds.read(inlaySnapshot, inlayEdits);
    return tabs.sync(foldSnapshot, foldEdits, tabSize).$2;
  }

  List<PointEdit> afterFolds((FoldSnapshot, List<LayerEdit>) result) =>
      tabs.sync(result.$1, result.$2, tabSize).$2;

  List<PointEdit> spliceInlays(List<int> remove, List<Inlay> insert) {
    final (inlaySnapshot, inlayEdits) = inlays.splice(remove, insert);
    return afterFolds(folds.read(inlaySnapshot, inlayEdits));
  }
}

void main() {
  group('TabMap', () {
    test('a tab is the spaces to the next stop', () {
      final layers = _Layers('\ta\tbc\t\n\t', 4);
      final snapshot = layers.tabs.snapshot;
      expect(snapshot.text, '    a   bc  \n    ');
      expect(snapshot.maxPoint, const Point(1, 4));
      expect(snapshot.lineLen(0), 12);
      expect(
        snapshot.foldPointToTabPoint(const Point(0, 2)),
        const Point(0, 5),
      );
      expect(
        snapshot.foldPointToTabPoint(const Point(0, 3)),
        const Point(0, 8),
      );
    });

    test('a place inside a tab goes to one side of it', () {
      final snapshot = _Layers('\ta', 4).tabs.snapshot;
      expect(snapshot.tabPointToFoldPoint(const Point(0, 2), Bias.left), (
        const Point(0, 0),
        2,
        2,
      ));
      expect(snapshot.tabPointToFoldPoint(const Point(0, 2), Bias.right), (
        const Point(0, 1),
        2,
        0,
      ));
      expect(
        snapshot.clipPoint(const Point(0, 2), Bias.left),
        const Point(0, 0),
      );
      expect(
        snapshot.clipPoint(const Point(0, 2), Bias.right),
        const Point(0, 4),
      );
      expect(
        snapshot.tabPointToFoldPoint(const Point(0, 5), Bias.left).$1,
        const Point(0, 2),
      );
    });

    test('text can be read from the middle of a tab', () {
      final snapshot = _Layers('\tab\tc', 4).tabs.snapshot;
      expect(snapshot.text, '    ab  c');
      expect(
        snapshot.textForRange(const Point(0, 2), const Point(0, 7)),
        '  ab ',
      );
      expect(snapshot.textForRange(const Point(0, 1), const Point(0, 3)), '  ');
      expect(
        snapshot.textForRange(const Point(0, 4), const Point(0, 9)),
        'ab  c',
      );
    });

    test('a wide character counts once for where tabs stop', () {
      final snapshot = _Layers('😀\tx', 4).tabs.snapshot;
      // one character, then three spaces to the stop
      expect(snapshot.text, '😀   x');
    });

    test(
      'tabs past the column where they stop being expanded are one cell',
      () {
        final layers = _Layers('\ta\tb\tc', 4);
        final snapshot = layers.tabs.setMaxExpansionColumn(2);
        expect(snapshot.text, '    a b c');
        expect(
          snapshot.foldPointToTabPoint(const Point(0, 4)),
          const Point(0, 7),
        );
        expect(
          snapshot.tabPointToFoldPoint(const Point(0, 7), Bias.left).$1,
          const Point(0, 4),
        );
      },
    );

    test('text typed on a line changes the tabs after it', () {
      final layers = _Layers('a\tb\tc\nx\ty', 4);
      final before = layers.tabs.snapshot.text;
      expect(before, 'a   b   c\nx   y');
      final edits = layers.edit([const Replacement.insert(1, 'zz')]);
      final after = layers.tabs.snapshot.text;
      expect(after, 'azz b   c\nx   y');
      // the edit takes in the tab after it, which is narrower now
      expect(edits, const [
        PointEdit(Point(0, 1), Point(0, 4), Point(0, 1), Point(0, 4)),
      ]);
      expect(_applyEdits(before, after, edits), after);
    });

    test('a change of the width of tabs changes everything', () {
      final layers = _Layers('\ta\n\tb', 4);
      layers.tabSize = 2;
      final edits = layers.afterFolds((layers.folds.snapshot, const []));
      expect(layers.tabs.snapshot.text, '  a\n  b');
      expect(edits, const [
        PointEdit(Point.zero, Point(1, 5), Point.zero, Point(1, 3)),
      ]);
    });

    test('random text is expanded as expected, through folds and edits', () {
      const pieces = [
        'a',
        'bc',
        '\n',
        ' ',
        '\t',
        '\t',
        'word',
        '\n\t',
        '😀',
        '\t\t',
      ];
      for (var seed = 0; seed < 120; seed++) {
        final random = Random(seed);
        String randomText(int max) => List.generate(
          random.nextInt(max),
          (_) => pieces[random.nextInt(pieces.length)],
        ).join();

        final tabSize = 1 + random.nextInt(8);
        final layers = _Layers(randomText(40), tabSize);
        final maxColumn = random.nextBool() ? 256 : 1 + random.nextInt(12);
        layers.tabs.setMaxExpansionColumn(maxColumn);
        final buffer = layers.buffer;
        int offset() => buffer.text.clipOffset(
          random.nextInt(buffer.length + 1),
          Bias.left,
        );
        var nextInlay = 0;
        var shown = layers.tabs.snapshot.text;
        for (var step = 0; step < 20; step++) {
          final List<PointEdit> edits;
          switch (random.nextInt(5)) {
            case 0:
            case 1:
              final a = offset();
              final b = offset();
              edits = layers.edit([
                Replacement(min(a, b), max(a, b), randomText(4)),
              ]);
            case 2:
              edits = layers.spliceInlays([], [
                inlayAt(
                  buffer,
                  nextInlay++,
                  offset(),
                  randomText(3),
                  random.nextBool() ? Bias.left : Bias.right,
                ),
              ]);
            case 3:
              final a = offset();
              final b = offset();
              edits = layers.afterFolds(
                layers.folds.unfoldIntersecting([(min(a, b), max(a, b))]),
              );
            default:
              final a = offset();
              final b = offset();
              edits = layers.afterFolds(
                layers.folds.fold([(min(a, b), max(a, b), null)]),
              );
          }

          final why = 'seed $seed step $step tab $tabSize max $maxColumn';
          final snapshot = layers.tabs.snapshot;
          final fold = layers.folds.snapshot;
          final foldText = fold.text;
          final expected = _expand(foldText, tabSize, maxColumn);
          expect(snapshot.text, expected, reason: why);
          expect(
            snapshot.maxPoint,
            TextSummary.of(expected).lines,
            reason: why,
          );
          expect(_applyEdits(shown, expected, edits), expected, reason: why);
          shown = expected;

          final lines = expected.split('\n');
          for (var row = 0; row < lines.length; row++) {
            expect(snapshot.lineLen(row), lines[row].length, reason: why);
          }

          // the places of the fold layer go up, to where the text before
          // them comes to, and come down again
          for (var at = 0; at <= foldText.length; at++) {
            if (at > 0 &&
                at < foldText.length &&
                foldText.codeUnitAt(at) >= 0xDC00 &&
                foldText.codeUnitAt(at) <= 0xDFFF) {
              continue;
            }
            final foldPoint = fold.toPoint(at);
            final tabPoint = snapshot.foldPointToTabPoint(foldPoint);
            final lineStart = at == 0
                ? 0
                : foldText.lastIndexOf('\n', at - 1) + 1;
            final want = _expand(
              foldText.substring(lineStart, at),
              tabSize,
              maxColumn,
            ).length;
            expect(tabPoint, Point(foldPoint.row, want), reason: '$why at $at');
            for (final bias in Bias.values) {
              expect(
                snapshot.tabPointToFoldPoint(tabPoint, bias).$1,
                foldPoint,
                reason: '$why at $at',
              );
            }
          }

          for (var i = 0; i < 8; i++) {
            final a = random.nextInt(expected.length + 1);
            final b = random.nextInt(expected.length + 1);
            final from = min(a, b);
            final to = max(a, b);
            final start = offsetToPointIn(expected, from);
            final end = offsetToPointIn(expected, to);
            if (_inPair(expected, from) || _inPair(expected, to)) {
              continue;
            }
            expect(
              snapshot.textForRange(start, end),
              expected.substring(from, to),
              reason: '$why range $start..$end',
            );
            final summary = snapshot.textSummaryForRange(start, end);
            final want = TextSummary.of(expected, from, to);
            expect(summary.lines, want.lines, reason: why);
            expect(summary.firstLineChars, want.firstLineChars, reason: why);
            expect(summary.lastLineChars, want.lastLineChars, reason: why);
            for (final bias in Bias.values) {
              final clipped = snapshot.clipPoint(start, bias);
              expect(snapshot.clipPoint(clipped, bias), clipped, reason: why);
            }
          }
        }
      }
    });
  });
}

bool _inPair(String text, int at) =>
    at > 0 &&
    at < text.length &&
    text.codeUnitAt(at) >= 0xDC00 &&
    text.codeUnitAt(at) <= 0xDFFF;
