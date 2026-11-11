import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor_core/buffer.dart';
import 'package:ui/editor_core/display/inlay_map.dart';
import 'package:ui/editor_core/display/layer_edit.dart';
import 'package:ui/editor_core/patch.dart';
import 'package:ui/editor_core/point.dart';
import 'package:ui/editor_core/text_summary.dart';

import 'helpers.dart';

/// the text that is to be shown for [text] with [inlays], which are in the
/// order they are shown in
String _expected(String text, List<(Inlay, int)> inlays) {
  final out = StringBuffer();
  var at = 0;
  for (final (inlay, offset) in inlays) {
    out.write(text.substring(at, offset));
    out.write(inlay.text);
    at = offset;
  }
  out.write(text.substring(at));
  return out.toString();
}

/// [old] with what [edits] say changed taken from [now]
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

void main() {
  group('InlayMap', () {
    test('without inlays the text is the text of the buffer', () {
      final buffer = TextBuffer('one\ntwo');
      final map = InlayMap(buffer.snapshot);
      expect(map.snapshot.text, 'one\ntwo');
      expect(map.snapshot.len, 7);
      expect(map.snapshot.maxPoint, const Point(1, 3));
      expect(map.snapshot.toInlayOffset(5), 5);
      expect(map.snapshot.toBufferOffset(5), 5);
    });

    test(
      'inlays are shown in the text, and the places around them are found',
      () {
        final buffer = TextBuffer('abcdefghi');
        final map = InlayMap(buffer.snapshot);
        final (snapshot, edits) = map.splice([], [
          inlayAt(buffer, 1, 3, '|123|', Bias.right),
        ]);
        expect(snapshot.text, 'abc|123|defghi');
        expect(edits, const [LayerEdit(3, 3, 3, 8)]);
        expect(snapshot.toInlayOffset(0), 0);
        // text typed at an inlay of this side goes before it
        expect(snapshot.toInlayOffset(3), 3);
        expect(snapshot.toInlayOffset(4), 9);
        expect(snapshot.toBufferOffset(3), 3);
        expect(snapshot.toBufferOffset(5), 3);
        expect(snapshot.toBufferOffset(8), 3);
        expect(snapshot.toBufferOffset(9), 4);
        expect(snapshot.toInlayPoint(const Point(0, 4)), const Point(0, 9));
        expect(snapshot.toBufferPoint(const Point(0, 6)), const Point(0, 3));
        expect(
          snapshot.clipPoint(const Point(0, 5), Bias.left),
          const Point(0, 3),
        );
        expect(
          snapshot.clipPoint(const Point(0, 5), Bias.right),
          const Point(0, 9),
        );
        expect(
          snapshot.clipPoint(const Point(0, 8), Bias.right),
          const Point(0, 9),
        );
      },
    );

    test('an inlay of the other side has text typed at it after it', () {
      final buffer = TextBuffer('abcdefghi');
      final map = InlayMap(buffer.snapshot);
      final (snapshot, _) = map.splice([], [inlayAt(buffer, 1, 3, '|123|')]);
      expect(snapshot.toInlayOffset(3), 8);
      expect(
        snapshot.clipPoint(const Point(0, 3), Bias.left),
        const Point(0, 2),
      );
      expect(
        snapshot.clipPoint(const Point(0, 3), Bias.right),
        const Point(0, 8),
      );
      expect(
        snapshot.clipPoint(const Point(0, 8), Bias.left),
        const Point(0, 8),
      );
    });

    test('text typed at an inlay goes on the side the inlay says', () {
      final buffer = TextBuffer('abcdef');
      final map = InlayMap(buffer.snapshot);
      map.splice([], [
        inlayAt(buffer, 1, 3, '<L>'),
        inlayAt(buffer, 2, 3, '<R>', Bias.right),
      ]);
      expect(map.snapshot.text, 'abc<L><R>def');
      final patch = buffer.edit([const Replacement.insert(3, 'XY')]);
      final (snapshot, edits) = map.sync(
        buffer.snapshot,
        layerEditsFromPatch(patch),
      );
      expect(snapshot.text, 'abc<L>XY<R>def');
      expect(_applyEdits('abc<L><R>def', snapshot.text, edits), snapshot.text);
    });

    test(
      'inlays are taken out by their ids, and one of no text is not kept',
      () {
        final buffer = TextBuffer('abc\ndef');
        final map = InlayMap(buffer.snapshot);
        map.splice([], [
          inlayAt(buffer, 1, 1, 'X'),
          inlayAt(buffer, 2, 5, 'Y\nZ'),
          inlayAt(buffer, 3, 2, ''),
        ]);
        expect(map.snapshot.text, 'aXbc\ndY\nZef');
        expect(map.inlays.length, 2);
        expect(map.snapshot.maxPoint, const Point(2, 3));
        expect(map.snapshot.lineLen(1), 2);
        final (snapshot, edits) = map.splice([2], []);
        expect(snapshot.text, 'aXbc\ndef');
        expect(edits, const [LayerEdit(6, 9, 6, 6)]);
      },
    );

    test('an inlay in text that is taken out is not shown until the text is '
        'put back', () {
      final buffer = TextBuffer('abcdefgh');
      final subscription = buffer.subscribe();
      final map = InlayMap(buffer.snapshot);
      map.splice([], [inlayAt(buffer, 1, 4, '!')]);
      expect(map.snapshot.text, 'abcd!efgh');
      buffer.edit([const Replacement(2, 6, '')]);
      var (snapshot, _) = map.sync(
        buffer.snapshot,
        subscription.consume().edits,
      );
      expect(snapshot.text, 'abgh');
      expect(map.inlays, hasLength(1));
      buffer.undo();
      (snapshot, _) = map.sync(buffer.snapshot, subscription.consume().edits);
      expect(snapshot.text, 'abcd!efgh');
    });

    test('random inlays and edits give the text that is expected', () {
      const pieces = ['a', 'bc', '\n', ' ', 'word', '\n\n', 'x\ny', '😀'];
      for (var seed = 0; seed < 120; seed++) {
        final random = Random(seed);
        String randomText(int max) => List.generate(
          random.nextInt(max),
          (_) => pieces[random.nextInt(pieces.length)],
        ).join();

        final buffer = TextBuffer(randomText(30));
        final map = InlayMap(buffer.snapshot);
        var nextId = 0;
        var shown = map.snapshot.text;
        for (var step = 0; step < 25; step++) {
          final List<LayerEdit> edits;
          if (random.nextInt(3) == 0) {
            final now = buffer.text.toString();
            final a = buffer.text.clipOffset(
              random.nextInt(now.length + 1),
              Bias.left,
            );
            final b = buffer.text.clipOffset(
              random.nextInt(now.length + 1),
              Bias.left,
            );
            final patch = buffer.edit([
              Replacement(min(a, b), max(a, b), randomText(4)),
            ]);
            edits = map.sync(buffer.snapshot, layerEditsFromPatch(patch)).$2;
          } else {
            final remove = <int>[];
            final insert = <Inlay>[];
            for (var i = 0; i < 1 + random.nextInt(4); i++) {
              if (map.inlays.isEmpty || random.nextBool()) {
                insert.add(
                  inlayAt(
                    buffer,
                    nextId++,
                    buffer.text.clipOffset(
                      random.nextInt(buffer.length + 1),
                      Bias.left,
                    ),
                    randomText(4),
                    random.nextBool() ? Bias.left : Bias.right,
                  ),
                );
              } else {
                remove.add(map.inlays[random.nextInt(map.inlays.length)].id);
              }
            }
            edits = map.splice(remove, insert).$2;
          }

          final snapshot = map.snapshot;
          final text = buffer.text.toString();
          final inlays = shownInlays(buffer.snapshot, map.inlays);
          final why = 'seed $seed step $step';
          for (var i = 0; i < inlays.length; i++) {
            expect(inlays[i].$2, inInclusiveRange(0, text.length), reason: why);
            if (i > 0) {
              expect(
                inlays[i].$2,
                greaterThanOrEqualTo(inlays[i - 1].$2),
                reason: why,
              );
            }
          }
          final expected = _expected(text, inlays);
          expect(snapshot.text, expected, reason: why);
          expect(snapshot.len, expected.length, reason: why);
          expect(snapshot.textSummary, TextSummary.of(expected), reason: why);
          expect(_applyEdits(shown, expected, edits), expected, reason: why);
          shown = expected;

          // the places of the buffer and of the inlays go to each other
          for (var offset = 0; offset <= text.length; offset++) {
            var want = offset;
            for (final (inlay, at) in inlays) {
              if (at < offset || (at == offset && inlay.bias == Bias.left)) {
                want += inlay.text.length;
              }
            }
            final inlayOffset = snapshot.toInlayOffset(offset);
            expect(inlayOffset, want, reason: '$why offset $offset');
            expect(snapshot.toBufferOffset(inlayOffset), offset, reason: why);
            final bufferPoint = buffer.text.offsetToPoint(offset);
            final inlayPoint = snapshot.toInlayPoint(bufferPoint);
            expect(inlayPoint, snapshot.toPoint(inlayOffset), reason: why);
            expect(
              snapshot.toBufferPoint(inlayPoint),
              bufferPoint,
              reason: why,
            );
          }
          for (var offset = 0; offset <= expected.length; offset++) {
            final point = snapshot.toPoint(offset);
            expect(point, offsetToPointIn(expected, offset), reason: why);
            expect(snapshot.toOffset(point), offset, reason: why);
          }
          for (var row = 0; row <= snapshot.maxPoint.row; row++) {
            expect(
              snapshot.lineLen(row),
              expected.split('\n')[row].length,
              reason: why,
            );
          }
          for (var i = 0; i < 8; i++) {
            final a = random.nextInt(expected.length + 1);
            final b = random.nextInt(expected.length + 1);
            expect(
              snapshot.textSummaryForRange(min(a, b), max(a, b)),
              TextSummary.of(expected, min(a, b), max(a, b)),
              reason: '$why range ${min(a, b)}..${max(a, b)}',
            );
            expect(
              [for (final c in snapshot.chunks(min(a, b), max(a, b))) c.text]
                  .join(),
              expected.substring(min(a, b), max(a, b)),
              reason: why,
            );
          }

          // a clipped point is a place of the buffer, and stays where it is
          for (var i = 0; i < 8; i++) {
            final point = snapshot.toPoint(random.nextInt(expected.length + 1));
            for (final bias in Bias.values) {
              final clipped = snapshot.clipPoint(point, bias);
              expect(snapshot.clipPoint(clipped, bias), clipped, reason: why);
              final back = snapshot.toInlayPoint(
                snapshot.toBufferPoint(clipped),
              );
              expect(
                snapshot.toBufferPoint(back),
                snapshot.toBufferPoint(clipped),
                reason: why,
              );
            }
          }
        }
      }
    });
  });
}
