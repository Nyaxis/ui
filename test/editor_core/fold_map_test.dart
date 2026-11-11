import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor_core/buffer.dart';
import 'package:ui/editor_core/display/fold_map.dart';
import 'package:ui/editor_core/display/inlay_map.dart';
import 'package:ui/editor_core/display/layer_edit.dart';
import 'package:ui/editor_core/patch.dart';
import 'package:ui/editor_core/point.dart';
import 'package:ui/editor_core/text_summary.dart';

import 'helpers.dart';

const _e = foldEllipsis;

String _applyEdits(String old, String now, List<LayerEdit> edits) {
  var text = old;
  for (final edit in edits.reversed) {
    text = text.replaceRange(
      edit.oldStart,
      edit.oldEnd,
      now.substring(edit.newStart, edit.newEnd),
    );
  }
  return text;
}

/// the buffer with its layers, kept together as the editor will keep them
class _Layers {
  _Layers(String text) : buffer = TextBuffer(text) {
    inlays = InlayMap(buffer.snapshot);
    folds = FoldMap(inlays.snapshot);
  }

  final TextBuffer buffer;
  late final InlayMap inlays;
  late final FoldMap folds;

  List<LayerEdit> edit(List<Replacement> replacements) {
    final bufferEdits = layerEditsFromPatch(buffer.edit(replacements));
    final (inlaySnapshot, inlayEdits) = inlays.sync(
      buffer.snapshot,
      bufferEdits,
    );
    return folds.read(inlaySnapshot, inlayEdits).$2;
  }

  List<LayerEdit> spliceInlays(List<int> remove, List<Inlay> insert) {
    final (inlaySnapshot, inlayEdits) = inlays.splice(remove, insert);
    return folds.read(inlaySnapshot, inlayEdits).$2;
  }
}

/// the ranges of the inlay layer that are folded, with the ones that are one
/// made one
List<(int, int)> _mergedFolds(_Layers layers) {
  final inlay = layers.inlays.snapshot;
  final buffer = layers.buffer;
  final ranges = [
    for (final fold in layers.folds.snapshot.folds)
      (
        inlay.toInlayOffset(buffer.offsetForAnchor(fold.range.start)),
        inlay.toInlayOffset(buffer.offsetForAnchor(fold.range.end)),
      ),
  ];
  final merged = <(int, int)>[];
  for (final range in ranges) {
    if (merged.isNotEmpty && range.$1 <= merged.last.$2) {
      if (range.$2 > merged.last.$2) {
        merged[merged.length - 1] = (merged.last.$1, range.$2);
      }
    } else {
      merged.add(range);
    }
  }
  return [
    for (final range in merged)
      if (range.$2 > range.$1) range,
  ];
}

void main() {
  group('FoldMap', () {
    test('a fold is shown as its placeholder', () {
      final layers = _Layers('aa\nbb\ncc\ndd\nee\nff');
      final (snapshot, edits) = layers.folds.fold([
        (4, 13, null),
        (15, 16, null),
      ]);
      // from the second `b` to the first `e`, and the first `f`
      expect(snapshot.text, 'aa\nb${_e}e\n${_e}f');
      expect(edits, const [LayerEdit(4, 13, 4, 5), LayerEdit(15, 16, 7, 8)]);
      expect(snapshot.maxPoint, const Point(2, 2));
      expect(snapshot.lineLen(1), 3);
      expect(snapshot.isLineFolded(1), isTrue);
      expect(snapshot.isLineFolded(0), isFalse);
      expect(snapshot.intersectsFold(6), isTrue);
      // a fold has its start in it, and not its end
      expect(snapshot.intersectsFold(4), isTrue);
      expect(snapshot.intersectsFold(3), isFalse);
      expect(snapshot.intersectsFold(13), isFalse);
    });

    test('an edit before a fold moves it, and one in it stays folded', () {
      final layers = _Layers('aa\nbb\ncc\ndd\nee\nff');
      layers.folds.fold([(4, 13, null)]);
      final edits = layers.edit([
        const Replacement.insert(0, '123'),
        const Replacement.insert(7, 'XY'),
      ]);
      expect(layers.folds.snapshot.text, '123aa\nb${_e}e\nff');
      expect(edits, const [LayerEdit(0, 0, 0, 3), LayerEdit(4, 5, 7, 8)]);
    });

    test('text typed at the edges of a fold is outside it', () {
      final layers = _Layers('0123456789');
      layers.folds.fold([(3, 6, null)]);
      layers.edit([const Replacement.insert(3, 'a')]);
      expect(layers.folds.snapshot.text, '012a${_e}6789');
      layers.edit([const Replacement.insert(7, 'b')]);
      expect(layers.folds.snapshot.text, '012a${_e}b6789');
    });

    test('folds that touch or overlap are shown as one', () {
      final layers = _Layers('0123456789');
      layers.folds.fold([
        (0, 2, null),
        (2, 4, null),
        (3, 6, null),
        (8, 9, null),
      ]);
      expect(layers.folds.snapshot.text, '${_e}67${_e}9');
    });

    test('unfolding takes out the folds that a range has any of', () {
      final layers = _Layers('0123456789');
      layers.folds.fold([(1, 3, null), (5, 8, null)]);
      expect(layers.folds.snapshot.text, '0${_e}34${_e}89');
      var (snapshot, edits) = layers.folds.unfoldIntersecting([(3, 5)]);
      expect(snapshot.text, '0${_e}34${_e}89');
      expect(edits, isEmpty);
      (snapshot, edits) = layers.folds.unfoldIntersecting([
        (3, 5),
      ], inclusive: true);
      expect(snapshot.text, '0123456789');
      expect(snapshot.hasFolds, isFalse);
    });

    test('points go between the layers, and to the edges of a fold', () {
      final layers = _Layers('aa\nbb\ncc\ndd');
      final (snapshot, _) = layers.folds.fold([
        (4, 10, const FoldPlaceholder(collapsedText: 'FOLD')),
      ]);
      expect(snapshot.text, 'aa\nbFOLDd');
      expect(
        snapshot.toFoldPoint(const Point(1, 1), Bias.left),
        const Point(1, 1),
      );
      expect(
        snapshot.toFoldPoint(const Point(2, 1), Bias.left),
        const Point(1, 1),
      );
      expect(
        snapshot.toFoldPoint(const Point(2, 1), Bias.right),
        const Point(1, 5),
      );
      expect(
        snapshot.toFoldPoint(const Point(3, 1), Bias.left),
        const Point(1, 5),
      );
      // the fold ends before the last `d`
      expect(snapshot.toInlayPoint(const Point(1, 5)), const Point(3, 1));
      expect(
        snapshot.clipPoint(const Point(1, 3), Bias.left),
        const Point(1, 1),
      );
      expect(
        snapshot.clipPoint(const Point(1, 3), Bias.right),
        const Point(1, 5),
      );
      expect(snapshot.placeholderRangeAt(const Point(1, 2)), (
        const Point(1, 1),
        const Point(1, 5),
      ));
      expect(snapshot.placeholderRangeAt(const Point(0, 1)), isNull);
    });

    test('random folds, inlays and edits give the text that is expected', () {
      const pieces = ['a', 'bc', '\n', ' ', 'word', '\n\n', 'x\ny', '😀'];
      for (var seed = 0; seed < 120; seed++) {
        final random = Random(seed);
        String randomText(int max) => List.generate(
          random.nextInt(max),
          (_) => pieces[random.nextInt(pieces.length)],
        ).join();

        final layers = _Layers(randomText(30));
        final buffer = layers.buffer;
        int offset() => buffer.text.clipOffset(
          random.nextInt(buffer.length + 1),
          Bias.left,
        );
        var nextInlay = 0;
        var shown = layers.folds.snapshot.text;
        for (var step = 0; step < 25; step++) {
          final List<LayerEdit> edits;
          switch (random.nextInt(5)) {
            case 0:
              final a = offset();
              final b = offset();
              edits = layers.edit([
                Replacement(min(a, b), max(a, b), randomText(4)),
              ]);
            case 1:
              final remove = <int>[];
              final insert = <Inlay>[];
              if (layers.inlays.inlays.isEmpty || random.nextBool()) {
                insert.add(
                  inlayAt(
                    buffer,
                    nextInlay++,
                    offset(),
                    randomText(3),
                    random.nextBool() ? Bias.left : Bias.right,
                  ),
                );
              } else {
                final all = layers.inlays.inlays;
                remove.add(all[random.nextInt(all.length)].id);
              }
              edits = layers.spliceInlays(remove, insert);
            case 2:
              final a = offset();
              final b = offset();
              edits = layers.folds.unfoldIntersecting([
                (min(a, b), max(a, b)),
              ], inclusive: random.nextBool()).$2;
            default:
              final ranges = <(int, int, FoldPlaceholder?)>[];
              for (var i = 0; i < 1 + random.nextInt(2); i++) {
                final a = offset();
                final b = offset();
                ranges.add((min(a, b), max(a, b), null));
              }
              edits = layers.folds.fold(ranges).$2;
          }

          final why = 'seed $seed step $step';
          final snapshot = layers.folds.snapshot;
          final inlay = layers.inlays.snapshot;
          final inlayText = inlay.text;
          final merged = _mergedFolds(layers);
          var expected = inlayText;
          for (final (start, end) in merged.reversed) {
            expected = expected.replaceRange(start, end, foldEllipsis);
          }
          expect(snapshot.text, expected, reason: why);
          expect(snapshot.len, expected.length, reason: why);
          expect(snapshot.textSummary, TextSummary.of(expected), reason: why);
          expect(_applyEdits(shown, expected, edits), expected, reason: why);
          shown = expected;

          // every place of this layer is found by point and by offset
          for (var at = 0; at <= expected.length; at++) {
            final point = snapshot.toPoint(at);
            expect(point, offsetToPointIn(expected, at), reason: '$why at $at');
            expect(snapshot.toOffset(point), at, reason: why);
          }
          for (var row = 0; row <= snapshot.maxPoint.row; row++) {
            expect(
              snapshot.lineLen(row),
              expected.split('\n')[row].length,
              reason: why,
            );
          }

          // the places of the layer below go up and come down again, but for
          // the ones inside a fold, which go to its edges
          var folded = 0;
          for (var at = 0; at <= inlayText.length; at++) {
            (int, int)? inFold;
            for (final range in merged) {
              if (range.$1 < at && at < range.$2) {
                inFold = range;
              }
            }
            final inlayPoint = inlay.toPoint(at);
            for (final bias in Bias.values) {
              final foldPoint = snapshot.toFoldPoint(inlayPoint, bias);
              final foldOffset = snapshot.toFoldOffset(at, bias);
              expect(
                snapshot.toPoint(foldOffset),
                foldPoint,
                reason: '$why at $at',
              );
              final back = snapshot.toInlayOffset(foldOffset);
              expect(
                inlay.toPoint(back),
                snapshot.toInlayPoint(foldPoint),
                reason: why,
              );
              if (inFold == null) {
                expect(back, at, reason: '$why at $at');
              } else {
                folded++;
                expect(
                  back,
                  bias == Bias.left ? inFold.$1 : inFold.$2,
                  reason: '$why at $at',
                );
              }
            }
          }
          expect(folded.isEven, isTrue);

          for (var offset = 0; offset <= buffer.length; offset++) {
            final at = inlay.toInlayOffset(offset);
            expect(
              snapshot.intersectsFold(offset),
              merged.any((r) => r.$1 <= at && at < r.$2),
              reason: '$why offset $offset',
            );
          }

          for (var i = 0; i < 8; i++) {
            final a = random.nextInt(expected.length + 1);
            final b = random.nextInt(expected.length + 1);
            final from = min(a, b);
            final to = max(a, b);
            expect(
              snapshot.textSummaryForRange(
                snapshot.toPoint(from),
                snapshot.toPoint(to),
              ),
              TextSummary.of(expected, from, to),
              reason: '$why range $from..$to',
            );
            expect(
              [for (final c in snapshot.chunks(from, to)) c.text].join(),
              expected.substring(from, to),
              reason: why,
            );
            for (final bias in Bias.values) {
              final clipped = snapshot.clipPoint(snapshot.toPoint(from), bias);
              expect(snapshot.clipPoint(clipped, bias), clipped, reason: why);
              expect(
                snapshot.placeholderRangeAt(clipped)?.$1,
                anyOf(isNull, clipped),
              );
            }
          }
        }
      }
    });
  });
}
