import '../editor_core/rope.dart';
import 'lsp_client.dart';

typedef _Point = (int row, int column);

/// where a diagnostic is drawn in [text], as offsets: the range the server
/// gave, made to hold something that can be underlined.
///
/// the range is clipped to the text. an empty range grows by one character to
/// the right, or, when the line ends there, by one to the left. a range that
/// is only the end of a line, from where it ends to the start of the next row,
/// is the last character of that line.
(int, int) diagnosticOffsets(Rope text, LspRange range) {
  final lastRow = text.lineCount - 1;

  bool isHigh(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
  bool isLow(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

  // the nearest place that is on a character, going [right] or left when the
  // column is in the middle of a pair of code units
  _Point clip(int row, int column, {required bool right}) {
    if (row > lastRow) {
      return (lastRow, text.lineLength(lastRow));
    }
    final length = text.lineLength(row < 0 ? 0 : row);
    final line = row < 0 ? 0 : row;
    var clipped = column.clamp(0, length);
    if (clipped > 0 && clipped < length) {
      final at = text.lineStart(line) + clipped;
      if (isLow(text.codeUnitAt(at)) && isHigh(text.codeUnitAt(at - 1))) {
        clipped += right ? 1 : -1;
      }
    }
    return (line, clipped);
  }

  var start = clip(range.start.line, range.start.character, right: false);
  var end = clip(range.end.line, range.end.character, right: true);
  if (start == end) {
    end = clip(end.$1, end.$2 + 1, right: true);
    if (start == end && end.$2 > 0) {
      start = clip(start.$1, start.$2 - 1, right: false);
    }
  } else if (end == (start.$1 + 1, 0)) {
    if (start == (start.$1, text.lineLength(start.$1))) {
      end = start;
      if (start.$2 > 0) {
        start = clip(start.$1, start.$2 - 1, right: false);
      }
    }
  }
  int offset(_Point point) => text.lineStart(point.$1) + point.$2;
  return (offset(start), offset(end));
}
