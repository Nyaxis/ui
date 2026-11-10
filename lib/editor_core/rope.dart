import 'dart:math' as math;

import 'point.dart';
import 'sum_tree.dart';
import 'text_summary.dart';

/// the most a chunk of the rope holds, in UTF-16 code units
const int _maxChunk = 1024;

/// what some chunks of text come to
class ChunkSummary {
  const ChunkSummary(this.text, this.chunks);

  static const zero = ChunkSummary(TextSummary.zero, 0);

  final TextSummary text;
  final int chunks;

  int get length => text.len;
  int get newlines => text.lines.row;
}

class _TextOps extends SummaryOps<String, ChunkSummary> {
  const _TextOps();

  @override
  ChunkSummary get zero => ChunkSummary.zero;

  @override
  ChunkSummary add(ChunkSummary a, ChunkSummary b) =>
      ChunkSummary(a.text + b.text, a.chunks + b.chunks);

  @override
  ChunkSummary summarize(String item) => ChunkSummary(TextSummary.of(item), 1);
}

const _ops = _TextOps();
const _whole = SummaryDimension<String, ChunkSummary>(_ops);

/// text that never changes: an edit makes a new rope that shares what it can
/// with the old one, so a snapshot can be held while editing goes on. lines
/// end in `\n` only; the buffer takes the other line endings out first.
///
/// the text is kept as chunks in a [SumTree], which knows how long the text
/// before a chunk is and how many lines it has, which is how a line or an
/// offset is found without reading the text before it.
class Rope {
  Rope._(this._tree);

  factory Rope(String text) {
    if (text.isEmpty) {
      return empty;
    }
    final chunks = <String>[];
    var start = 0;
    while (start < text.length) {
      var end = math.min(start + _maxChunk, text.length);
      // a pair of surrogates is kept in one chunk
      if (end < text.length && _isLowSurrogate(text.codeUnitAt(end))) {
        end--;
      }
      chunks.add(text.substring(start, end));
      start = end;
    }
    return Rope._(SumTree.fromIterable(_ops, chunks));
  }

  static final empty = Rope._(SumTree(_ops));

  final SumTree<String, ChunkSummary> _tree;

  int get length => _tree.summary.length;
  bool get isEmpty => length == 0;

  /// the number of lines, which is one more than the number of `\n`; an empty
  /// text has one empty line
  int get lineCount => _tree.summary.newlines + 1;

  /// what the whole text comes to
  TextSummary get summary => _tree.summary.text;

  /// the place of the end of the text
  Point get maxPoint => _tree.summary.text.lines;

  /// the text of the chunks, in order
  Iterable<String> get chunks => _tree.items;

  @override
  String toString() => substring(0, length);

  /// the text from [start] to [end], which are offsets
  String substring(int start, [int? end]) {
    end ??= length;
    RangeError.checkValidRange(start, end, length);
    if (start == end) {
      return '';
    }
    final out = StringBuffer();
    chunksInRange(start, end).forEach(out.write);
    return out.toString();
  }

  /// the text from [start] to [end] in pieces, each read only when it is
  /// asked for, so that what reads a little of a long range does not read
  /// it all
  Iterable<String> chunksInRange(int start, int end) sync* {
    RangeError.checkValidRange(start, end, length);
    if (start == end) {
      return;
    }
    final cursor = _tree.cursor(_whole)
      ..seek((p) => start.compareTo(p.length), Bias.right);
    while (true) {
      final chunk = cursor.item;
      if (chunk == null) {
        return;
      }
      final chunkStart = cursor.start.length;
      if (chunkStart >= end) {
        return;
      }
      yield chunk.substring(
        math.max(start - chunkStart, 0),
        math.min(end - chunkStart, chunk.length),
      );
      cursor.next();
    }
  }

  /// what the text from [start] to [end] comes to, without reading the
  /// chunks that are all in it
  TextSummary textSummaryForRange(int start, int end) {
    RangeError.checkValidRange(start, end, length);
    if (start == end) {
      return TextSummary.zero;
    }
    final cursor = _tree.cursor(_whole)
      ..seek((p) => start.compareTo(p.length), Bias.right);
    final first = cursor.item!;
    final firstStart = cursor.start.length;
    if (end <= firstStart + first.length) {
      return TextSummary.of(first, start - firstStart, end - firstStart);
    }
    var summary = TextSummary.of(first, start - firstStart);
    cursor.next();
    summary += cursor
        .summary(_whole, (p) => end.compareTo(p.length), Bias.right)
        .text;
    final last = cursor.item;
    if (last != null) {
      summary += TextSummary.of(last, 0, end - cursor.start.length);
    }
    return summary;
  }

  int codeUnitAt(int offset) {
    RangeError.checkValidIndex(offset, this, 'offset', length);
    final (start, _, chunk) = _tree.find(
      _whole,
      (p) => offset.compareTo(p.length),
      Bias.right,
    );
    return chunk!.codeUnitAt(offset - start.length);
  }

  /// the first [offset] code units, and what follows them
  (Rope, Rope) split(int offset) {
    RangeError.checkValueInInterval(offset, 0, length, 'offset');
    final cursor = _tree.cursor(_whole);
    var before = cursor.slice((p) => offset.compareTo(p.length), Bias.right);
    var after = SumTree(_ops);
    final chunk = cursor.item;
    final at = offset - cursor.start.length;
    if (chunk != null && at > 0) {
      before = before.push(chunk.substring(0, at));
      after = after.push(chunk.substring(at));
      cursor.next();
    }
    return (Rope._(before), Rope._(after.append(cursor.suffix())));
  }

  /// the text from [start] to [end] as a rope, which shares its chunks with
  /// this one
  Rope slice(int start, int end) {
    RangeError.checkValidRange(start, end, length);
    if (start == end) {
      return empty;
    }
    if (start == 0 && end == length) {
      return this;
    }
    return split(end).$1.split(start).$2;
  }

  Rope operator +(Rope other) {
    if (isEmpty) {
      return other;
    }
    if (other.isEmpty) {
      return this;
    }
    final last = _tree.last!;
    final first = other._tree.first!;
    // small chunks are joined, so that edits do not leave a rope of crumbs
    if (last.length + first.length > _maxChunk) {
      return Rope._(_tree.append(other._tree));
    }
    final chunks = _tree.summary.chunks;
    final head = _tree
        .cursor(_whole)
        .slice((p) => (chunks - 1).compareTo(p.chunks), Bias.right);
    final rest = other._tree.cursor(_whole)
      ..seek((p) => 1.compareTo(p.chunks), Bias.right);
    return Rope._(head.push(last + first).append(rest.suffix()));
  }

  /// this text with [start] to [end] replaced by [text]
  Rope replaceRange(int start, int end, String text) {
    RangeError.checkValidRange(start, end, length);
    final (before, rest) = split(start);
    final (_, after) = rest.split(end - start);
    return before + Rope(text) + after;
  }

  // lines and points

  /// the offset where line [row] starts; a row past the last is the end
  int lineStart(int row) {
    if (row <= 0) {
      return 0;
    }
    if (row > _tree.summary.newlines) {
      return length;
    }
    final (start, _, chunk) = _tree.find(
      _whole,
      (p) => row.compareTo(p.newlines),
      Bias.left,
    );
    var index = -1;
    for (var i = start.newlines; i < row; i++) {
      index = chunk!.indexOf('\n', index + 1);
    }
    return start.length + index + 1;
  }

  /// the offset where line [row] ends, before its `\n`
  int lineEnd(int row) {
    if (row >= lineCount - 1) {
      return length;
    }
    return lineStart(row + 1) - 1;
  }

  int lineLength(int row) => lineEnd(row) - lineStart(row);

  String lineText(int row) => substring(lineStart(row), lineEnd(row));

  /// the line that has [offset], which at the end of a line is that line
  int rowAt(int offset) {
    RangeError.checkValueInInterval(offset, 0, length, 'offset');
    final (start, _, chunk) = _tree.find(
      _whole,
      (p) => offset.compareTo(p.length),
      Bias.left,
    );
    if (chunk == null) {
      return start.newlines;
    }
    return start.newlines + _countNewlines(chunk, offset - start.length);
  }

  Point offsetToPoint(int offset) {
    final row = rowAt(offset);
    return Point(row, offset - lineStart(row));
  }

  /// the offset of [point]; a column past the end of its line is the end of
  /// the line, and a row past the last is the end of the text
  int pointToOffset(Point point) {
    if (point.row >= lineCount) {
      return length;
    }
    final start = lineStart(point.row);
    return start +
        math.min(math.max(point.column, 0), lineEnd(point.row) - start);
  }

  /// [offset] moved off the middle of a pair of surrogates, and into the text
  int clipOffset(int offset, Bias bias) {
    final at = math.min(math.max(offset, 0), length);
    if (at > 0 &&
        at < length &&
        _isLowSurrogate(codeUnitAt(at)) &&
        _isHighSurrogate(codeUnitAt(at - 1))) {
      return bias == Bias.left ? at - 1 : at + 1;
    }
    return at;
  }

  /// [point] moved to a place that the text has
  Point clipPoint(Point point, Bias bias) {
    final max = maxPoint;
    if (point.row > max.row) {
      return max;
    }
    final row = math.max(point.row, 0);
    final column = math.min(math.max(point.column, 0), lineLength(row));
    return offsetToPoint(clipOffset(lineStart(row) + column, bias));
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is Rope &&
        other.length == length &&
        other.toString() == toString();
  }

  @override
  int get hashCode => Object.hash(length, toString());
}

int _countNewlines(String text, int end) {
  var count = 0;
  for (var i = 0; i < end; i++) {
    if (text.codeUnitAt(i) == 0x0A) {
      count++;
    }
  }
  return count;
}

bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
