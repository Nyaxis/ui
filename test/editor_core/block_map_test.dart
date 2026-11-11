import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor_core/buffer.dart';
import 'package:ui/editor_core/display_map.dart';
import 'package:ui/editor_core/patch.dart';
import 'package:ui/editor_core/point.dart';

BlockProperties _above(TextBuffer buffer, int offset, int height) =>
    BlockProperties(
      placement: BlockPlacement.above(buffer.anchorAfter(offset)),
      height: height,
    );

BlockProperties _below(TextBuffer buffer, int offset, int height) =>
    BlockProperties(
      placement: BlockPlacement.below(buffer.anchorAfter(offset)),
      height: height,
    );

BlockProperties _replace(TextBuffer buffer, int start, int end, int height) =>
    BlockProperties(
      placement: BlockPlacement.replace(
        buffer.anchorAfter(start),
        buffer.anchorAfter(end),
      ),
      height: height,
    );

/// the text, and the blocks in it, that the layout is to have: a line of the
/// wrapped text at a time, with rows of nothing for the blocks
class _Expected {
  _Expected(this.rows, this.blockRows, this.wrapRowToRow);

  /// the text of each row
  final List<String> rows;

  /// the rows that are blocks
  final Set<int> blockRows;

  /// the row that each row of the wrap layer is on, or null if it is replaced
  final List<int?> wrapRowToRow;
}

_Expected _expected(DisplayMap map, List<CustomBlock> blocks) {
  final snapshot = map.snapshot;
  final wrap = snapshot.wrapSnapshot;
  final buffer = snapshot.bufferSnapshot;
  final wrapLines = wrap.text.split('\n');

  int rowOf(Point point, {required bool end}) => wrap
      .makeWrapPoint(
        Point(point.row, end ? buffer.text.lineLength(point.row) : 0),
        Bias.left,
      )
      .row;

  // where each block is, in rows of the wrap layer
  final placed = <(BlockPlacementKind, int, int, CustomBlock)>[];
  for (final block in blocks) {
    final start = buffer.pointForAnchor(block.placement.start);
    final end = buffer.pointForAnchor(block.placement.end);
    switch (block.placement.kind) {
      case BlockPlacementKind.above:
        placed.add((block.placement.kind, rowOf(start, end: false), 0, block));
      case BlockPlacementKind.below:
      case BlockPlacementKind.near:
        placed.add((block.placement.kind, rowOf(start, end: true), 0, block));
      case BlockPlacementKind.replace:
        if (start != end) {
          placed.add((
            block.placement.kind,
            rowOf(start, end: false),
            rowOf(end, end: true),
            block,
          ));
        }
    }
  }

  // replacements that touch are one, and cover what is in them
  final replaces =
      placed.where((p) => p.$1 == BlockPlacementKind.replace).toList()
        ..sort((a, b) {
          final c = a.$2.compareTo(b.$2);
          if (c != 0) {
            return c;
          }
          final d = b.$3.compareTo(a.$3);
          return d != 0 ? d : a.$4.id.compareTo(b.$4.id);
        });
  final merged = <(int, int, CustomBlock)>[];
  for (final r in replaces) {
    if (merged.isNotEmpty && merged.last.$2 >= r.$2 && merged.last.$1 <= r.$3) {
      final last = merged.last;
      merged[merged.length - 1] = (last.$1, max(last.$2, r.$3), last.$3);
    } else {
      merged.add((r.$2, r.$3, r.$4));
    }
  }
  bool covered(int row) => merged.any((m) => row >= m.$1 && row <= m.$2);

  final others =
      placed
          .where((p) => p.$1 != BlockPlacementKind.replace && !covered(p.$2))
          .toList()
        ..sort((a, b) {
          var c = a.$2.compareTo(b.$2);
          if (c != 0) {
            return c;
          }
          c = a.$1.index.compareTo(b.$1.index);
          return c != 0 ? c : a.$4.id.compareTo(b.$4.id);
        });

  final rows = <String>[];
  final blockRows = <int>{};
  final wrapRowToRow = <int?>[];
  void block(CustomBlock b) {
    for (var i = 0; i < b.rows; i++) {
      blockRows.add(rows.length);
      rows.add('');
    }
  }

  for (var wrapRow = 0; wrapRow < wrapLines.length; wrapRow++) {
    for (final p in others) {
      if (p.$1 == BlockPlacementKind.above && p.$2 == wrapRow) {
        block(p.$4);
      }
    }
    final replace = merged.where((m) => wrapRow >= m.$1 && wrapRow <= m.$2);
    if (replace.isNotEmpty) {
      wrapRowToRow.add(null);
      if (wrapRow == replace.first.$2) {
        block(replace.first.$3);
      }
    } else {
      wrapRowToRow.add(rows.length);
      rows.add(wrapLines[wrapRow]);
    }
    for (final p in others) {
      if (p.$1 != BlockPlacementKind.above && p.$2 == wrapRow) {
        block(p.$4);
      }
    }
  }
  return _Expected(rows, blockRows, wrapRowToRow);
}

void main() {
  group('blocks', () {
    test('rows are put in above and below, and in place of rows', () {
      final buffer = TextBuffer('aa\nbb\ncc\ndd');
      final map = DisplayMap(buffer);
      final ids = map.insertBlocks([
        _above(buffer, 3, 2),
        _below(buffer, 3, 1),
        _replace(buffer, 6, 8, 1),
      ]);
      expect(ids, hasLength(3));
      // above `bb` two rows, below it one, and `cc` is a row of its own
      expect(map.snapshot.text, 'aa\n\n\nbb\n\n\ndd');
      final snapshot = map.snapshot;
      expect(snapshot.rowCount, 7);
      expect(snapshot.isBlockLine(1), isTrue);
      expect(snapshot.isBlockLine(3), isFalse);
      expect(snapshot.isBlockLine(5), isTrue);
      expect(snapshot.rowInfo(3), (bufferRow: 1, softWrapped: false));
      expect(snapshot.rowInfo(1), (bufferRow: null, softWrapped: false));
      expect(snapshot.isLineReplaced(2), isTrue);
      expect(snapshot.isLineReplaced(3), isFalse);
      expect(snapshot.offsetToDisplayPoint(3), const Point(3, 0));
      expect(snapshot.displayPointToOffset(const Point(3, 1)), 4);
      expect(snapshot.blocksInRange(0, 7).map((b) => b.$1), [1, 4, 5]);

      map.resizeBlocks({ids[0]: 0});
      expect(map.snapshot.text, 'aa\nbb\n\n\ndd');
      map.removeBlocks({ids[1], ids[2]});
      expect(map.snapshot.text, 'aa\nbb\ncc\ndd');
      expect(map.blocks, hasLength(1));
    });

    test('a block stays with its line through edits', () {
      final buffer = TextBuffer('aa\nbb\ncc');
      final map = DisplayMap(buffer);
      map.insertBlocks([_above(buffer, 3, 1)]);
      expect(map.snapshot.text, 'aa\n\nbb\ncc');
      buffer.edit([const Replacement.insert(0, 'x\ny\n')]);
      expect(map.snapshot.text, 'x\ny\naa\n\nbb\ncc');
      buffer.edit([const Replacement(5, 8, '')]);
      expect(
        map.snapshot.text,
        // the line the block is above is now `ab`
        'x\ny\n\nab\ncc',
      );
    });

    test('blocks are clipped to, and not put on', () {
      final buffer = TextBuffer('aa\nbb');
      final map = DisplayMap(buffer);
      map.insertBlocks([_above(buffer, 3, 2)]);
      final snapshot = map.snapshot;
      expect(
        snapshot.clipPoint(const Point(1, 0), Bias.left),
        const Point(0, 2),
      );
      expect(
        snapshot.clipPoint(const Point(1, 0), Bias.right),
        const Point(3, 0),
      );
      expect(
        snapshot.clipPoint(const Point(3, 9), Bias.left),
        const Point(3, 2),
      );
    });

    test('random blocks, edits and wrap widths give the rows that are '
        'expected', () {
      const pieces = ['a', 'bc', '\n', ' ', 'word ', '\n\n', '\t'];
      for (var seed = 0; seed < 150; seed++) {
        final random = Random(seed);
        String randomText(int max) => List.generate(
          random.nextInt(max),
          (_) => pieces[random.nextInt(pieces.length)],
        ).join();

        final buffer = TextBuffer(randomText(12));
        final map = DisplayMap(
          buffer,
          tabSize: 1,
          wrapWidth: random.nextInt(5) == 0 ? null : 3.0 + random.nextInt(20),
        );
        for (var op = 0; op < 12; op++) {
          final why = 'seed $seed op $op';
          int offset() => buffer.text.clipOffset(
            random.nextInt(buffer.length + 1),
            Bias.left,
          );
          switch (random.nextInt(10)) {
            case 0:
              map.setWrapWidth(
                random.nextInt(5) == 0 ? null : 3.0 + random.nextInt(20),
              );
            case 1:
            case 2:
            case 3:
              final props = <BlockProperties>[];
              for (var i = 0; i < 1 + random.nextInt(3); i++) {
                final at = offset();
                props.add(switch (random.nextInt(3)) {
                  0 => _replace(
                    buffer,
                    at,
                    buffer.text.clipOffset(
                      at + random.nextInt(buffer.length - at + 1),
                      Bias.left,
                    ),
                    1 + random.nextInt(4),
                  ),
                  1 => _above(buffer, at, random.nextInt(4)),
                  _ => _below(buffer, at, random.nextInt(4)),
                });
              }
              map.insertBlocks(props);
            case 4:
            case 5:
              final all = map.blocks;
              if (all.isNotEmpty) {
                final remove = <int>{};
                for (var i = 0; i < 1 + random.nextInt(2); i++) {
                  remove.add(all[random.nextInt(all.length)].id);
                }
                map.removeBlocks(remove);
              }
            case 6:
              final all = map.blocks;
              if (all.isNotEmpty) {
                final block = all[random.nextInt(all.length)];
                map.resizeBlocks({
                  block.id: block.isReplacement
                      ? 1 + random.nextInt(4)
                      : random.nextInt(4),
                });
              }
            case 7:
              buffer.finalizeLastTransaction();
              if (random.nextBool()) {
                buffer.undo();
              } else {
                buffer.redo();
              }
            default:
              final a = offset();
              final b = offset();
              buffer.finalizeLastTransaction();
              buffer.edit([Replacement(min(a, b), max(a, b), randomText(4))]);
          }

          final expected = _expected(map, map.blocks);
          final snapshot = map.snapshot;
          expect(
            snapshot.rowCount,
            expected.rows.length,
            reason:
                '$why blocks ${map.blocks} wrap '
                '${snapshot.wrapSnapshot.text.split('\n')} got '
                '${snapshot.text.split('\n')} want ${expected.rows}',
          );
          for (var row = 0; row < expected.rows.length; row++) {
            expect(
              snapshot.rowText(row),
              expected.rows[row],
              reason: '$why $row',
            );
            expect(
              snapshot.lineLen(row),
              expected.rows[row].length,
              reason: why,
            );
            expect(
              snapshot.isBlockLine(row),
              expected.blockRows.contains(row),
              reason: '$why row $row',
            );
            if (expected.blockRows.contains(row)) {
              // only the first row of a replacement has a row of the buffer
              final bufferRow = snapshot.rowInfo(row).bufferRow;
              if (bufferRow != null) {
                expect(snapshot.isLineReplaced(bufferRow), isTrue, reason: why);
              }
            }
          }

          // a place of the buffer is on the row of the line it is in, unless
          // the line is replaced
          for (var at = 0; at <= buffer.length; at++) {
            if (buffer.text.clipOffset(at, Bias.left) != at) {
              continue;
            }
            final point = buffer.offsetToPoint(at);
            if (snapshot.isLineReplaced(point.row)) {
              continue;
            }
            final display = snapshot.offsetToDisplayPoint(at);
            final wrapRow = snapshot.wrapSnapshot
                .makeWrapPoint(point, Bias.left)
                .row;
            expect(display.row, expected.wrapRowToRow[wrapRow], reason: why);
            expect(snapshot.displayPointToOffset(display), at, reason: why);
            expect(
              snapshot.clipPoint(display, Bias.left),
              display,
              reason: why,
            );
          }
        }
      }
    });
  });
}
