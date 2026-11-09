import 'dart:math' as math;

import 'point.dart';

/// the most a leaf of the rope holds, in UTF-16 code units
const int _maxLeaf = 1024;

/// text that never changes: an edit makes a new rope that shares what it can
/// with the old one, so a snapshot can be held while editing goes on. lines
/// end in `\n` only; the buffer takes the other line endings out first.
///
/// the text is kept as a balanced tree of chunks. each node knows how long its
/// text is and how many lines it has, which is how a line or an offset is
/// found without reading the text before it.
class Rope {
  const Rope._(this._root);

  factory Rope(String text) => Rope._(_build(text));

  static const empty = Rope._(null);

  final _Node? _root;

  int get length => _root?.length ?? 0;
  bool get isEmpty => length == 0;

  /// the number of lines, which is one more than the number of `\n`; an empty
  /// text has one empty line
  int get lineCount => (_root?.newlines ?? 0) + 1;

  /// the text of the chunks, in order
  Iterable<String> get chunks sync* {
    final root = _root;
    if (root == null) {
      return;
    }
    final stack = <_Node>[root];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      if (node is _Leaf) {
        yield node.text;
      } else {
        final branch = node as _Branch;
        stack.add(branch.right);
        stack.add(branch.left);
      }
    }
  }

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
    _write(_root!, start, end, out);
    return out.toString();
  }

  static void _write(_Node node, int start, int end, StringBuffer out) {
    if (start <= 0 && end >= node.length) {
      _writeAll(node, out);
      return;
    }
    if (node is _Leaf) {
      out.write(
        node.text.substring(math.max(start, 0), math.min(end, node.length)),
      );
      return;
    }
    final branch = node as _Branch;
    final split = branch.left.length;
    if (start < split) {
      _write(branch.left, start, end, out);
    }
    if (end > split) {
      _write(branch.right, start - split, end - split, out);
    }
  }

  static void _writeAll(_Node node, StringBuffer out) {
    if (node is _Leaf) {
      out.write(node.text);
    } else {
      final branch = node as _Branch;
      _writeAll(branch.left, out);
      _writeAll(branch.right, out);
    }
  }

  int codeUnitAt(int offset) {
    RangeError.checkValidIndex(offset, this, 'offset', length);
    var node = _root!;
    var at = offset;
    while (node is _Branch) {
      final split = node.left.length;
      if (at < split) {
        node = node.left;
      } else {
        at -= split;
        node = node.right;
      }
    }
    return (node as _Leaf).text.codeUnitAt(at);
  }

  /// the first [offset] code units, and what follows them
  (Rope, Rope) split(int offset) {
    RangeError.checkValueInInterval(offset, 0, length, 'offset');
    final root = _root;
    if (root == null) {
      return (empty, empty);
    }
    final (a, b) = _split(root, offset);
    return (Rope._(a), Rope._(b));
  }

  Rope operator +(Rope other) => Rope._(_concat(_root, other._root));

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
    final root = _root;
    if (root == null || row > root.newlines) {
      return length;
    }
    return _offsetAfterNewline(root, row);
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
    final root = _root;
    return root == null ? 0 : _newlinesBefore(root, offset);
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

  static int _offsetAfterNewline(_Node node, int n) {
    var at = 0;
    var node0 = node;
    var left = n;
    while (node0 is _Branch) {
      final inLeft = node0.left.newlines;
      if (left <= inLeft) {
        node0 = node0.left;
      } else {
        left -= inLeft;
        at += node0.left.length;
        node0 = node0.right;
      }
    }
    final text = (node0 as _Leaf).text;
    var index = -1;
    for (var i = 0; i < left; i++) {
      index = text.indexOf('\n', index + 1);
    }
    return at + index + 1;
  }

  static int _newlinesBefore(_Node node, int offset) {
    var count = 0;
    var node0 = node;
    var at = offset;
    while (node0 is _Branch) {
      final split = node0.left.length;
      if (at <= split) {
        node0 = node0.left;
      } else {
        count += node0.left.newlines;
        at -= split;
        node0 = node0.right;
      }
    }
    return count + _countNewlines((node0 as _Leaf).text, at);
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

abstract class _Node {
  int get length;
  int get newlines;
  int get height;
}

class _Leaf implements _Node {
  _Leaf(this.text) : newlines = _countNewlines(text, text.length);

  final String text;

  @override
  final int newlines;

  @override
  int get length => text.length;

  @override
  int get height => 0;
}

class _Branch implements _Node {
  _Branch(this.left, this.right)
    : length = left.length + right.length,
      newlines = left.newlines + right.newlines,
      height = 1 + math.max(left.height, right.height);

  final _Node left;
  final _Node right;

  @override
  final int length;

  @override
  final int newlines;

  @override
  final int height;
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

_Node? _build(String text) {
  if (text.isEmpty) {
    return null;
  }
  final leaves = <_Node>[];
  var start = 0;
  while (start < text.length) {
    var end = math.min(start + _maxLeaf, text.length);
    // a pair of surrogates is kept in one chunk
    if (end < text.length && _isLowSurrogate(text.codeUnitAt(end))) {
      end--;
    }
    leaves.add(_Leaf(text.substring(start, end)));
    start = end;
  }
  return _balanced(leaves, 0, leaves.length);
}

bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

_Node _balanced(List<_Node> nodes, int start, int end) {
  if (end - start == 1) {
    return nodes[start];
  }
  final middle = (start + end) ~/ 2;
  return _Branch(
    _balanced(nodes, start, middle),
    _balanced(nodes, middle, end),
  );
}

(_Node?, _Node?) _split(_Node node, int offset) {
  if (offset <= 0) {
    return (null, node);
  }
  if (offset >= node.length) {
    return (node, null);
  }
  if (node is _Leaf) {
    return (
      _Leaf(node.text.substring(0, offset)),
      _Leaf(node.text.substring(offset)),
    );
  }
  final branch = node as _Branch;
  final at = branch.left.length;
  if (offset == at) {
    return (branch.left, branch.right);
  }
  if (offset < at) {
    final (a, b) = _split(branch.left, offset);
    return (a, _concat(b, branch.right));
  }
  final (a, b) = _split(branch.right, offset - at);
  return (_concat(branch.left, a), b);
}

_Node? _concat(_Node? a, _Node? b) {
  if (a == null) {
    return b;
  }
  if (b == null) {
    return a;
  }
  // small leaves are merged, so that edits do not leave a rope of crumbs
  if (a is _Leaf && b is _Leaf && a.length + b.length <= _maxLeaf) {
    return _Leaf(a.text + b.text);
  }
  if (a.height > b.height + 1) {
    final branch = a as _Branch;
    return _node(branch.left, _concat(branch.right, b)!);
  }
  if (b.height > a.height + 1) {
    final branch = b as _Branch;
    return _node(_concat(a, branch.left)!, branch.right);
  }
  return _node(a, b);
}

/// a branch over [left] and [right], turned about when one is too much taller
_Node _node(_Node left, _Node right) {
  if (left.height > right.height + 1) {
    final l = left as _Branch;
    if (l.left.height >= l.right.height) {
      return _Branch(l.left, _node(l.right, right));
    }
    final lr = l.right as _Branch;
    return _Branch(_node(l.left, lr.left), _node(lr.right, right));
  }
  if (right.height > left.height + 1) {
    final r = right as _Branch;
    if (r.right.height >= r.left.height) {
      return _Branch(_node(left, r.left), r.right);
    }
    final rl = r.left as _Branch;
    return _Branch(_node(left, rl.left), _node(rl.right, r.right));
  }
  return _Branch(left, right);
}
