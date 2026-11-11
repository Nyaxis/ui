import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor_core/buffer.dart';
import 'package:ui/editor_core/display_map.dart';
import 'package:ui/editor_core/patch.dart';
import 'package:ui/editor_core/point.dart';

import 'helpers.dart';

const _e = foldEllipsis;

/// a layout made from nothing for what [map] shows, to compare with the one
/// that followed every change
DisplayMap _fresh(DisplayMap map) {
  final old = map.buffer.snapshot;
  final buffer = TextBuffer(old.text.toString());
  final fresh = DisplayMap(
    buffer,
    tabSize: map.tabSize,
    wrapWidth: map.wrapWidth,
  );
  fresh.spliceInlays([], [
    for (final (inlay, offset) in shownInlays(old, map.inlays))
      inlayAt(buffer, inlay.id, offset, inlay.text, inlay.bias),
  ]);
  fresh.fold([
    for (final fold in map.folds)
      (
        old.offsetForAnchor(fold.range.start),
        old.offsetForAnchor(fold.range.end),
        fold.placeholder,
      ),
  ]);
  return fresh;
}

void main() {
  group('DisplayMap', () {
    test('the layers are put on one another', () {
      final buffer = TextBuffer('fn main() {\n\tlet x = 1;\n\tlet y = 2;\n}\n');
      final map = DisplayMap(buffer, wrapWidth: 12);
      map.spliceInlays([], [inlayAt(buffer, 1, 18, ': i32')]);
      // from after the second `let` to before its `;`
      map.fold([(28, 34, null)]);
      final snapshot = map.snapshot;
      expect(
        snapshot.text,
        [
          'fn main() {',
          '    let x: ',
          '    i32 = 1;',
          '    let$_e;',
          '}',
          '',
        ].join('\n'),
      );
      expect(snapshot.rowCount, 6);
      expect(snapshot.rowText(2), '    i32 = 1;');
      expect(snapshot.rowInfo(2), (bufferRow: 1, softWrapped: true));
      expect(snapshot.softWrapIndent(2), 4);
      expect(snapshot.softWrapIndent(1), isNull);
      expect(snapshot.rowInfo(3), (bufferRow: 2, softWrapped: false));
      expect(snapshot.isLineFolded(2), isTrue);
      // the `=` of the first `let`, after the hint and on the wrapped row
      expect(snapshot.offsetToDisplayPoint(19), const Point(2, 8));
      expect(snapshot.displayPointToOffset(const Point(2, 8)), 19);
      // in the fold, a place goes to its edges
      expect(snapshot.offsetToDisplayPoint(30), const Point(3, 7));
      expect(snapshot.offsetToDisplayPoint(30, Bias.right), const Point(3, 8));
      expect(snapshot.intersectsFold(30), isTrue);
    });

    test('the edits of the buffer are taken when the layout is asked for', () {
      final buffer = TextBuffer('one\ntwo\nthree');
      final map = DisplayMap(buffer);
      final before = map.snapshot;
      buffer.edit([const Replacement.insert(4, 'new\n')]);
      buffer.edit([const Replacement.insert(0, 'x')]);
      expect(before.text, 'one\ntwo\nthree');
      expect(map.snapshot.text, 'xone\nnew\ntwo\nthree');
    });

    test('folds and inlays stay with their text through undo and redo', () {
      final buffer = TextBuffer('one two three four', Duration.zero);
      final map = DisplayMap(buffer);
      map.fold([(4, 13, null)]);
      map.spliceInlays([], [inlayAt(buffer, 1, 14, '>')]);
      expect(map.snapshot.text, 'one $_e >four');
      // the text of the fold and of the inlay is taken out, and put back
      buffer.edit([const Replacement(2, 16, '')]);
      expect(map.snapshot.text, 'onur');
      buffer.edit([const Replacement.insert(0, 'zero ')]);
      expect(map.snapshot.text, 'zero onur');
      buffer.undo();
      buffer.undo();
      expect(map.snapshot.text, 'one $_e >four');
      buffer.redo();
      expect(map.snapshot.text, 'onur');
    });

    test('the settings of the layout are changed', () {
      final buffer = TextBuffer('\tone two three');
      final map = DisplayMap(buffer);
      expect(map.snapshot.text, '    one two three');
      map.setTabSize(2);
      expect(map.snapshot.text, '  one two three');
      map.setWrapWidth(8);
      expect(map.snapshot.text, '  one \n  two \n  three');
      map.setSoftWrapIndent(const IndentAdjustment.noIndent());
      expect(map.snapshot.text, '  one \ntwo \nthree');
      map.setWrapWidth(null);
      expect(map.snapshot.text, '  one two three');
    });

    test('a layout that followed every change is one made from nothing', () {
      const pieces = [
        'a',
        'bc',
        '\n',
        ' ',
        ' ',
        '\t',
        'word ',
        '\n  ',
        '日',
        '😀',
      ];
      for (var seed = 0; seed < 100; seed++) {
        final random = Random(seed);
        String randomText(int max) => List.generate(
          random.nextInt(max),
          (_) => pieces[random.nextInt(pieces.length)],
        ).join();

        final buffer = TextBuffer(randomText(50));
        final map = DisplayMap(
          buffer,
          tabSize: 1 + random.nextInt(6),
          wrapWidth: random.nextBool() ? null : 4.0 + random.nextInt(16),
        );
        int offset() => buffer.text.clipOffset(
          random.nextInt(buffer.length + 1),
          Bias.left,
        );
        var nextInlay = 0;
        for (var step = 0; step < 25; step++) {
          switch (random.nextInt(9)) {
            case 0:
            case 1:
            case 2:
              final a = offset();
              final b = offset();
              buffer.finalizeLastTransaction();
              buffer.edit([Replacement(min(a, b), max(a, b), randomText(5))]);
            case 3:
              if (random.nextBool()) {
                buffer.undo();
              } else {
                buffer.redo();
              }
            case 4:
              final all = map.inlays;
              map.spliceInlays(
                [if (all.isNotEmpty) all[random.nextInt(all.length)].id],
                [
                  inlayAt(
                    buffer,
                    nextInlay++,
                    offset(),
                    randomText(3),
                    random.nextBool() ? Bias.left : Bias.right,
                  ),
                ],
              );
            case 5:
              map.setWrapWidth(
                random.nextInt(4) == 0 ? null : 4.0 + random.nextInt(16),
              );
            case 6:
              map.setTabSize(1 + random.nextInt(6));
            case 7:
              final a = offset();
              final b = offset();
              map.unfold([
                (min(a, b), max(a, b)),
              ], inclusive: random.nextBool());
            default:
              final a = offset();
              final b = offset();
              map.fold([(min(a, b), max(a, b), null)]);
          }

          final why = 'seed $seed step $step';
          final snapshot = map.snapshot;
          final text = snapshot.text;
          final fresh = _fresh(map).snapshot;
          expect(text, fresh.text, reason: why);
          expect(snapshot.maxPoint, fresh.maxPoint, reason: why);

          final rows = text.split('\n');
          for (var row = 0; row < rows.length; row++) {
            expect(snapshot.rowText(row), rows[row], reason: '$why row $row');
            expect(snapshot.lineLen(row), rows[row].length, reason: why);
            expect(snapshot.rowInfo(row), fresh.rowInfo(row), reason: why);
          }
          for (var at = 0; at <= buffer.length; at++) {
            if (buffer.text.clipOffset(at, Bias.left) != at) {
              continue;
            }
            for (final bias in Bias.values) {
              final point = snapshot.offsetToDisplayPoint(at, bias);
              expect(point, fresh.offsetToDisplayPoint(at, bias), reason: why);
              expect(point.row, lessThan(rows.length), reason: why);
              expect(
                point.column,
                lessThanOrEqualTo(rows[point.row].length),
                reason: '$why at $at',
              );
              if (!snapshot.intersectsFold(at)) {
                expect(
                  snapshot.displayPointToOffset(point, bias),
                  at,
                  reason: '$why at $at $bias',
                );
              }
              expect(
                snapshot.clipPoint(point, bias),
                point,
                reason: '$why at $at',
              );
            }
          }
        }
      }
    });

    test('a big text is edited without laying it all out again', () async {
      final text = List.generate(100000, (i) => 'line number $i\n').join();
      final buffer = TextBuffer(text);
      final map = DisplayMap(buffer, wrapWidth: 12);
      final random = Random(2);
      // so many rows are wrapped in the background, and are shown as they
      // are until that is done
      expect(map.isRewrapping, isTrue);
      expect(map.snapshot.rowCount, 100001);
      var told = 0;
      map.addListener(() => told++);
      while (map.isRewrapping) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(told, 1);
      expect(map.snapshot.rowCount, greaterThan(100001));
      final timer = Stopwatch()..start();
      for (var i = 0; i < 1500; i++) {
        final at = random.nextInt(buffer.length);
        buffer.edit([Replacement.insert(at, i.isEven ? 'xx ' : '\n')]);
        final snapshot = map.snapshot;
        snapshot.offsetToDisplayPoint(random.nextInt(buffer.length));
        snapshot.rowText(random.nextInt(snapshot.rowCount));
      }
      expect(timer.elapsed.inSeconds, lessThan(15));
      while (map.isRewrapping) {
        await Future<void>.delayed(Duration.zero);
      }
      final fresh = DisplayMap(
        TextBuffer(buffer.text.toString()),
        wrapWidth: 12,
      );
      while (fresh.isRewrapping) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(map.snapshot.text, fresh.snapshot.text);
      map.dispose();
      fresh.dispose();
    });
  });
}
