import 'dart:math' as math;

import '../buffer.dart' show Anchor, BufferSnapshot;
import '../edit_patch.dart';
import '../highlight.dart' show Highlights;
import '../point.dart';
import '../sum_tree.dart';
import 'layer_edit.dart';
import 'wrap_map.dart';

/// where a block goes, in the positions of [T]
class BlockPlacement<T> {
  const BlockPlacement._(this.kind, this.start, this.end);

  /// above the row of [position]
  const BlockPlacement.above(T position)
    : this._(BlockPlacementKind.above, position, position);

  /// below the row of [position]
  const BlockPlacement.below(T position)
    : this._(BlockPlacementKind.below, position, position);

  /// below the row of [position], at the end of its text
  const BlockPlacement.near(T position)
    : this._(BlockPlacementKind.near, position, position);

  /// in place of the rows from that of [start] to that of [end]
  const BlockPlacement.replace(T start, T end)
    : this._(BlockPlacementKind.replace, start, end);

  final BlockPlacementKind kind;
  final T start;
  final T end;

  BlockPlacement<R> map<R>(R Function(T position) f) =>
      BlockPlacement<R>._(kind, f(start), f(end));

  /// which goes first when two are at the same place
  int get tieBreak => switch (kind) {
    BlockPlacementKind.replace => 0,
    BlockPlacementKind.above => 1,
    BlockPlacementKind.near => 2,
    BlockPlacementKind.below => 3,
  };

  @override
  String toString() => switch (kind) {
    BlockPlacementKind.replace => 'Replace($start..=$end)',
    _ => '${kind.name}($start)',
  };
}

enum BlockPlacementKind { above, below, near, replace }

/// how a block is drawn, which the layout does not care about
enum BlockStyle { fixed, flex, spacer, sticky }

/// what a block is made from
class BlockProperties {
  const BlockProperties({
    required this.placement,
    this.height,
    this.style = BlockStyle.fixed,
    this.priority = 0,
    this.data,
  });

  final BlockPlacement<Anchor> placement;

  /// how many rows it takes, or null for one that takes no room, such as a
  /// line
  final int? height;
  final BlockStyle style;

  /// of two blocks in the same place the one with the lower goes first
  final int priority;

  /// whatever draws the block needs
  final Object? data;
}

/// text-less rows put between the rows of the text, such as the room for a
/// diagnostic under a line, or a block that stands for rows that are replaced
class CustomBlock {
  const CustomBlock({
    required this.id,
    required this.placement,
    required this.height,
    required this.style,
    required this.priority,
    this.data,
  });

  final int id;
  final BlockPlacement<Anchor> placement;
  final int? height;
  final BlockStyle style;
  final int priority;
  final Object? data;

  int get rows => height ?? 0;

  bool get placeAbove => placement.kind == BlockPlacementKind.above;
  bool get placeNear => placement.kind == BlockPlacementKind.near;
  bool get placeBelow =>
      placement.kind == BlockPlacementKind.below ||
      placement.kind == BlockPlacementKind.near;
  bool get isReplacement => placement.kind == BlockPlacementKind.replace;

  CustomBlock withHeight(int height) => CustomBlock(
    id: id,
    placement: placement,
    height: height,
    style: style,
    priority: priority,
    data: data,
  );

  @override
  String toString() => 'Block#$id($placement, height $height)';
}

int _compareAnchorPlacements(
  BufferSnapshot buffer,
  BlockPlacement<Anchor> a,
  BlockPlacement<Anchor> b,
) {
  var c = buffer.compareAnchors(a.start, b.start);
  if (c != 0) {
    return c;
  }
  c = buffer.compareAnchors(b.end, a.end);
  return c != 0 ? c : a.tieBreak.compareTo(b.tieBreak);
}

/// [placement] in rows of the wrap layer, or null for a replacement of
/// nothing
BlockPlacement<int>? _toWrapRow(
  BlockPlacement<Anchor> placement,
  WrapSnapshot wrap,
) {
  final buffer = wrap.bufferSnapshot;
  int rowAt(Point point, {required bool endOfLine}) {
    final at = endOfLine
        ? Point(point.row, buffer.text.lineLength(point.row))
        : Point(point.row, 0);
    return wrap.makeWrapPoint(at, Bias.left).row;
  }

  switch (placement.kind) {
    case BlockPlacementKind.above:
      return BlockPlacement.above(
        rowAt(buffer.pointForAnchor(placement.start), endOfLine: false),
      );
    case BlockPlacementKind.near:
      return BlockPlacement.near(
        rowAt(buffer.pointForAnchor(placement.start), endOfLine: true),
      );
    case BlockPlacementKind.below:
      return BlockPlacement.below(
        rowAt(buffer.pointForAnchor(placement.start), endOfLine: true),
      );
    case BlockPlacementKind.replace:
      final start = buffer.pointForAnchor(placement.start);
      final end = buffer.pointForAnchor(placement.end);
      if (start == end) {
        return null;
      }
      return BlockPlacement.replace(
        rowAt(start, endOfLine: false),
        rowAt(end, endOfLine: true),
      );
  }
}

class _Summary {
  const _Summary({
    this.inputRows = 0,
    this.outputRows = 0,
    this.longestRow = 0,
    this.longestRowChars = 0,
    this.hasReplacementBlocks = false,
  });

  static const zero = _Summary();

  /// rows of the wrap layer
  final int inputRows;

  /// rows with the blocks
  final int outputRows;

  /// the longest row, counted from the start of what is summed
  final int longestRow;
  final int longestRowChars;
  final bool hasReplacementBlocks;

  _Summary operator +(_Summary other) => _Summary(
    inputRows: inputRows + other.inputRows,
    outputRows: outputRows + other.outputRows,
    longestRow: other.longestRowChars > longestRowChars
        ? outputRows + other.longestRow
        : longestRow,
    longestRowChars: math.max(longestRowChars, other.longestRowChars),
    hasReplacementBlocks: hasReplacementBlocks || other.hasReplacementBlocks,
  );
}

/// rows of the wrap layer passed through as they are, when [block] is null,
/// or a block with the rows it takes up, and the rows it stands for
class _Transform {
  const _Transform(this.summary, [this.block]);

  final _Summary summary;
  final CustomBlock? block;
}

class _Ops extends SummaryOps<_Transform, _Summary> {
  const _Ops();

  @override
  _Summary get zero => _Summary.zero;

  @override
  _Summary add(_Summary a, _Summary b) => a + b;

  @override
  _Summary summarize(_Transform item) => item.summary;
}

const _ops = _Ops();
const _dim = SummaryDimension<_Transform, _Summary>(_ops);

typedef _Tree = SumTree<_Transform, _Summary>;

SeekTarget<_Summary> _inputRow(int row) =>
    (p) => row.compareTo(p.inputRows);
SeekTarget<_Summary> _outputRow(int row) =>
    (p) => row.compareTo(p.outputRows);

/// [tree] with [rows] rows of the wrap layer, joined to the rows before them
_Tree _pushIsomorphic(_Tree tree, int rows, WrapSnapshot wrap) {
  if (rows <= 0) {
    return tree;
  }
  final start = tree.summary.inputRows;
  final text = wrap.textSummaryForRange(start, start + rows);
  final summary = _Summary(
    inputRows: rows,
    outputRows: rows,
    longestRow: text.longestRow,
    longestRowChars: text.longestRowChars,
  );
  final last = tree.last;
  if (last != null && last.block == null) {
    return tree.updateLast((_) => _Transform(last.summary + summary));
  }
  return tree.push(_Transform(summary));
}

int _comparePlacements(
  (BlockPlacement<int>, CustomBlock) a,
  (BlockPlacement<int>, CustomBlock) b,
) {
  var c = a.$1.start.compareTo(b.$1.start);
  if (c != 0) {
    return c;
  }
  c = b.$1.end.compareTo(a.$1.end);
  if (c != 0) {
    return c;
  }
  c = a.$1.tieBreak.compareTo(b.$1.tieBreak);
  if (c != 0) {
    return c;
  }
  c = a.$2.priority.compareTo(b.$2.priority);
  return c != 0 ? c : a.$2.id.compareTo(b.$2.id);
}

/// puts blocks in the order they are laid out in, and takes out the ones that
/// a replacement covers
void _sortBlocks(List<(BlockPlacement<int>, CustomBlock)> blocks) {
  blocks.sort(_comparePlacements);
  final out = <(BlockPlacement<int>, CustomBlock)>[];
  for (final right in blocks) {
    if (out.isNotEmpty) {
      final left = out.last;
      final l = left.$1;
      final r = right.$1;
      if (l.kind == BlockPlacementKind.replace) {
        if (r.kind != BlockPlacementKind.replace) {
          if (r.start >= l.start && r.start <= l.end) {
            continue;
          }
        } else if (l.end >= r.start && l.start <= r.end) {
          out[out.length - 1] = (
            BlockPlacement.replace(l.start, math.max(l.end, r.end)),
            left.$2,
          );
          continue;
        }
      }
    }
    out.add(right);
  }
  blocks
    ..clear()
    ..addAll(out);
}

/// decides where blocks go. it is the last layer of the display: its text is
/// the text of the wrap layer with rows of nothing put between the rows, and
/// some rows taken out and stood for by one block.
///
/// blocks are given as anchors in the buffer, so they stay with their text.
class BlockMap {
  BlockMap(WrapSnapshot wrapSnapshot)
    : _wrap = wrapSnapshot,
      _transforms = _pushIsomorphic(
        _Tree(_ops),
        wrapSnapshot.maxPoint.row + 1,
        wrapSnapshot,
      );

  WrapSnapshot _wrap;
  _Tree _transforms;
  final List<CustomBlock> _blocks = [];
  final Map<int, CustomBlock> _byId = {};
  int _nextId = 0;

  /// the blocks, in the order of where they are
  List<CustomBlock> get blocks => List.unmodifiable(_blocks);

  /// follows the wrap layer to [wrapSnapshot], which [edits] were made to,
  /// and gives the layout
  BlockSnapshot read(WrapSnapshot wrapSnapshot, List<RowEdit> edits) {
    _sync(wrapSnapshot, edits);
    _wrap = wrapSnapshot;
    return _snapshot();
  }

  /// follows the wrap layer the same way, to change the blocks
  BlockMapWriter write(WrapSnapshot wrapSnapshot, List<RowEdit> edits) {
    _sync(wrapSnapshot, edits);
    _wrap = wrapSnapshot;
    return BlockMapWriter._(this);
  }

  BlockSnapshot get snapshot => _snapshot();

  BlockSnapshot _snapshot() =>
      BlockSnapshot._(_wrap, _transforms, Map.of(_byId));

  void _sync(WrapSnapshot wrap, List<RowEdit> editList) {
    final patch = EditPatch();
    for (final edit in editList) {
      patch.push(edit);
    }
    final edits = patch.edits;
    if (edits.isEmpty) {
      return;
    }
    final buffer = wrap.bufferSnapshot;
    final maxRow = wrap.maxPoint.row;

    var newTransforms = _Tree(_ops);
    final cursor = _transforms.cursor(_dim);
    var lastBlockIx = 0;
    var next = 0;

    // the first block that starts at or after [point], from [from] on
    int firstBlockAtOrAfter(Point point, int from) {
      var low = from;
      var high = _blocks.length;
      while (low < high) {
        final middle = (low + high) >> 1;
        final at = buffer.pointForAnchor(_blocks[middle].placement.start);
        if (at.compareTo(point) >= 0) {
          high = middle;
        } else {
          low = middle + 1;
        }
      }
      return low;
    }

    while (next < edits.length) {
      final edit = edits[next++];
      var oldStart = edit.oldStart;
      var newStart = edit.newStart;

      // what comes before the edit is kept: transforms that end before it,
      // text that ends at it, and the blocks below that text. a replacement
      // that ends at the edit is made again.
      newTransforms = newTransforms.append(
        cursor.slice(_inputRow(oldStart), Bias.left),
      );
      final item = cursor.item;
      if (item != null &&
          item.summary.inputRows > 0 &&
          cursor.end.inputRows == oldStart &&
          (item.block == null || !item.block!.isReplacement)) {
        newTransforms = newTransforms.push(item);
        cursor.next();
        while (true) {
          final following = cursor.item;
          if (following != null && (following.block?.placeBelow ?? false)) {
            newTransforms = newTransforms.push(following);
            cursor.next();
          } else {
            break;
          }
        }
      }

      // the edit starts where a transform does
      final rowsBeforeEdit = oldStart - cursor.start.inputRows;
      final current = cursor.item;
      if (rowsBeforeEdit > 0 && current != null) {
        if (current.block == null) {
          newTransforms = _pushIsomorphic(newTransforms, rowsBeforeEdit, wrap);
        } else {
          // in a replacement: the edit starts where the replacement does
          oldStart -= rowsBeforeEdit;
          newStart -= rowsBeforeEdit;
        }
      }

      // the edit ends where a transform does, and takes in the edits that
      // share a transform with it
      var oldEnd = edit.oldEnd;
      var newEnd = edit.newEnd;
      while (true) {
        cursor
          ..seek(_inputRow(oldEnd), Bias.left)
          ..next();
        final rowsAfterEdit = cursor.start.inputRows - oldEnd;
        oldEnd += rowsAfterEdit;
        newEnd += rowsAfterEdit;
        while (next < edits.length &&
            edits[next].oldStart <= cursor.start.inputRows) {
          final following = edits[next++];
          oldEnd = following.oldEnd;
          newEnd = following.newEnd;
          cursor
            ..seek(_inputRow(oldEnd), Bias.left)
            ..next();
        }
        if (cursor.start.inputRows == oldEnd) {
          break;
        }
      }

      // the blocks below the end of the edit are made again
      while (true) {
        final following = cursor.item;
        if (following != null && (following.block?.placeBelow ?? false)) {
          cursor.next();
        } else {
          break;
        }
      }

      // the blocks that start in the edited rows
      final startBlockIx = firstBlockAtOrAfter(
        wrap.toPoint(Point(newStart, 0), Bias.left),
        lastBlockIx,
      );
      final int endBlockIx;
      if (newEnd > maxRow) {
        endBlockIx = _blocks.length;
      } else {
        endBlockIx = firstBlockAtOrAfter(
          wrap.toPoint(Point(newEnd, 0), Bias.left),
          startBlockIx,
        );
      }
      lastBlockIx = endBlockIx;

      final inEdit = <(BlockPlacement<int>, CustomBlock)>[];
      for (var i = startBlockIx; i < endBlockIx; i++) {
        final block = _blocks[i];
        final placement = _toWrapRow(block.placement, wrap);
        if (placement == null) {
          continue;
        }
        // a block in a fold is not shown, unless it replaces the fold's rows
        if (placement.kind != BlockPlacementKind.replace) {
          final row = buffer.pointForAnchor(block.placement.start).row;
          final offset = buffer.text.pointToOffset(Point(row, 0));
          if (wrap.tabSnapshot.foldSnapshot.intersectsFold(offset)) {
            continue;
          }
        }
        if (placement.kind == BlockPlacementKind.above &&
            placement.start < newStart) {
          continue;
        }
        inEdit.add((placement, block));
      }
      _sortBlocks(inEdit);

      // each block has the text before it, and then itself
      for (final (placement, block) in inEdit) {
        var summary = _Summary(outputRows: block.rows);
        final inputRows = newTransforms.summary.inputRows;
        final int rowsBeforeBlock;
        switch (placement.kind) {
          case BlockPlacementKind.above:
            rowsBeforeBlock = placement.start - inputRows;
          case BlockPlacementKind.near:
          case BlockPlacementKind.below:
            rowsBeforeBlock = placement.start + 1 - inputRows;
          case BlockPlacementKind.replace:
            rowsBeforeBlock = placement.start - inputRows;
            summary = _Summary(
              inputRows: 1 + placement.end - placement.start,
              outputRows: block.rows,
              hasReplacementBlocks: true,
            );
        }
        if (rowsBeforeBlock < 0) {
          continue;
        }
        newTransforms = _pushIsomorphic(newTransforms, rowsBeforeBlock, wrap);
        newTransforms = newTransforms.push(_Transform(summary, block));
      }

      // and the text after the last block
      newTransforms = _pushIsomorphic(
        newTransforms,
        math.max(0, newEnd - newTransforms.summary.inputRows),
        wrap,
      );
    }

    newTransforms = newTransforms.append(cursor.suffix());
    assert(
      newTransforms.summary.inputRows == maxRow + 1,
      'the blocks cover ${newTransforms.summary.inputRows} rows of '
      '${maxRow + 1}',
    );
    _transforms = newTransforms;
  }
}

/// changes the blocks of a map, which is made to follow the layout first
class BlockMapWriter {
  BlockMapWriter._(this._map);

  final BlockMap _map;

  /// the rows of the wrap layer from the one that starts the line of
  /// [bufferRow] to the one that starts the next line
  (int, int) _wrapRowRange(Point start, Point end) {
    final wrap = _map._wrap;
    final startWrapRow = wrap.makeWrapPoint(Point(start.row, 0), Bias.left).row;
    final endWrapRow = wrap.makeWrapPoint(Point(end.row, 0), Bias.left).row;
    final first = wrap.prevRowBoundary(Point(startWrapRow, 0));
    final last =
        wrap.nextRowBoundary(Point(endWrapRow, 0)) ?? wrap.maxPoint.row + 1;
    return (first, last);
  }

  /// puts in [blocks], and gives their ids
  List<int> insert(Iterable<BlockProperties> blocks) {
    final ids = <int>[];
    final wrap = _map._wrap;
    final buffer = wrap.bufferSnapshot;
    final edits = <RowEdit>[];
    for (final properties in blocks) {
      assert(
        properties.placement.kind != BlockPlacementKind.replace ||
            (properties.height ?? 0) > 0,
        'a block that replaces rows has a height',
      );
      final id = _map._nextId++;
      final block = CustomBlock(
        id: id,
        placement: properties.placement,
        height: properties.height,
        style: properties.style,
        priority: properties.priority,
        data: properties.data,
      );
      var low = 0;
      var high = _map._blocks.length;
      while (low < high) {
        final middle = (low + high) >> 1;
        if (_compareAnchorPlacements(
              buffer,
              _map._blocks[middle].placement,
              block.placement,
            ) <
            0) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      _map._blocks.insert(low, block);
      _map._byId[id] = block;
      ids.add(id);

      final (first, last) = _wrapRowRange(
        buffer.pointForAnchor(properties.placement.start),
        buffer.pointForAnchor(properties.placement.end),
      );
      edits.add(LayerEdit(first, last, first, last));
    }
    _map._sync(wrap, consolidateEdits(edits));
    return ids;
  }

  /// gives the blocks of [heights] the heights they are mapped to
  void resize(Map<int, int> heights) {
    final wrap = _map._wrap;
    final buffer = wrap.bufferSnapshot;
    final edits = <RowEdit>[];
    for (var i = 0; i < _map._blocks.length; i++) {
      final block = _map._blocks[i];
      final newHeight = heights[block.id];
      if (newHeight == null || block.height == newHeight) {
        continue;
      }
      assert(
        !block.isReplacement || newHeight > 0,
        'a block that replaces rows has a height',
      );
      final resized = block.withHeight(newHeight);
      _map._blocks[i] = resized;
      _map._byId[block.id] = resized;

      final start = buffer.pointForAnchor(block.placement.start);
      final end = buffer.pointForAnchor(block.placement.end);
      final (first, last) = _wrapRowRange(start, end);
      edits.add(LayerEdit(first, last, first, last));
    }
    _map._sync(wrap, consolidateEdits(edits));
  }

  /// takes out the blocks with [ids]
  void remove(Set<int> ids) {
    final wrap = _map._wrap;
    final buffer = wrap.bufferSnapshot;
    final edits = <RowEdit>[];
    _map._blocks.removeWhere((block) {
      if (!ids.contains(block.id)) {
        return false;
      }
      final start = buffer.pointForAnchor(block.placement.start);
      final end = buffer.pointForAnchor(block.placement.end);
      final (first, last) = _wrapRowRange(start, end);
      edits.add(LayerEdit(first, last, first, last));
      return true;
    });
    _map._byId.removeWhere((id, _) => ids.contains(id));
    _map._sync(wrap, consolidateEdits(edits));
  }

  /// takes out the blocks that replace rows that [ranges] of the buffer
  /// touch; with [inclusive], also the ones that are only next to them
  void removeIntersectingReplaceBlocks(
    Iterable<(int start, int end)> ranges, {
    bool inclusive = false,
  }) {
    final buffer = _map._wrap.bufferSnapshot;
    final toRemove = <int>{};
    for (final (start, end) in ranges) {
      final from = buffer.anchorBefore(start);
      final to = buffer.anchorAfter(end);
      for (final block in _map._blocks) {
        if (!block.isReplacement) {
          continue;
        }
        final blockStart = block.placement.start;
        final blockEnd = block.placement.end;
        final startCmp = buffer.compareAnchors(from, blockEnd);
        final endCmp = buffer.compareAnchors(to, blockStart);
        final intersects = inclusive
            ? startCmp <= 0 && endCmp >= 0
            : startCmp < 0 && endCmp > 0;
        if (intersects) {
          toRemove.add(block.id);
        }
      }
    }
    remove(toRemove);
  }
}

/// the text with its blocks at one time. a point "of the blocks" has the row
/// that a place is on once rows are put in for the blocks, and a column of
/// the text on it.
class BlockSnapshot {
  BlockSnapshot._(this.wrapSnapshot, this._transforms, this._byId);

  final WrapSnapshot wrapSnapshot;
  final _Tree _transforms;
  final Map<int, CustomBlock> _byId;

  bool get hasReplacementBlocks => _transforms.summary.hasReplacementBlocks;

  /// how many rows of the wrap layer the blocks go over, which is all of them
  int get inputRows => _transforms.summary.inputRows;

  int get rowCount => _transforms.summary.outputRows;

  Point get maxPoint {
    final row = math.max(0, rowCount - 1);
    return Point(row, lineLen(row));
  }

  int get longestRow => _transforms.summary.longestRow;

  /// how long row [row] is; a block has no text
  int lineLen(int row) {
    final (start, _, item) = _transforms.find(
      _dim,
      _outputRow(row),
      Bias.right,
    );
    if (item != null) {
      return item.block != null
          ? 0
          : wrapSnapshot.lineLen(start.inputRows + (row - start.outputRows));
    }
    if (row == 0) {
      return 0;
    }
    throw RangeError.range(row, 0, rowCount - 1, 'row');
  }

  /// whether row [row] is a block
  bool isBlockLine(int row) {
    final (_, _, item) = _transforms.find(_dim, _outputRow(row), Bias.right);
    return item?.block != null;
  }

  /// whether line [bufferRow] of the buffer is in rows that a block replaces
  bool isLineReplaced(int bufferRow) {
    final row = wrapSnapshot.makeWrapPoint(Point(bufferRow, 0), Bias.left).row;
    final (_, _, item) = _transforms.find(_dim, _inputRow(row), Bias.right);
    return item?.block?.isReplacement ?? false;
  }

  /// the block with id [id]
  CustomBlock? blockForId(int id) => _byId[id];

  /// the blocks that start in rows [startRow] to [endRow], with the row they
  /// start on
  List<(int, CustomBlock)> blocksInRange(int startRow, int endRow) {
    final out = <(int, CustomBlock)>[];
    final cursor = _transforms.cursor(_dim)
      ..seek(_outputRow(startRow), Bias.left);
    while (cursor.start.outputRows < startRow &&
        cursor.end.outputRows <= startRow) {
      cursor.next();
    }
    while (true) {
      final transform = cursor.item;
      if (transform == null) {
        break;
      }
      final row = cursor.start.outputRows;
      final block = transform.block;
      if (row > endRow || (row == endRow && block != null && block.rows > 0)) {
        break;
      }
      if (block != null) {
        out.add((row, block));
      }
      cursor.next();
    }
    return out;
  }

  /// the text of the rows, and what each is of, for row [row]
  Iterable<WrapChunk> rowChunks(
    int row, [
    Highlights highlights = Highlights.none,
  ]) sync* {
    final (start, _, item) = _transforms.find(
      _dim,
      _outputRow(row),
      Bias.right,
    );
    if (item == null || item.block != null) {
      return;
    }
    final wrapRow = start.inputRows + (row - start.outputRows);
    yield* wrapSnapshot.chunks(
      Point(wrapRow, 0),
      Point(wrapRow, wrapSnapshot.lineLen(wrapRow)),
      highlights,
    );
  }

  String rowText(int row) => [for (final c in rowChunks(row)) c.text].join();

  /// all the text, a row to a line
  String get text => [for (var r = 0; r < rowCount; r++) rowText(r)].join('\n');

  /// the row of the buffer that row [row] shows part of, null when it is a
  /// block; and whether it continues a line that wrapped. the first row of a
  /// block that replaces rows is the row of the buffer it starts at.
  ({int? bufferRow, bool softWrapped}) rowInfo(int row) {
    final (start, _, item) = _transforms.find(
      _dim,
      _outputRow(row),
      Bias.right,
    );
    if (item == null) {
      return (bufferRow: null, softWrapped: false);
    }
    final block = item.block;
    if (block == null) {
      return wrapSnapshot.rowInfo(start.inputRows + (row - start.outputRows));
    }
    if (block.isReplacement && row == start.outputRows) {
      final info = wrapSnapshot.rowInfo(start.inputRows);
      return (bufferRow: info.bufferRow, softWrapped: false);
    }
    return (bufferRow: null, softWrapped: false);
  }

  /// the block point of the wrap point [point]
  Point toBlockPoint(Point point) {
    final (start, _, item) = _transforms.find(
      _dim,
      _inputRow(point.row),
      Bias.right,
    );
    if (item == null) {
      return maxPoint;
    }
    if (item.block != null) {
      return Point(start.outputRows, 0);
    }
    return Point(
      start.outputRows + (point.row - start.inputRows),
      point.column,
    );
  }

  /// the wrap point of the block point [point]. a place in a block goes to the
  /// edge of the text it is next to, or, in a replacement, to the side that
  /// [bias] says.
  Point toWrapPoint(Point point, Bias bias) {
    final (start, end, item) = _transforms.find(
      _dim,
      _outputRow(point.row),
      Bias.right,
    );
    if (item == null) {
      return wrapSnapshot.maxPoint;
    }
    final block = item.block;
    if (block == null) {
      return Point(
        start.inputRows + (point.row - start.outputRows),
        point.column,
      );
    }
    if (block.placeBelow) {
      final row = start.inputRows - 1;
      return Point(row, wrapSnapshot.lineLen(row));
    }
    if (block.placeAbove || bias == Bias.left) {
      return Point(start.inputRows, 0);
    }
    final row = end.inputRows - 1;
    return Point(row, wrapSnapshot.lineLen(row));
  }

  /// [point] moved to a place that can be at: not in a block, nor past the
  /// end of a row
  Point clipPoint(Point point, Bias bias) {
    final cursor = _transforms.cursor(_dim)
      ..seek(_outputRow(point.row), Bias.right);
    final maxInputRow = inputRows;
    var searchLeft =
        (bias == Bias.left && cursor.start.inputRows > 0) ||
        cursor.end.inputRows == maxInputRow;
    var reversed = false;

    while (true) {
      final transform = cursor.item;
      if (transform != null) {
        final outputStart = Point(cursor.start.outputRows, 0);
        final inputStart = Point(cursor.start.inputRows, 0);
        final inputEnd = Point(cursor.end.inputRows, 0);
        final block = transform.block;
        if (block != null) {
          if (block.isReplacement &&
              (((bias == Bias.left || searchLeft) &&
                      outputStart.compareTo(point) <= 0) ||
                  (!searchLeft && outputStart.compareTo(point) >= 0))) {
            return outputStart;
          }
        } else {
          final Point inputPoint;
          if (point.row >= cursor.end.outputRows) {
            final row = cursor.end.inputRows - 1;
            inputPoint = wrapSnapshot.clipPoint(
              Point(row, wrapSnapshot.lineLen(row)),
              bias,
            );
          } else {
            inputPoint = wrapSnapshot.clipPoint(
              inputStart + _saturatingSub(point, outputStart),
              bias,
            );
          }
          if (inputPoint.compareTo(inputStart) >= 0 &&
              inputPoint.compareTo(inputEnd) < 0) {
            return outputStart + _saturatingSub(inputPoint, inputStart);
          }
        }
        if (searchLeft) {
          cursor.prev();
        } else {
          cursor.next();
        }
      } else if (reversed) {
        return maxPoint;
      } else {
        reversed = true;
        searchLeft = !searchLeft;
        cursor.seek(_outputRow(point.row), Bias.right);
      }
    }
  }
}

Point _saturatingSub(Point a, Point b) =>
    a.compareTo(b) <= 0 ? Point.zero : a - b;
