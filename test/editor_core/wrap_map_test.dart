import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor_core/buffer.dart';
import 'package:ui/editor_core/display/fold_map.dart';
import 'package:ui/editor_core/display/inlay_map.dart';
import 'package:ui/editor_core/display/layer_edit.dart';
import 'package:ui/editor_core/display/line_wrapper.dart';
import 'package:ui/editor_core/display/tab_map.dart';
import 'package:ui/editor_core/display/wrap_map.dart';
import 'package:ui/editor_core/patch.dart';
import 'package:ui/editor_core/point.dart';
import 'package:ui/editor_core/text_metrics.dart';
import 'package:ui/editor_core/text_summary.dart';

import 'helpers.dart';

/// [text] wrapped a line at a time, without anything of the wrap layer but
/// the wrapper of lines
String _wrap(String text, double? width, IndentAdjustment indent) {
  if (width == null) {
    return text;
  }
  final wrapper = LineWrapper(const CellMetrics());
  final out = StringBuffer();
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = i < lines.length - 1 ? '${lines[i]}\n' : lines[i];
    var previous = 0;
    for (final boundary in wrapper.wrapLine(line, width, indent)) {
      out.write(line.substring(previous, boundary.ix));
      out.write('\n${' ' * boundary.nextIndent}');
      previous = boundary.ix;
    }
    out.write(line.substring(previous));
  }
  return out.toString();
}

class _Layers {
  /// with [background], no wrapping is done at once: all of it goes on in
  /// the background, a row at a time
  _Layers(
    String text,
    this.tabSize,
    double? wrapWidth,
    this.indent, {
    bool background = false,
  }) : buffer = TextBuffer(text) {
    inlays = InlayMap(buffer.snapshot);
    folds = FoldMap(inlays.snapshot);
    tabs = TabMap(folds.snapshot, tabSize);
    wraps = background
        ? WrapMap(
            tabs.snapshot,
            wrapWidth: wrapWidth,
            softWrapIndent: indent,
            rewrapBudget: Duration.zero,
            flushBudget: Duration.zero,
            yieldRowInterval: 1,
          )
        : WrapMap(tabs.snapshot, wrapWidth: wrapWidth, softWrapIndent: indent);
  }

  /// the rows that changed since they were last asked for
  List<RowEdit> flush() => wraps.sync(tabs.snapshot, const []).$2;

  /// waits for the rows that are being wrapped in the background
  Future<void> settle() async {
    while (wraps.isRewrapping) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  final TextBuffer buffer;
  int tabSize;
  final IndentAdjustment indent;
  late final InlayMap inlays;
  late final FoldMap folds;
  late final TabMap tabs;
  late final WrapMap wraps;

  List<RowEdit> edit(List<Replacement> replacements) {
    final bufferEdits = layerEditsFromPatch(buffer.edit(replacements));
    final (inlaySnapshot, inlayEdits) = inlays.sync(
      buffer.snapshot,
      bufferEdits,
    );
    return afterFolds(folds.read(inlaySnapshot, inlayEdits));
  }

  List<RowEdit> afterFolds((FoldSnapshot, List<LayerEdit>) result) {
    final (tabSnapshot, tabEdits) = tabs.sync(result.$1, result.$2, tabSize);
    return wraps.sync(tabSnapshot, tabEdits).$2;
  }

  List<RowEdit> spliceInlays(List<int> remove, List<Inlay> insert) {
    final (inlaySnapshot, inlayEdits) = inlays.splice(remove, insert);
    return afterFolds(folds.read(inlaySnapshot, inlayEdits));
  }
}

String _applyRowEdits(String old, String now, List<RowEdit> edits) {
  final rows = old.split('\n');
  final newRows = now.split('\n');
  for (final edit in edits.reversed) {
    rows.replaceRange(
      edit.oldStart,
      min(edit.oldEnd, rows.length),
      newRows.sublist(edit.newStart, min(edit.newEnd, newRows.length)),
    );
  }
  return rows.join('\n');
}

void main() {
  const same = IndentAdjustment.sameIndent();

  group('LineWrapper', () {
    final wrapper = LineWrapper(const CellMetrics());

    test('a line breaks after the last space that fits', () {
      expect(wrapper.wrapLine('aa bbb cccc ddddd eeee', 9), const [
        Boundary(7, 0),
        Boundary(12, 0),
        Boundary(18, 0),
      ]);
    });

    test('a word that is too long breaks where it is too wide', () {
      expect(wrapper.wrapLine('aaa aaaaaaaaaaaaaaaaaa', 9), const [
        Boundary(4, 0),
        Boundary(13, 0),
      ]);
    });

    test('the rows that are continued on keep the indent of the line', () {
      expect(wrapper.wrapLine('     aaaaaaa', 9), const [Boundary(9, 5)]);
      expect(
        wrapper.wrapLine('     aaaaaaa', 9, const IndentAdjustment.noIndent()),
        const [Boundary(9, 0), Boundary(18, 0)].sublist(0, 1),
      );
    });

    test('more indent is added when asked, while there is room for it', () {
      expect(
        wrapper.wrapLine(
          '  aaaa bbbb cccc',
          10,
          const IndentAdjustment.extraColumns(2),
        ),
        const [Boundary(7, 4), Boundary(12, 4)],
      );
      // no room for the indent and what is carried over
      expect(
        wrapper
            .wrapLine(
              '      aaaaaaaa',
              9,
              const IndentAdjustment.extraColumns(4),
            )
            .first
            .nextIndent,
        0,
      );
    });

    test('a line that fits does not break, and its newline is not counted', () {
      expect(wrapper.wrapLine('aaaaaaaaa\n', 9), isEmpty);
      expect(wrapper.wrapLine('', 9), isEmpty);
    });

    test('East Asian text breaks between characters, each two cells wide', () {
      expect(wrapper.wrapLine('日本語日本語', 6), const [Boundary(3, 0)]);
    });

    test('a character and the mark on it stay on one row', () {
      final boundaries = wrapper.wrapLine('aaaaéé', 5);
      for (final boundary in boundaries) {
        expect('aaaaéé'.codeUnitAt(boundary.ix), isNot(0x0301));
      }
    });
  });

  group('WrapMap', () {
    test('lines that are too wide are broken into rows', () {
      final layers = _Layers('aa bbb cccc\nx', 4, 6, same);
      final snapshot = layers.wraps.snapshot;
      expect(snapshot.text, 'aa \nbbb \ncccc\nx');
      expect(snapshot.maxPoint, const Point(3, 1));
      expect(snapshot.lineLen(1), 4);
      // asked of a row, it answers for the row after it
      expect(snapshot.softWrapIndent(0), 0);
      expect(snapshot.softWrapIndent(2), isNull);
      expect(snapshot.isSoftWrapped(0), isFalse);
      expect(snapshot.isSoftWrapped(1), isTrue);
      expect(snapshot.rowInfo(2), (bufferRow: 0, softWrapped: true));
      expect(snapshot.rowInfo(3), (bufferRow: 1, softWrapped: false));
      expect(
        snapshot.tabPointToWrapPoint(const Point(0, 8)),
        const Point(2, 1),
      );
      expect(snapshot.toTabPoint(const Point(2, 1)), const Point(0, 8));
      expect(
        snapshot.makeWrapPoint(const Point(1, 1), Bias.left),
        const Point(3, 1),
      );
    });

    test('a row that continues an indented line has its indent', () {
      final layers = _Layers('  aaa bbb ccc', 4, 8, same);
      final snapshot = layers.wraps.snapshot;
      expect(snapshot.text, '  aaa \n  bbb \n  ccc');
      expect(snapshot.softWrapIndent(0), 2);
      // a place in the indent is one before the end of the row before, or
      // the first character after the indent
      expect(
        snapshot.clipPoint(const Point(1, 1), Bias.left),
        const Point(0, 5),
      );
      expect(
        snapshot.clipPoint(const Point(1, 1), Bias.right),
        const Point(1, 2),
      );
      expect(snapshot.toTabPoint(const Point(1, 2)), const Point(0, 6));
    });

    test('without a width nothing wraps', () {
      final layers = _Layers('aa bbb cccc\nx', 4, null, same);
      expect(layers.wraps.snapshot.text, 'aa bbb cccc\nx');
      expect(layers.wraps.setWrapWidth(6), isTrue);
      expect(layers.wraps.setWrapWidth(6), isFalse);
      expect(layers.wraps.snapshot.text, 'aa \nbbb \ncccc\nx');
      expect(layers.flush(), const [RowEdit(0, 2, 0, 4)]);
      layers.wraps.setWrapWidth(null);
      expect(layers.wraps.snapshot.text, 'aa bbb cccc\nx');
      expect(layers.flush(), const [RowEdit(0, 4, 0, 2)]);
    });

    test('rows wrapped in the background are shown unwrapped until they are '
        'done', () async {
      final layers = _Layers('aa bbb cccc\nx', 4, 6, same, background: true);
      final wraps = layers.wraps;
      expect(wraps.isRewrapping, isTrue);
      expect(wraps.snapshot.interpolated, isTrue);
      expect(wraps.snapshot.text, 'aa bbb cccc\nx');

      // an edit made meanwhile is shown at once, as it is
      var told = 0;
      wraps.addListener(() => told++);
      final edits = layers.edit([const Replacement.insert(0, 'zz ')]);
      expect(wraps.snapshot.text, 'zz aa bbb cccc\nx');
      expect(edits, const [RowEdit(0, 1, 0, 1)]);

      await layers.settle();
      expect(told, greaterThan(0));
      expect(wraps.snapshot.interpolated, isFalse);
      expect(wraps.snapshot.text, 'zz aa \nbbb \ncccc\nx');
      // all of the text was being wrapped, so all of its rows changed
      expect(layers.flush(), const [RowEdit(0, 2, 0, 4)]);
    });

    test(
      'changing the width stops what was being wrapped to the old one',
      () async {
        final layers = _Layers('aa bbb cccc', 4, 6, same, background: true);
        layers.wraps.setWrapWidth(4);
        await layers.settle();
        expect(layers.wraps.snapshot.text, 'aa \nbbb \ncccc');
        layers.wraps.setWrapWidth(null);
        expect(layers.wraps.isRewrapping, isFalse);
        expect(layers.wraps.snapshot.text, 'aa bbb cccc');
      },
    );

    test('only the lines that are edited are wrapped again', () {
      final layers = _Layers('aaa bbb\nccc ddd\neee fff', 4, 5, same);
      expect(layers.wraps.snapshot.text, 'aaa \nbbb\nccc \nddd\neee \nfff');
      final edits = layers.edit([const Replacement.insert(8, 'zz ')]);
      expect(
        layers.wraps.snapshot.text,
        'aaa \nbbb\nzz \nccc \nddd\neee \nfff',
      );
      expect(edits, const [RowEdit(2, 4, 2, 5)]);
    });

    test('the rows that start a line are found from any row', () {
      final layers = _Layers('aaa bbb ccc\nddd eee\nf', 4, 5, same);
      final snapshot = layers.wraps.snapshot;
      expect(snapshot.text, 'aaa \nbbb \nccc\nddd \neee\nf');
      // a boundary is only found where a run of unwrapped text starts a line,
      // so none may be found, and one that is found starts a line
      expect(snapshot.nextRowBoundary(const Point(5, 0)), isNull);
      for (var row = 0; row <= 5; row++) {
        expect(snapshot.prevRowBoundary(Point(row, 0)), lessThanOrEqualTo(row));
        final next = snapshot.nextRowBoundary(Point(row, 0));
        if (next != null) {
          expect(next, greaterThan(row));
          expect(snapshot.isSoftWrapped(next), isFalse);
        }
      }
    });

    test(
      'random text wraps as expected, through every kind of change',
      () async {
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
          'long-ish',
        ];
        for (var seed = 0; seed < 120; seed++) {
          final random = Random(seed);
          String randomText(int max) => List.generate(
            random.nextInt(max),
            (_) => pieces[random.nextInt(pieces.length)],
          ).join();

          final indent = switch (random.nextInt(3)) {
            0 => const IndentAdjustment.noIndent(),
            1 => same,
            _ => IndentAdjustment.extraColumns(1 + random.nextInt(3)),
          };
          double? width = random.nextInt(5) == 0
              ? null
              : 4.0 + random.nextInt(16);
          final layers = _Layers(
            randomText(50),
            1 + random.nextInt(6),
            width,
            indent,
            background: seed.isOdd,
          );
          final buffer = layers.buffer;
          int offset() => buffer.text.clipOffset(
            random.nextInt(buffer.length + 1),
            Bias.left,
          );
          var nextInlay = 0;
          var shown = layers.wraps.snapshot.text;
          for (var step = 0; step < 20; step++) {
            final List<RowEdit> edits;
            switch (random.nextInt(7)) {
              case 0:
              case 1:
              case 2:
                final a = offset();
                final b = offset();
                final replacements = [
                  Replacement(min(a, b), max(a, b), randomText(5)),
                ];
                if (random.nextBool() && min(a, b) > 2) {
                  replacements.add(Replacement.insert(0, randomText(3)));
                }
                edits = layers.edit(replacements);
              case 3:
                edits = layers.spliceInlays([], [
                  inlayAt(buffer, nextInlay++, offset(), randomText(3)),
                ]);
              case 4:
                width = random.nextInt(4) == 0
                    ? null
                    : 4.0 + random.nextInt(16);
                layers.wraps.setWrapWidth(width);
                edits = layers.flush();
              case 5:
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

            final why = 'seed $seed step $step width $width';
            // whatever is shown, wrapped or not yet, is what was shown with
            // the rows that are said to have changed
            var snapshot = layers.wraps.snapshot;
            expect(
              _applyRowEdits(shown, snapshot.text, edits),
              snapshot.text,
              reason: why,
            );
            shown = snapshot.text;
            if (layers.wraps.isRewrapping &&
                (step == 19 || random.nextBool())) {
              await layers.settle();
              final more = layers.flush();
              snapshot = layers.wraps.snapshot;
              expect(
                _applyRowEdits(shown, snapshot.text, more),
                snapshot.text,
                reason: '$why settled',
              );
              shown = snapshot.text;
            }
            if (layers.wraps.isRewrapping) {
              continue;
            }

            final tab = layers.tabs.snapshot;
            final tabText = tab.text;
            final expected = _wrap(tabText, width, indent);
            expect(snapshot.text, expected, reason: why);
            expect(
              snapshot.maxPoint,
              TextSummary.of(expected).lines,
              reason: why,
            );

            final rows = expected.split('\n');
            for (var row = 0; row < rows.length; row++) {
              expect(
                snapshot.lineLen(row),
                rows[row].length,
                reason: '$why row $row',
              );
              final boundary = snapshot.prevRowBoundary(Point(row, 0));
              expect(boundary, lessThanOrEqualTo(row), reason: why);
              final next = snapshot.nextRowBoundary(Point(row, 0));
              if (next != null) {
                expect(next, greaterThan(row), reason: why);
                expect(snapshot.isSoftWrapped(next), isFalse, reason: why);
              }
            }
            // the longest row is that of the text before its tabs were
            // expanded, so it is the longest row shown only without tabs
            if (!layers.folds.snapshot.text.contains('\t')) {
              expect(
                rows[snapshot.longestRow].length,
                rows.map((r) => r.length).reduce(max),
                reason: why,
              );
            }

            // every place of the tab layer has a row, and comes back from it
            for (var at = 0; at <= tabText.length; at++) {
              if (at < tabText.length &&
                  tabText.codeUnitAt(at) >= 0xDC00 &&
                  tabText.codeUnitAt(at) <= 0xDFFF) {
                continue;
              }
              final tabPoint = offsetToPointIn(tabText, at);
              final wrapPoint = snapshot.tabPointToWrapPoint(tabPoint);
              expect(
                snapshot.toTabPoint(wrapPoint),
                tabPoint,
                reason: '$why at $at',
              );
              expect(
                wrapPoint.column,
                lessThanOrEqualTo(rows[wrapPoint.row].length),
                reason: why,
              );
            }

            for (var i = 0; i < 6; i++) {
              final a = random.nextInt(rows.length + 1);
              final b = random.nextInt(rows.length + 1);
              final from = min(a, b);
              final to = max(a, b);
              final start = Point(from, 0);
              final end = to >= rows.length ? snapshot.maxPoint : Point(to, 0);
              final want = to >= rows.length
                  ? rows.sublist(from).join('\n')
                  : rows.sublist(from, to).map((r) => '$r\n').join();
              expect(
                [for (final c in snapshot.chunks(start, end)) c.text].join(),
                want,
                reason: '$why rows $from..$to',
              );
              final lastRow = rows.length - 1;
              final summary = snapshot.textSummaryForRange(
                min(from, lastRow),
                min(to, lastRow),
              );
              expect(
                summary.lines.row,
                min(to, lastRow) - min(from, lastRow),
                reason: why,
              );
              for (final bias in Bias.values) {
                final point = Point(
                  random.nextInt(rows.length),
                  random.nextInt(12),
                );
                final clipped = snapshot.clipPoint(point, bias);
                expect(
                  snapshot.clipPoint(clipped, bias),
                  clipped,
                  reason: '$why $point',
                );
                expect(
                  clipped.column,
                  lessThanOrEqualTo(rows[clipped.row].length),
                  reason: why,
                );
              }
            }
          }
        }
      },
    );
  });
}
