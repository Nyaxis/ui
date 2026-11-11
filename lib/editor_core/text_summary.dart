import 'point.dart';

/// what some text comes to: how long it is, how many lines it goes over, and
/// how long its lines are. lengths and columns count UTF-16 code units.
class TextSummary {
  const TextSummary({
    this.len = 0,
    this.lines = Point.zero,
    this.firstLineChars = 0,
    this.lastLineChars = 0,
    this.longestRow = 0,
    this.longestRowChars = 0,
  });

  /// the summary of [text], from [start] to [end]
  factory TextSummary.of(String text, [int start = 0, int? end]) {
    end ??= text.length;
    var row = 0;
    var lineStart = start;
    var firstLineChars = 0;
    var longestRow = 0;
    var longestRowChars = 0;
    for (var i = start; i < end; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        final chars = i - lineStart;
        if (row == 0) {
          firstLineChars = chars;
        }
        if (chars > longestRowChars) {
          longestRow = row;
          longestRowChars = chars;
        }
        row++;
        lineStart = i + 1;
      }
    }
    final lastLineChars = end - lineStart;
    if (row == 0) {
      firstLineChars = lastLineChars;
    }
    if (lastLineChars > longestRowChars) {
      longestRow = row;
      longestRowChars = lastLineChars;
    }
    return TextSummary(
      len: end - start,
      lines: Point(row, lastLineChars),
      firstLineChars: firstLineChars,
      lastLineChars: lastLineChars,
      longestRow: longestRow,
      longestRowChars: longestRowChars,
    );
  }

  static const zero = TextSummary();

  final int len;

  /// the place of the end of the text, counted from its start
  final Point lines;
  final int firstLineChars;
  final int lastLineChars;

  /// the first of the rows that are the longest, and how long it is
  final int longestRow;
  final int longestRowChars;

  TextSummary operator +(TextSummary other) {
    var longestRow = this.longestRow;
    var longestRowChars = this.longestRowChars;
    final joined = lastLineChars + other.firstLineChars;
    if (joined > longestRowChars) {
      longestRow = lines.row;
      longestRowChars = joined;
    }
    if (other.longestRowChars > longestRowChars) {
      longestRow = lines.row + other.longestRow;
      longestRowChars = other.longestRowChars;
    }
    return TextSummary(
      len: len + other.len,
      lines: lines + other.lines,
      firstLineChars: lines.row == 0
          ? firstLineChars + other.firstLineChars
          : firstLineChars,
      lastLineChars: other.lines.row == 0
          ? lastLineChars + other.firstLineChars
          : other.lastLineChars,
      longestRow: longestRow,
      longestRowChars: longestRowChars,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TextSummary &&
      other.len == len &&
      other.lines == lines &&
      other.firstLineChars == firstLineChars &&
      other.lastLineChars == lastLineChars &&
      other.longestRow == longestRow &&
      other.longestRowChars == longestRowChars;

  @override
  int get hashCode => Object.hash(
    len,
    lines,
    firstLineChars,
    lastLineChars,
    longestRow,
    longestRowChars,
  );

  @override
  String toString() =>
      'TextSummary(len $len, lines $lines, first $firstLineChars, '
      'last $lastLineChars, longest $longestRow:$longestRowChars)';
}

/// the place of [offset] in [text], counted from its start
Point offsetToPointIn(String text, int offset) {
  var row = 0;
  var lineStart = 0;
  for (var i = 0; i < offset; i++) {
    if (text.codeUnitAt(i) == 0x0A) {
      row++;
      lineStart = i + 1;
    }
  }
  return Point(row, offset - lineStart);
}

/// the offset of [point] in [text]; a column past the end of its line is the
/// end of the line
int pointToOffsetIn(String text, Point point) {
  var row = 0;
  var i = 0;
  while (row < point.row) {
    final next = text.indexOf('\n', i);
    if (next < 0) {
      return text.length;
    }
    i = next + 1;
    row++;
  }
  final lineEnd = text.indexOf('\n', i);
  final end = lineEnd < 0 ? text.length : lineEnd;
  return i + point.column > end ? end : i + point.column;
}
