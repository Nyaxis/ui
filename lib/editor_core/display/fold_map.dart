import 'dart:math' as math;

import '../buffer.dart' show Anchor, AnchorRange, BufferSnapshot;
import '../highlight.dart' show HighlightStyle, Highlights;
import '../point.dart';
import '../sum_tree.dart';
import '../text_summary.dart';
import 'inlay_map.dart';
import 'layer_edit.dart';

/// what is shown in place of text that is folded
const String foldEllipsis = '⋯';

/// what is shown in place of a fold
class FoldPlaceholder {
  const FoldPlaceholder({
    this.collapsedText,
    this.mergeAdjacent = true,
    this.constrainWidth = true,
    this.typeTag,
  });

  /// the text shown, or null for the ellipsis
  final String? collapsedText;

  /// whether the fold is one with a fold that starts where it ends
  final bool mergeAdjacent;

  /// whether what is shown is kept as narrow as its text
  final bool constrainWidth;

  /// what made the fold, by which its folds can be taken out again
  final Object? typeTag;

  String get text => collapsedText ?? foldEllipsis;
}

/// a range of the buffer that is folded away
class Fold {
  const Fold({
    required this.id,
    required this.range,
    this.placeholder = const FoldPlaceholder(),
  });

  final int id;

  /// the text that is folded, which stays the same text as the buffer is
  /// edited: what is typed at its ends is outside it
  final AnchorRange range;
  final FoldPlaceholder placeholder;
}

class _FoldSummary {
  const _FoldSummary(
    this.start,
    this.end,
    this.minStart,
    this.maxEnd,
    this.count,
  );

  static const zero = _FoldSummary(
    Anchor.min,
    Anchor.max,
    Anchor.max,
    Anchor.min,
    0,
  );

  /// the range of the last fold
  final Anchor start;
  final Anchor end;

  /// the first start and the last end of all the folds
  final Anchor minStart;
  final Anchor maxEnd;
  final int count;
}

/// the buffer that the anchors of the folds are compared in, which is the one
/// the map last saw
class _BufferRef {
  _BufferRef(this.buffer);

  BufferSnapshot buffer;
}

class _FoldOps extends SummaryOps<Fold, _FoldSummary> {
  const _FoldOps(this.ref);

  final _BufferRef ref;

  @override
  _FoldSummary get zero => _FoldSummary.zero;

  @override
  _FoldSummary add(_FoldSummary a, _FoldSummary b) {
    final buffer = ref.buffer;
    return _FoldSummary(
      b.start,
      b.end,
      buffer.compareAnchors(b.minStart, a.minStart) < 0
          ? b.minStart
          : a.minStart,
      buffer.compareAnchors(b.maxEnd, a.maxEnd) > 0 ? b.maxEnd : a.maxEnd,
      a.count + b.count,
    );
  }

  @override
  _FoldSummary summarize(Fold item) => _FoldSummary(
    item.range.start,
    item.range.end,
    item.range.start,
    item.range.end,
    1,
  );
}

/// which of two ranges comes first: the one that starts first, and of two
/// that start together the one that ends last
int _compareRanges(BufferSnapshot buffer, AnchorRange a, AnchorRange b) {
  final byStart = buffer.compareAnchors(a.start, b.start);
  return byStart != 0 ? byStart : buffer.compareAnchors(b.end, a.end);
}

/// a cursor over the folds that have any of the buffer from [start] to
/// [end]; with [inclusive], also the ones that only touch it
FilterCursor<Fold, _FoldSummary, _FoldSummary> _intersectingFolds(
  BufferSnapshot buffer,
  SumTree<Fold, _FoldSummary> folds,
  int start,
  int end,
  bool inclusive,
) {
  final startAnchor = buffer.anchorBefore(start);
  final endAnchor = buffer.anchorAfter(end);
  return folds.filter(SummaryDimension<Fold, _FoldSummary>(folds.ops), (
    summary,
  ) {
    final startCmp = buffer.compareAnchors(startAnchor, summary.maxEnd);
    final endCmp = buffer.compareAnchors(endAnchor, summary.minStart);
    return inclusive
        ? startCmp <= 0 && endCmp >= 0
        : startCmp < 0 && endCmp > 0;
  })..next();
}

class _Transform {
  const _Transform(this.summary, [this.placeholder, this.fold]);

  final _Summary summary;

  /// the text shown for a fold, or null for text that is shown as it is
  final String? placeholder;
  final Fold? fold;

  bool get isFold => placeholder != null;
}

class _Summary {
  const _Summary(this.input, this.output);

  static const zero = _Summary(TextSummary.zero, TextSummary.zero);

  /// the text of the inlay layer
  final TextSummary input;

  /// the text with the folds
  final TextSummary output;

  _Summary operator +(_Summary other) =>
      _Summary(input + other.input, output + other.output);
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

SeekTarget<_Summary> _inputOffset(int offset) =>
    (p) => offset.compareTo(p.input.len);
SeekTarget<_Summary> _outputOffset(int offset) =>
    (p) => offset.compareTo(p.output.len);
SeekTarget<_Summary> _inputPoint(Point point) =>
    (p) => point.compareTo(p.input.lines);
SeekTarget<_Summary> _outputPoint(Point point) =>
    (p) => point.compareTo(p.output.lines);

SumTree<_Transform, _Summary> _pushIsomorphic(
  SumTree<_Transform, _Summary> tree,
  TextSummary summary,
) {
  final last = tree.last;
  if (last != null && !last.isFold) {
    return tree.updateLast(
      (_) => _Transform(last.summary + _Summary(summary, summary)),
    );
  }
  return tree.push(_Transform(_Summary(summary, summary)));
}

/// decides what text is folded away. it is the second layer of the display:
/// its text is the text of the inlay layer with a placeholder for each fold.
class FoldMap {
  FoldMap(InlaySnapshot inlaySnapshot)
    : _buffer = _BufferRef(inlaySnapshot.bufferSnapshot) {
    _snapshot = FoldSnapshot._(
      inlaySnapshot,
      SumTree<_Transform, _Summary>(_ops).push(
        _Transform(
          _Summary(inlaySnapshot.textSummary, inlaySnapshot.textSummary),
        ),
      ),
      SumTree<Fold, _FoldSummary>(_FoldOps(_buffer)),
      0,
    );
  }

  final _BufferRef _buffer;
  late FoldSnapshot _snapshot;
  int _nextFoldId = 0;

  FoldSnapshot get snapshot => _snapshot;

  /// follows the inlay layer to [inlaySnapshot], which [inlayEdits] were made
  /// to
  (FoldSnapshot, List<LayerEdit>) read(
    InlaySnapshot inlaySnapshot,
    List<LayerEdit> inlayEdits,
  ) {
    final edits = _sync(inlaySnapshot, inlayEdits);
    return (_snapshot, edits);
  }

  /// folds [ranges] of the buffer, each with what is shown in its place, or
  /// null for the ellipsis
  (FoldSnapshot, List<LayerEdit>) fold(
    Iterable<(int start, int end, FoldPlaceholder? placeholder)> ranges,
  ) {
    final inlay = _snapshot.inlaySnapshot;
    final buffer = inlay.bufferSnapshot;
    final edits = <LayerEdit>[];
    final folds = <Fold>[];
    for (final (start, end, placeholder) in ranges) {
      // a range of nothing is not folded
      if (start >= end) {
        continue;
      }
      folds.add(
        Fold(
          id: _nextFoldId++,
          range: buffer.anchorRangeInside(start, end),
          placeholder: placeholder ?? const FoldPlaceholder(),
        ),
      );
      final from = inlay.toInlayOffset(start);
      final to = inlay.toInlayOffset(end);
      edits.add(LayerEdit(from, to, from, to));
    }
    // a sort that keeps the order of the ones that are the same range
    final indexed = [for (var i = 0; i < folds.length; i++) (i, folds[i])]
      ..sort((a, b) {
        final byRange = _compareRanges(buffer, a.$2.range, b.$2.range);
        return byRange != 0 ? byRange : a.$1.compareTo(b.$1);
      });

    final cursor = _snapshot._folds.cursor(_foldDim);
    var tree = SumTree<Fold, _FoldSummary>(_snapshot._folds.ops);
    for (final (_, fold) in indexed) {
      tree = tree
          .append(
            cursor.slice(
              (p) => _compareRanges(
                buffer,
                fold.range,
                AnchorRange(p.start, p.end),
              ),
              Bias.right,
            ),
          )
          .push(fold);
    }
    tree = tree.append(cursor.suffix());

    _snapshot = FoldSnapshot._(
      inlay,
      _snapshot._transforms,
      tree,
      _snapshot.version,
    );
    final foldEdits = _sync(inlay, consolidateEdits(edits));
    return (_snapshot, foldEdits);
  }

  /// takes out the folds that have any of [ranges] of the buffer and were
  /// made with a placeholder that has [typeTag]
  (FoldSnapshot, List<LayerEdit>) removeFolds(
    Iterable<(int start, int end)> ranges,
    Object typeTag,
  ) => _removeFoldsWith(
    ranges,
    (fold) => fold.placeholder.typeTag == typeTag,
    false,
  );

  /// takes out the folds that have any of [ranges] of the buffer; with
  /// [inclusive], also the ones that only touch them
  (FoldSnapshot, List<LayerEdit>) unfoldIntersecting(
    Iterable<(int start, int end)> ranges, {
    bool inclusive = false,
  }) => _removeFoldsWith(ranges, (_) => true, inclusive);

  (FoldSnapshot, List<LayerEdit>) _removeFoldsWith(
    Iterable<(int start, int end)> ranges,
    bool Function(Fold fold) shouldUnfold,
    bool inclusive,
  ) {
    final inlay = _snapshot.inlaySnapshot;
    final buffer = inlay.bufferSnapshot;
    final edits = <LayerEdit>[];
    final toDelete = <int>{};
    for (final (start, end) in ranges) {
      final cursor = _intersectingFolds(
        buffer,
        _snapshot._folds,
        start,
        end,
        inclusive,
      );
      while (true) {
        final fold = cursor.item;
        if (fold == null) {
          break;
        }
        if (shouldUnfold(fold)) {
          final foldStart = buffer.offsetForAnchor(fold.range.start);
          final foldEnd = buffer.offsetForAnchor(fold.range.end);
          if (foldEnd > foldStart) {
            final from = inlay.toInlayOffset(foldStart);
            final to = inlay.toInlayOffset(foldEnd);
            edits.add(LayerEdit(from, to, from, to));
          }
          toDelete.add(cursor.start.count);
        }
        cursor.next();
      }
    }

    final cursor = _snapshot._folds.cursor(_foldDim);
    var tree = SumTree<Fold, _FoldSummary>(_snapshot._folds.ops);
    for (final index in toDelete.toList()..sort()) {
      tree = tree.append(
        cursor.slice((p) => index.compareTo(p.count), Bias.right),
      );
      cursor.next();
    }
    tree = tree.append(cursor.suffix());

    _snapshot = FoldSnapshot._(
      inlay,
      _snapshot._transforms,
      tree,
      _snapshot.version,
    );
    final foldEdits = _sync(inlay, consolidateEdits(edits));
    return (_snapshot, foldEdits);
  }

  SummaryDimension<Fold, _FoldSummary> get _foldDim =>
      SummaryDimension<Fold, _FoldSummary>(_snapshot._folds.ops);

  List<LayerEdit> _sync(InlaySnapshot inlay, List<LayerEdit> inlayEdits) {
    final old = _snapshot;
    final buffer = inlay.bufferSnapshot;
    _buffer.buffer = buffer;
    if (inlayEdits.isEmpty) {
      _snapshot = FoldSnapshot._(
        inlay,
        old._transforms,
        old._folds,
        old.inlaySnapshot.version != inlay.version
            ? old.version + 1
            : old.version,
      );
      return const [];
    }

    final folds = old._folds;
    var newTransforms = SumTree<_Transform, _Summary>(_ops);
    final cursor = old._transforms.cursor(_dim)
      ..seek(_inputOffset(0), Bias.right);
    var next = 0;
    while (next < inlayEdits.length) {
      final edit = inlayEdits[next++];
      var oldStart = edit.oldStart;
      var oldEnd = edit.oldEnd;
      var newStart = edit.newStart;

      final item = cursor.item;
      final last = newTransforms.last;
      if (item != null && !item.isFold && last != null && !last.isFold) {
        newTransforms = newTransforms.updateLast(
          (_) => _Transform(last.summary + item.summary),
        );
        cursor.next();
      }
      newTransforms = newTransforms.append(
        cursor.slice(_inputOffset(oldStart), Bias.left),
      );
      newStart -= oldStart - cursor.start.input.len;
      oldStart = cursor.start.input.len;

      cursor
        ..seek(_inputOffset(oldEnd), Bias.right)
        ..next();

      var delta = (edit.newEnd - edit.newStart) - (edit.oldEnd - edit.oldStart);
      while (true) {
        oldEnd = cursor.start.input.len;
        if (next >= inlayEdits.length) {
          break;
        }
        final following = inlayEdits[next];
        if (following.oldStart > oldEnd) {
          break;
        }
        next++;
        delta +=
            (following.newEnd - following.newStart) -
            (following.oldEnd - following.oldStart);
        if (following.oldEnd >= oldEnd) {
          oldEnd = following.oldEnd;
          cursor
            ..seek(_inputOffset(oldEnd), Bias.right)
            ..next();
        }
      }
      final newEnd = newStart + (oldEnd - oldStart) + delta;

      // the folds that start in what changed
      final from = inlay.toBufferOffset(newStart);
      final foldsCursor = folds.cursor(_foldDim)
        ..seek(
          (p) => from.compareTo(buffer.offsetForAnchor(p.start)),
          Bias.left,
        );
      (Fold, int, int)? peeked;
      (Fold, int, int)? peek() {
        final fold = foldsCursor.item;
        if (fold == null) {
          return null;
        }
        return peeked ??= (
          fold,
          inlay.toInlayOffset(buffer.offsetForAnchor(fold.range.start)),
          inlay.toInlayOffset(buffer.offsetForAnchor(fold.range.end)),
        );
      }

      void advance() {
        peeked = null;
        foldsCursor.next();
      }

      while (true) {
        final head = peek();
        if (head == null || head.$2 >= newEnd) {
          break;
        }
        advance();
        final fold = head.$1;
        final foldStart = head.$2;
        var foldEnd = head.$3;
        while (true) {
          final following = peek();
          if (following == null) {
            break;
          }
          if (following.$2 < foldEnd ||
              (following.$2 == foldEnd &&
                  fold.placeholder.mergeAdjacent &&
                  following.$1.placeholder.mergeAdjacent)) {
            advance();
            if (following.$3 > foldEnd) {
              foldEnd = following.$3;
            }
          } else {
            break;
          }
        }

        final sum = newTransforms.summary;
        assert(foldStart >= sum.input.len);
        if (foldStart > sum.input.len) {
          newTransforms = _pushIsomorphic(
            newTransforms,
            inlay.textSummaryForRange(sum.input.len, foldStart),
          );
        }
        if (foldEnd > foldStart) {
          newTransforms = newTransforms.push(
            _Transform(
              _Summary(
                inlay.textSummaryForRange(foldStart, foldEnd),
                TextSummary.of(fold.placeholder.text),
              ),
              fold.placeholder.text,
              fold,
            ),
          );
        }
      }

      final sum = newTransforms.summary;
      if (sum.input.len < newEnd) {
        newTransforms = _pushIsomorphic(
          newTransforms,
          inlay.textSummaryForRange(sum.input.len, newEnd),
        );
      }
    }

    newTransforms = newTransforms.append(cursor.suffix());
    if (newTransforms.isEmpty) {
      newTransforms = _pushIsomorphic(newTransforms, inlay.textSummary);
    }

    final foldEdits = _foldEdits(
      old,
      newTransforms,
      inlayEdits,
      old.inlaySnapshot.len,
      inlay.len,
    );
    _snapshot = FoldSnapshot._(inlay, newTransforms, folds, old.version + 1);
    return foldEdits;
  }

  /// what changed in the text of this layer, from what changed below it: an
  /// edit that starts or ends inside a fold is made to take in all of it
  static List<LayerEdit> _foldEdits(
    FoldSnapshot old,
    SumTree<_Transform, _Summary> newTransforms,
    List<LayerEdit> inlayEdits,
    int oldLen,
    int newLen,
  ) {
    final oldCursor = old._transforms.cursor(_dim);
    final newCursor = newTransforms.cursor(_dim);
    bool onFold(Cursor<_Transform, _Summary, _Summary> cursor) =>
        cursor.item?.isFold ?? false;

    final widened = <List<int>>[];
    for (var i = 0; i < inlayEdits.length; i++) {
      final edit = inlayEdits[i];
      var oldStart = edit.oldStart;
      var oldEnd = edit.oldEnd;
      var newStart = edit.newStart;
      var newEnd = edit.newEnd;
      final previous = widened.isEmpty ? null : widened.last;
      var mergeWithPrevious = previous != null && previous[1] >= oldStart;
      if (!mergeWithPrevious) {
        var limit = previous == null
            ? math.min(oldStart, newStart)
            : math.min(oldStart - previous[1], newStart - previous[3]);
        while (true) {
          oldCursor.seek(_inputOffset(oldStart), Bias.left);
          newCursor.seek(_inputOffset(newStart), Bias.left);
          final oldPull = onFold(oldCursor)
              ? oldStart - oldCursor.start.input.len
              : 0;
          final newPull = onFold(newCursor)
              ? newStart - newCursor.start.input.len
              : 0;
          final pull = math.min(math.max(oldPull, newPull), limit);
          if (pull == 0) {
            break;
          }
          oldStart -= pull;
          newStart -= pull;
          limit -= pull;
        }
        mergeWithPrevious = previous != null && limit == 0;
      }

      var limit = i + 1 < inlayEdits.length
          ? math.min(
              inlayEdits[i + 1].oldStart - oldEnd,
              inlayEdits[i + 1].newStart - newEnd,
            )
          : math.min(oldLen - oldEnd, newLen - newEnd);
      while (true) {
        oldCursor.seek(_inputOffset(oldEnd), Bias.right);
        newCursor.seek(_inputOffset(newEnd), Bias.right);
        final oldExtension = onFold(oldCursor)
            ? oldCursor.end.input.len - oldEnd
            : 0;
        final newExtension = onFold(newCursor)
            ? newCursor.end.input.len - newEnd
            : 0;
        final extension = math.min(math.max(oldExtension, newExtension), limit);
        if (extension == 0) {
          break;
        }
        oldEnd += extension;
        newEnd += extension;
        limit -= extension;
      }

      if (mergeWithPrevious && previous != null) {
        previous[1] = oldEnd;
        previous[3] = newEnd;
      } else {
        widened.add([oldStart, oldEnd, newStart, newEnd]);
      }
    }

    final edits = <LayerEdit>[];
    for (final edit in widened) {
      oldCursor.seek(_inputOffset(edit[0]), Bias.left);
      final oldStart =
          oldCursor.start.output.len + (edit[0] - oldCursor.start.input.len);
      oldCursor.seek(_inputOffset(edit[1]), Bias.right);
      final oldEnd =
          oldCursor.start.output.len + (edit[1] - oldCursor.start.input.len);
      newCursor.seek(_inputOffset(edit[2]), Bias.left);
      final newStart =
          newCursor.start.output.len + (edit[2] - newCursor.start.input.len);
      newCursor.seek(_inputOffset(edit[3]), Bias.right);
      final newEnd =
          newCursor.start.output.len + (edit[3] - newCursor.start.input.len);
      edits.add(LayerEdit(oldStart, oldEnd, newStart, newEnd));
    }
    return consolidateEdits(edits);
  }
}

/// the text with its folds at one time. an offset or point "of the folds"
/// counts a fold as its placeholder.
class FoldSnapshot {
  FoldSnapshot._(
    this.inlaySnapshot,
    this._transforms,
    this._folds,
    this.version,
  );

  final InlaySnapshot inlaySnapshot;
  final SumTree<_Transform, _Summary> _transforms;
  final SumTree<Fold, _FoldSummary> _folds;
  final int version;

  /// the folds, in the order of where they start
  List<Fold> get folds => _folds.items.toList();
  bool get hasFolds => !_folds.isEmpty;
  int get foldCount => _folds.summary.count;

  int get len => _transforms.summary.output.len;
  Point get maxPoint => _transforms.summary.output.lines;
  TextSummary get textSummary => _transforms.summary.output;
  int get longestRow => _transforms.summary.output.longestRow;

  /// the fold point of the inlay point [point], which in a fold is its start,
  /// or its end with [Bias.right]
  Point toFoldPoint(Point point, Bias bias) {
    final (start, end, item) = _transforms.find(
      _dim,
      _inputPoint(point),
      Bias.right,
    );
    if (item != null && item.isFold) {
      return bias == Bias.left || point == start.input.lines
          ? start.output.lines
          : end.output.lines;
    }
    final at = start.output.lines + (point - start.input.lines);
    return at < end.output.lines ? at : end.output.lines;
  }

  /// the fold offset of the inlay offset [offset]
  int toFoldOffset(int offset, Bias bias) {
    final (start, end, item) = _transforms.find(
      _dim,
      _inputOffset(offset),
      Bias.right,
    );
    if (item != null && item.isFold) {
      return bias == Bias.left || offset == start.input.len
          ? start.output.len
          : end.output.len;
    }
    return math.min(
      start.output.len + (offset - start.input.len),
      end.output.len,
    );
  }

  /// the inlay point of the fold point [point]
  Point toInlayPoint(Point point) {
    final (start, _, _) = _transforms.find(
      _dim,
      _outputPoint(point),
      Bias.right,
    );
    return start.input.lines + (point - start.output.lines);
  }

  /// the inlay offset of the fold offset [offset]
  int toInlayOffset(int offset) {
    final (start, _, _) = _transforms.find(
      _dim,
      _outputOffset(offset),
      Bias.right,
    );
    return start.input.len + (offset - start.output.len);
  }

  /// the fold offset of the fold point [point]
  int toOffset(Point point) {
    final (start, _, item) = _transforms.find(
      _dim,
      _outputPoint(point),
      Bias.right,
    );
    final overshoot = point - start.output.lines;
    var offset = start.output.len;
    if (overshoot != Point.zero) {
      if (item == null) {
        return len;
      }
      if (item.isFold) {
        return offset + overshoot.column;
      }
      offset +=
          inlaySnapshot.toOffset(start.input.lines + overshoot) -
          start.input.len;
    }
    return offset;
  }

  /// the fold point of the fold offset [offset]
  Point toPoint(int offset) {
    final (start, _, item) = _transforms.find(
      _dim,
      _outputOffset(offset),
      Bias.right,
    );
    final Point overshoot;
    if (item == null || item.isFold) {
      overshoot = Point(0, offset - start.output.len);
    } else {
      final inlayOffset = start.input.len + (offset - start.output.len);
      overshoot = inlaySnapshot.toPoint(inlayOffset) - start.input.lines;
    }
    return start.output.lines + overshoot;
  }

  int lineLen(int row) {
    final start = toOffset(Point(row, 0));
    final end = row >= maxPoint.row ? len : toOffset(Point(row + 1, 0)) - 1;
    return end - start;
  }

  /// whether the buffer offset [offset] is inside a fold
  bool intersectsFold(int offset) {
    final inlayOffset = inlaySnapshot.toInlayOffset(offset);
    final (_, _, item) = _transforms.find(
      _dim,
      _inputOffset(inlayOffset),
      Bias.right,
    );
    return item != null && item.isFold;
  }

  /// whether row [bufferRow] of the buffer has a fold on it
  bool isLineFolded(int bufferRow) {
    var inlayPoint = inlaySnapshot.toInlayPoint(Point(bufferRow, 0));
    final cursor = _transforms.cursor(_dim)
      ..seek(_inputPoint(inlayPoint), Bias.right);
    while (true) {
      final item = cursor.item;
      if (item == null) {
        return false;
      }
      if (inlaySnapshot.toBufferPoint(inlayPoint).row != bufferRow) {
        return false;
      }
      if (item.isFold) {
        return true;
      }
      if (cursor.end.input.lines.row == inlayPoint.row) {
        cursor.next();
      } else {
        inlayPoint = inlayPoint + const Point(1, 0);
        cursor.seek(_inputPoint(inlayPoint), Bias.right);
      }
    }
  }

  /// the folds that have any of the buffer from [start] to [end]
  Iterable<Fold> foldsInRange(int start, int end) sync* {
    final cursor = _intersectingFolds(
      inlaySnapshot.bufferSnapshot,
      _folds,
      start,
      end,
      false,
    );
    while (true) {
      final fold = cursor.item;
      if (fold == null) {
        return;
      }
      yield fold;
      cursor.next();
    }
  }

  /// the range of the placeholder that the fold point [point] is on, if any
  (Point, Point)? placeholderRangeAt(Point point) {
    final (start, end, item) = _transforms.find(
      _dim,
      _outputPoint(point),
      Bias.right,
    );
    return item != null && item.isFold
        ? (start.output.lines, end.output.lines)
        : null;
  }

  /// [point] moved to a place a cursor can be at, which is not inside a
  /// placeholder
  Point clipPoint(Point point, Bias bias) {
    final (start, end, item) = _transforms.find(
      _dim,
      _outputPoint(point),
      Bias.right,
    );
    if (item == null) {
      return maxPoint;
    }
    final transformStart = start.output.lines;
    if (item.isFold) {
      return point == transformStart || bias == Bias.left
          ? transformStart
          : end.output.lines;
    }
    final inlayPoint = start.input.lines + (point - transformStart);
    final clipped = inlaySnapshot.clipPoint(inlayPoint, bias);
    return transformStart + (clipped - start.input.lines);
  }

  int clipOffset(int offset, Bias bias) =>
      offset > len ? len : toOffset(clipPoint(toPoint(offset), bias));

  /// what the text from the fold point [start] to [end] comes to
  TextSummary textSummaryForRange(Point start, Point end) {
    var summary = TextSummary.zero;
    final cursor = _transforms.cursor(_dim)
      ..seek(_outputPoint(start), Bias.right);
    final first = cursor.item;
    if (first != null) {
      final from = start - cursor.start.output.lines;
      final stop = end < cursor.end.output.lines
          ? end
          : cursor.end.output.lines;
      final to = stop - cursor.start.output.lines;
      final placeholder = first.placeholder;
      if (placeholder != null) {
        summary = TextSummary.of(placeholder, from.column, to.column);
      } else {
        summary = inlaySnapshot.textSummaryForRange(
          inlaySnapshot.toOffset(cursor.start.input.lines + from),
          inlaySnapshot.toOffset(cursor.start.input.lines + to),
        );
      }
    }
    if (end > cursor.end.output.lines) {
      cursor.next();
      summary += cursor.summary(_dim, _outputPoint(end), Bias.right).output;
      final last = cursor.item;
      if (last != null) {
        final to = end - cursor.start.output.lines;
        final placeholder = last.placeholder;
        if (placeholder != null) {
          summary += TextSummary.of(placeholder, 0, to.column);
        } else {
          summary += inlaySnapshot.textSummaryForRange(
            inlaySnapshot.toOffset(cursor.start.input.lines),
            inlaySnapshot.toOffset(cursor.start.input.lines + to),
          );
        }
      }
    }
    return summary;
  }

  /// the pieces of the text from the fold offset [start] to [end]: the text
  /// of a fold's placeholder with its fold, of an inlay with its inlay, or of
  /// the buffer
  Iterable<FoldChunk> chunks(
    int start,
    int end, [
    Highlights highlights = Highlights.none,
  ]) sync* {
    final cursor = _transforms.cursor(_dim)
      ..seek(_outputOffset(start), Bias.right);
    while (true) {
      final item = cursor.item;
      final itemStart = cursor.start.output.len;
      if (item == null || itemStart >= end) {
        return;
      }
      final from = math.max(start, itemStart) - itemStart;
      final to = math.min(end, cursor.end.output.len) - itemStart;
      if (to > from) {
        final placeholder = item.placeholder;
        if (placeholder != null) {
          yield FoldChunk(placeholder.substring(from, to), fold: item.fold);
        } else {
          final inlayStart = cursor.start.input.len;
          for (final chunk in inlaySnapshot.chunks(
            inlayStart + from,
            inlayStart + to,
            highlights,
          )) {
            yield FoldChunk(chunk.text, inlay: chunk.inlay, style: chunk.style);
          }
        }
      }
      cursor.next();
    }
  }

  /// the text with its folds
  String get text => [for (final chunk in chunks(0, len)) chunk.text].join();
}

/// a piece of the text of the fold layer
class FoldChunk {
  const FoldChunk(this.text, {this.fold, this.inlay, this.style});

  final String text;

  /// how the text is drawn, from the highlights that are on it
  final HighlightStyle? style;

  /// the fold that the text is the placeholder of
  final Fold? fold;

  /// the inlay that the text is of
  final Inlay? inlay;
}
