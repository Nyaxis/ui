import 'dart:math' as math;

import '../buffer.dart' show Anchor, BufferSnapshot;
import '../highlight.dart';
import '../point.dart';
import '../rope.dart';
import '../sum_tree.dart';
import '../text_summary.dart';
import 'layer_edit.dart';

/// text that is shown in the text without being in it, such as the hint of a
/// type or what is predicted to be typed next
class Inlay {
  Inlay({
    required this.id,
    required this.position,
    required this.text,
    this.style,
  }) : summary = TextSummary.of(text);

  final int id;

  /// how its text is drawn
  final HighlightStyle? style;

  /// where in the text it is shown, which stays with the text as it is
  /// edited
  final Anchor position;
  final String text;
  final TextSummary summary;

  /// which side of text typed at its place it stays on: with [Bias.left] what
  /// is typed there comes after it, and with [Bias.right] before it
  Bias get bias => position.bias;
}

sealed class _Transform {
  const _Transform();
}

/// text of the buffer, shown as it is
class _Isomorphic extends _Transform {
  const _Isomorphic(this.summary);

  final TextSummary summary;
}

class _InlayTransform extends _Transform {
  const _InlayTransform(this.inlay);

  final Inlay inlay;
}

class _Summary {
  const _Summary(this.input, this.output);

  static const zero = _Summary(TextSummary.zero, TextSummary.zero);

  /// the text before the inlays are put in
  final TextSummary input;

  /// the text with the inlays
  final TextSummary output;

  bool get hasInlays => input.len != output.len;
}

class _Ops extends SummaryOps<_Transform, _Summary> {
  const _Ops();

  @override
  _Summary get zero => _Summary.zero;

  @override
  _Summary add(_Summary a, _Summary b) =>
      _Summary(a.input + b.input, a.output + b.output);

  @override
  _Summary summarize(_Transform item) => switch (item) {
    _Isomorphic() => _Summary(item.summary, item.summary),
    _InlayTransform() => _Summary(TextSummary.zero, item.inlay.summary),
  };
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

/// adds text of the buffer to [tree], joined to the text before it
SumTree<_Transform, _Summary> _pushIsomorphic(
  SumTree<_Transform, _Summary> tree,
  TextSummary summary,
) {
  if (summary.len == 0) {
    return tree;
  }
  final last = tree.last;
  if (last is _Isomorphic) {
    return tree.updateLast((_) => _Isomorphic(last.summary + summary));
  }
  return tree.push(_Isomorphic(summary));
}

/// decides where the inlays are shown. it is the first layer of the display:
/// its text is the text of the buffer with the text of the inlays in it.
class InlayMap {
  InlayMap(BufferSnapshot buffer)
    : _snapshot = InlaySnapshot._(buffer, _initial(buffer.text), 0);

  InlaySnapshot _snapshot;

  /// in the order of their anchors, which edits to the text do not change
  final List<Inlay> _inlays = [];

  static SumTree<_Transform, _Summary> _initial(Rope buffer) =>
      SumTree<_Transform, _Summary>(_ops).push(_Isomorphic(buffer.summary));

  InlaySnapshot get snapshot => _snapshot;

  /// the inlays, in the order they are shown
  List<Inlay> get inlays => List.unmodifiable(_inlays);

  /// follows the buffer to [bufferSnapshot], which [bufferEdits] were made
  /// to, and gives the layout with what changed in it
  (InlaySnapshot, List<LayerEdit>) sync(
    BufferSnapshot bufferSnapshot,
    List<LayerEdit> bufferEdits,
  ) {
    final snapshot = _snapshot;
    final buffer = bufferSnapshot.text;
    if (bufferEdits.isEmpty) {
      _snapshot = InlaySnapshot._(
        bufferSnapshot,
        snapshot._transforms,
        snapshot.bufferSnapshot.version == bufferSnapshot.version
            ? snapshot.version
            : snapshot.version + 1,
      );
      return (_snapshot, const []);
    }
    if (_inlays.isEmpty && !snapshot._transforms.summary.hasInlays) {
      // without inlays the text is passed through as it is
      _snapshot = InlaySnapshot._(
        bufferSnapshot,
        _initial(buffer),
        snapshot.version + 1,
      );
      return (_snapshot, List.of(bufferEdits));
    }

    final inlayEdits = <LayerEdit>[];
    var newTransforms = SumTree<_Transform, _Summary>(_ops);
    final cursor = snapshot._transforms.cursor(_dim);
    for (var e = 0; e < bufferEdits.length; e++) {
      final edit = bufferEdits[e];
      newTransforms = newTransforms.append(
        cursor.slice(_inputOffset(edit.oldStart), Bias.left),
      );
      final item = cursor.item;
      if (item is _Isomorphic && cursor.end.input.len == edit.oldStart) {
        newTransforms = _pushIsomorphic(newTransforms, item.summary);
        cursor.next();
      }

      // the inlays and transforms that the edit has in it are taken out
      final oldStart =
          cursor.start.output.len + (edit.oldStart - cursor.start.input.len);
      cursor.seek(_inputOffset(edit.oldEnd), Bias.right);
      final oldEnd =
          cursor.start.output.len + (edit.oldEnd - cursor.start.input.len);

      // what did not change before the edit
      newTransforms = _pushIsomorphic(
        newTransforms,
        buffer.textSummaryForRange(
          newTransforms.summary.input.len,
          edit.newStart,
        ),
      );
      final newStart = newTransforms.summary.output.len;

      var index = _firstInlayAtOrAfter(bufferSnapshot, edit.newStart);
      for (; index < _inlays.length; index++) {
        final inlay = _inlays[index];
        // one whose text was taken out is not shown
        if (!bufferSnapshot.isValid(inlay.position)) {
          continue;
        }
        final offset = bufferSnapshot.offsetForAnchor(inlay.position);
        if (offset > edit.newEnd) {
          break;
        }
        newTransforms = _pushIsomorphic(
          newTransforms,
          buffer.textSummaryForRange(newTransforms.summary.input.len, offset),
        );
        newTransforms = newTransforms.push(_InlayTransform(inlay));
      }

      // the rest of the edit
      newTransforms = _pushIsomorphic(
        newTransforms,
        buffer.textSummaryForRange(
          newTransforms.summary.input.len,
          edit.newEnd,
        ),
      );
      final newEnd = newTransforms.summary.output.len;
      pushLayerEdit(inlayEdits, LayerEdit(oldStart, oldEnd, newStart, newEnd));

      // when the next edit is not in the transform this one ended in, what
      // is left of it is put in
      final transformEnd = cursor.end.input.len;
      if (e + 1 == bufferEdits.length ||
          bufferEdits[e + 1].oldStart >= transformEnd) {
        newTransforms = _pushIsomorphic(
          newTransforms,
          buffer.textSummaryForRange(
            newTransforms.summary.input.len,
            edit.newEnd + (transformEnd - edit.oldEnd),
          ),
        );
        cursor.next();
      }
    }

    newTransforms = newTransforms.append(cursor.suffix());
    if (newTransforms.isEmpty) {
      newTransforms = newTransforms.push(const _Isomorphic(TextSummary.zero));
    }
    _snapshot = InlaySnapshot._(
      bufferSnapshot,
      newTransforms,
      snapshot.version + 1,
    );
    return (_snapshot, inlayEdits);
  }

  int _firstInlayAtOrAfter(BufferSnapshot buffer, int offset) {
    var low = 0;
    var high = _inlays.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (buffer.offsetForAnchor(_inlays[middle].position) >= offset) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    return low;
  }

  /// takes out the inlays with the ids of [toRemove], and puts in [toInsert]
  (InlaySnapshot, List<LayerEdit>) splice(
    Iterable<int> toRemove,
    Iterable<Inlay> toInsert,
  ) {
    final buffer = _snapshot.bufferSnapshot;
    final offsets = <int>{};
    final remove = toRemove.toSet();
    _inlays.removeWhere((inlay) {
      if (remove.contains(inlay.id)) {
        offsets.add(buffer.offsetForAnchor(inlay.position));
        return true;
      }
      return false;
    });
    for (final inlay in toInsert) {
      // an inlay of no text is not one
      if (inlay.text.isEmpty) {
        continue;
      }
      // after the ones that are at the same anchor
      var low = 0;
      var high = _inlays.length;
      while (low < high) {
        final middle = (low + high) >> 1;
        if (buffer.compareAnchors(_inlays[middle].position, inlay.position) <=
            0) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      _inlays.insert(low, inlay);
      offsets.add(buffer.offsetForAnchor(inlay.position));
    }
    final sorted = offsets.toList()..sort();
    return sync(buffer, [
      for (final offset in sorted) LayerEdit(offset, offset, offset, offset),
    ]);
  }
}

/// the text with its inlays at one time. an offset or point "of the inlays"
/// counts the text of the inlays too.
class InlaySnapshot {
  InlaySnapshot._(this.bufferSnapshot, this._transforms, this.version);

  final BufferSnapshot bufferSnapshot;

  /// the text of the buffer
  Rope get buffer => bufferSnapshot.text;
  final SumTree<_Transform, _Summary> _transforms;
  final int version;

  /// how long the text is with its inlays
  int get len => _transforms.summary.output.len;
  Point get maxPoint => _transforms.summary.output.lines;
  TextSummary get textSummary => _transforms.summary.output;

  /// the place of the inlay offset [offset]
  Point toPoint(int offset) {
    final (start, _, item) = _transforms.find(
      _dim,
      _outputOffset(offset),
      Bias.right,
    );
    final overshoot = offset - start.output.len;
    switch (item) {
      case _Isomorphic():
        final bufferStart = start.input.len;
        return start.output.lines +
            (buffer.offsetToPoint(bufferStart + overshoot) -
                buffer.offsetToPoint(bufferStart));
      case _InlayTransform():
        return start.output.lines + offsetToPointIn(item.inlay.text, overshoot);
      case null:
        return maxPoint;
    }
  }

  /// the inlay offset of the inlay point [point]
  int toOffset(Point point) {
    final (start, _, item) = _transforms.find(
      _dim,
      _outputPoint(point),
      Bias.right,
    );
    final overshoot = point - start.output.lines;
    switch (item) {
      case _Isomorphic():
        final bufferStart = start.input.lines;
        return start.output.len +
            (buffer.pointToOffset(bufferStart + overshoot) -
                buffer.pointToOffset(bufferStart));
      case _InlayTransform():
        return start.output.len + pointToOffsetIn(item.inlay.text, overshoot);
      case null:
        return len;
    }
  }

  /// the place in the buffer of the inlay point [point], which for one in an
  /// inlay is where the inlay is
  Point toBufferPoint(Point point) {
    final (start, _, item) = _transforms.find(
      _dim,
      _outputPoint(point),
      Bias.right,
    );
    return switch (item) {
      _Isomorphic() => start.input.lines + (point - start.output.lines),
      _InlayTransform() => start.input.lines,
      null => buffer.maxPoint,
    };
  }

  /// the offset in the buffer of the inlay offset [offset]
  int toBufferOffset(int offset) {
    final (start, _, item) = _transforms.find(
      _dim,
      _outputOffset(offset),
      Bias.right,
    );
    return switch (item) {
      _Isomorphic() => start.input.len + (offset - start.output.len),
      _InlayTransform() => start.input.len,
      null => buffer.length,
    };
  }

  /// the inlay offset of the offset [offset] of the buffer: after the inlays
  /// there that text typed there comes after, and before the others
  int toInlayOffset(int offset) {
    final cursor = _transforms.cursor(_dim)
      ..seek(_inputOffset(offset), Bias.left);
    while (true) {
      final item = cursor.item;
      switch (item) {
        case _Isomorphic():
          if (offset == cursor.end.input.len) {
            while (true) {
              final next = cursor.nextItem;
              if (next is _InlayTransform && next.inlay.bias != Bias.right) {
                cursor.next();
              } else {
                break;
              }
            }
            return cursor.end.output.len;
          }
          return cursor.start.output.len + (offset - cursor.start.input.len);
        case _InlayTransform():
          if (item.inlay.bias == Bias.left) {
            cursor.next();
          } else {
            return cursor.start.output.len;
          }
        case null:
          return len;
      }
    }
  }

  /// the inlay point of the point [point] of the buffer
  Point toInlayPoint(Point point) {
    final cursor = _transforms.cursor(_dim)
      ..seek(_inputPoint(point), Bias.left);
    while (true) {
      final item = cursor.item;
      switch (item) {
        case _Isomorphic():
          if (point == cursor.end.input.lines) {
            while (true) {
              final next = cursor.nextItem;
              if (next is _InlayTransform && next.inlay.bias != Bias.right) {
                cursor.next();
              } else {
                break;
              }
            }
            return cursor.end.output.lines;
          }
          return cursor.start.output.lines + (point - cursor.start.input.lines);
        case _InlayTransform():
          if (item.inlay.bias == Bias.left) {
            cursor.next();
          } else {
            return cursor.start.output.lines;
          }
        case null:
          return maxPoint;
      }
    }
  }

  /// how long row [row] is, with the inlays on it
  int lineLen(int row) {
    final start = toOffset(Point(row, 0));
    final end = row >= maxPoint.row ? len : toOffset(Point(row + 1, 0)) - 1;
    return end - start;
  }

  /// [point] moved to a place a cursor can be at, which is not inside an
  /// inlay, and not on the side of one where text typed would not go
  Point clipPoint(Point point, Bias bias) {
    var at = point;
    var side = bias;
    final cursor = _transforms.cursor(_dim)..seek(_outputPoint(at), Bias.left);
    while (true) {
      final item = cursor.item;
      switch (item) {
        case _Isomorphic():
          if (cursor.start.output.lines == at) {
            final prev = cursor.prevItem;
            if (prev is _InlayTransform) {
              if (prev.inlay.bias == Bias.left) {
                return at;
              } else if (side == Bias.left) {
                cursor.prev();
              } else if (item.summary.firstLineChars == 0) {
                at = at + const Point(1, 0);
              } else {
                at = at + const Point(0, 1);
              }
            } else {
              return at;
            }
          } else if (cursor.end.output.lines == at) {
            final next = cursor.nextItem;
            if (next is _InlayTransform) {
              if (next.inlay.bias == Bias.right) {
                return at;
              } else if (side == Bias.right) {
                cursor.next();
              } else if (at.column == 0) {
                at = Point(at.row - 1, lineLen(at.row - 1));
              } else {
                at = Point(at.row, at.column - 1);
              }
            } else {
              return at;
            }
          } else {
            final overshoot = at - cursor.start.output.lines;
            final bufferPoint = cursor.start.input.lines + overshoot;
            final clipped = buffer.clipPoint(bufferPoint, side);
            final clippedPoint =
                cursor.start.output.lines +
                (clipped - cursor.start.input.lines);
            if (clippedPoint == at) {
              return clippedPoint;
            }
            at = clippedPoint;
          }
        case _InlayTransform():
          if (at == cursor.start.output.lines &&
              item.inlay.bias == Bias.right) {
            final prev = cursor.prevItem;
            if (prev is! _InlayTransform || prev.inlay.bias == Bias.left) {
              return at;
            }
          } else if (at == cursor.end.output.lines &&
              item.inlay.bias == Bias.left) {
            final next = cursor.nextItem;
            if (next is! _InlayTransform || next.inlay.bias == Bias.right) {
              return at;
            }
          }
          if (side == Bias.left) {
            at = cursor.start.output.lines;
            cursor.prev();
          } else {
            cursor.next();
            at = cursor.start.output.lines;
          }
        case null:
          side = side == Bias.left ? Bias.right : Bias.left;
          if (side == Bias.left) {
            at = cursor.start.output.lines;
            cursor.prev();
          } else {
            cursor.next();
            at = cursor.start.output.lines;
          }
      }
    }
  }

  /// what the text from the inlay offset [start] to [end] comes to
  TextSummary textSummaryForRange(int start, int end) {
    var summary = TextSummary.zero;
    final cursor = _transforms.cursor(_dim)
      ..seek(_outputOffset(start), Bias.right);
    final overshoot = start - cursor.start.output.len;
    final first = cursor.item;
    switch (first) {
      case _Isomorphic():
        final bufferStart = cursor.start.input.len;
        final suffixEnd =
            bufferStart +
            (math.min(cursor.end.output.len, end) - cursor.start.output.len);
        summary = buffer.textSummaryForRange(
          bufferStart + overshoot,
          suffixEnd,
        );
        cursor.next();
      case _InlayTransform():
        final suffixEnd =
            math.min(cursor.end.output.len, end) - cursor.start.output.len;
        summary = TextSummary.of(first.inlay.text, overshoot, suffixEnd);
        cursor.next();
      case null:
        break;
    }
    if (end > cursor.start.output.len) {
      summary += cursor.summary(_dim, _outputOffset(end), Bias.right).output;
      final rest = end - cursor.start.output.len;
      final last = cursor.item;
      switch (last) {
        case _Isomorphic():
          final prefixStart = cursor.start.input.len;
          summary += buffer.textSummaryForRange(
            prefixStart,
            prefixStart + rest,
          );
        case _InlayTransform():
          summary += TextSummary.of(last.inlay.text, 0, rest);
        case null:
          break;
      }
    }
    return summary;
  }

  /// the pieces of the text from the inlay offset [start] to [end], each the
  /// text of the buffer or of the inlay it is given with
  Iterable<InlayChunk> chunks(
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
      switch (item) {
        case _Isomorphic():
          final bufferStart = cursor.start.input.len;
          if (to > from) {
            for (final (piece, style) in highlightedBufferText(
              bufferSnapshot,
              bufferStart + from,
              bufferStart + to,
              buffer.chunksInRange(bufferStart + from, bufferStart + to),
              highlights,
            )) {
              yield InlayChunk(piece, style: style);
            }
          }
        case _InlayTransform():
          if (to > from) {
            yield InlayChunk(
              item.inlay.text.substring(from, to),
              inlay: item.inlay,
              style: item.inlay.style,
            );
          }
      }
      cursor.next();
    }
  }

  /// the text with its inlays
  String get text => [for (final chunk in chunks(0, len)) chunk.text].join();
}

/// a piece of the text of the inlay layer
class InlayChunk {
  const InlayChunk(this.text, {this.inlay, this.style});

  final String text;

  /// the inlay that the text is of, or null for text of the buffer
  final Inlay? inlay;

  /// how it is drawn, from the highlights that are on it
  final HighlightStyle? style;
}
