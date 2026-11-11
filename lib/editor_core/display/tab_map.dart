import 'dart:math' as math;

import '../highlight.dart' show HighlightStyle, Highlights;
import '../point.dart';
import '../sum_tree.dart' show Bias;
import '../text_summary.dart';
import 'fold_map.dart';
import 'inlay_map.dart';
import 'layer_edit.dart';

/// a tab that starts at or after this column of its line is not expanded, and
/// is one cell wide, so that a line of very many tabs is not slow to lay out
const int defaultMaxExpansionColumn = 256;

/// the most a tab is expanded to
const int maxTabSize = 128;

bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

/// decides how wide tabs are. it is the third layer of the display: its text
/// is the text of the fold layer with each tab as the spaces to the next stop.
/// it keeps no tree of its own, since what a tab comes to is worked out from
/// the line it is on.
class TabMap {
  TabMap(FoldSnapshot foldSnapshot, int tabSize)
    : _snapshot = TabSnapshot._(
        foldSnapshot,
        math.min(math.max(tabSize, 1), maxTabSize),
        defaultMaxExpansionColumn,
        0,
      );

  TabSnapshot _snapshot;

  TabSnapshot get snapshot => _snapshot;

  /// for tests: where tabs stop being expanded
  TabSnapshot setMaxExpansionColumn(int column) => _snapshot = TabSnapshot._(
    _snapshot.foldSnapshot,
    _snapshot.tabSize,
    column,
    _snapshot.version,
  );

  /// follows the fold layer to [foldSnapshot], which [foldEdits] were made to,
  /// and gives the layout with what changed in it
  (TabSnapshot, List<PointEdit>) sync(
    FoldSnapshot foldSnapshot,
    List<LayerEdit> foldEdits,
    int tabSize,
  ) {
    final size = math.min(math.max(tabSize, 1), maxTabSize);
    final old = _snapshot;
    if (old.tabSize != size) {
      final oldMax = old.maxPoint;
      _snapshot = TabSnapshot._(
        foldSnapshot,
        size,
        old.maxExpansionColumn,
        old.version + 1,
      );
      return (
        _snapshot,
        [PointEdit(Point.zero, oldMax, Point.zero, _snapshot.maxPoint)],
      );
    }

    final version = old.foldSnapshot.version != foldSnapshot.version
        ? old.version + 1
        : old.version;
    final next = TabSnapshot._(
      foldSnapshot,
      size,
      old.maxExpansionColumn,
      version,
    );
    if (foldEdits.isEmpty) {
      _snapshot = next;
      return (next, const []);
    }

    // each edit is made to take in the next tab on its line, and the tabs
    // after it that went across the column where tabs stop being expanded:
    // how wide a tab is depends on where it is, so text that moved on a line
    // changes the tabs after it, though they were not touched
    final max = old.maxExpansionColumn;
    final oldFold = old.foldSnapshot;
    final widened = <LayerEdit>[];
    for (final edit in foldEdits) {
      final oldEndColumn = oldFold.toPoint(edit.oldEnd).column;
      final newEndColumn = foldSnapshot.toPoint(edit.newEnd).column;
      var offset = 0;
      int? firstTab;
      int? lastChanged;
      scan:
      for (final chunk in oldFold.chunks(edit.oldEnd, oldFold.len)) {
        final text = chunk.text;
        for (var i = 0; i < text.length; i++) {
          final unit = text.codeUnitAt(i);
          if (unit == 0x0A) {
            break scan;
          }
          if (unit == 0x09) {
            firstTab ??= offset;
            final wasExpanded = oldEndColumn + offset < max;
            final isExpanded = newEndColumn + offset < max;
            if (wasExpanded != isExpanded) {
              lastChanged = offset;
            } else if (!wasExpanded && !isExpanded) {
              break scan;
            }
          }
          offset++;
          if (oldEndColumn + offset >= max && newEndColumn + offset >= max) {
            // the tabs from here on are not expanded, before and after
            break scan;
          }
        }
      }
      final extension = lastChanged ?? firstTab;
      final wide = extension == null
          ? edit
          : LayerEdit(
              edit.oldStart,
              edit.oldEnd + extension + 1,
              edit.newStart,
              edit.newEnd + extension + 1,
            );
      // the ones that the widening made overlap are one
      if (widened.isNotEmpty && widened.last.oldEnd >= wide.oldStart) {
        final last = widened.last;
        widened[widened.length - 1] = LayerEdit(
          last.oldStart,
          wide.oldEnd,
          last.newStart,
          wide.newEnd,
        );
      } else {
        widened.add(wide);
      }
    }

    final tabEdits = [
      for (final edit in widened)
        PointEdit(
          old.foldPointToTabPoint(oldFold.toPoint(edit.oldStart)),
          old.foldPointToTabPoint(oldFold.toPoint(edit.oldEnd)),
          next.foldPointToTabPoint(foldSnapshot.toPoint(edit.newStart)),
          next.foldPointToTabPoint(foldSnapshot.toPoint(edit.newEnd)),
        ),
    ];
    _snapshot = next;
    return (next, tabEdits);
  }
}

/// a piece of the text of the tab layer
class TabChunk {
  const TabChunk(
    this.text, {
    this.isTab = false,
    this.fold,
    this.inlay,
    this.style,
  });

  final String text;

  /// how the text is drawn, from the highlights that are on it
  final HighlightStyle? style;

  /// whether the text is the spaces of a tab
  final bool isTab;
  final Fold? fold;
  final Inlay? inlay;
}

/// the text with its tabs expanded at one time. a point "of the tabs" counts
/// a tab as the spaces it is shown as.
class TabSnapshot {
  TabSnapshot._(
    this.foldSnapshot,
    this.tabSize,
    this.maxExpansionColumn,
    this.version,
  );

  final FoldSnapshot foldSnapshot;
  final int tabSize;
  final int maxExpansionColumn;
  final int version;

  /// the code units of row [row] of the fold layer, read only as far as they
  /// are asked for
  Iterable<int> _lineUnits(int row) sync* {
    final start = foldSnapshot.toOffset(Point(row, 0));
    for (final chunk in foldSnapshot.chunks(start, foldSnapshot.len)) {
      final text = chunk.text;
      for (var i = 0; i < text.length; i++) {
        final unit = text.codeUnitAt(i);
        if (unit == 0x0A) {
          return;
        }
        yield unit;
      }
    }
  }

  /// the tab point of the fold point [input]
  Point foldPointToTabPoint(Point input) {
    final column = input.column;
    var collapsed = 0;
    var expandedUnits = 0;
    var expandedChars = 0;
    for (final unit in _lineUnits(input.row)) {
      if (collapsed >= column) {
        break;
      }
      if (unit == 0x09 && collapsed < maxExpansionColumn) {
        final tabLen = tabSize - (expandedChars % tabSize);
        expandedUnits += tabLen;
        expandedChars += tabLen;
      } else {
        expandedUnits++;
        // the second half of a pair is of the character before it
        if (!_isLowSurrogate(unit)) {
          expandedChars++;
        }
      }
      collapsed++;
    }
    return Point(input.row, expandedUnits + math.max(0, column - collapsed));
  }

  /// the fold point of the tab point [output], with the column of characters
  /// it is at, and how far it is from the end of the tab it is in. inside a
  /// tab, [bias] says which side of the tab it goes to.
  (Point, int, int) tabPointToFoldPoint(Point output, Bias bias) {
    final column = output.column;
    var collapsed = 0;
    var expandedUnits = 0;
    var expandedChars = 0;
    for (final unit in _lineUnits(output.row)) {
      if (expandedUnits >= column) {
        break;
      }
      if (unit == 0x09 && collapsed < maxExpansionColumn) {
        final tabLen = tabSize - (expandedChars % tabSize);
        if (expandedUnits + tabLen > column) {
          // the place is inside this tab
          final over = expandedUnits + tabLen - column;
          final chars = expandedChars + tabLen - over;
          return bias == Bias.left
              ? (Point(output.row, collapsed), chars, over)
              : (Point(output.row, collapsed + 1), chars, 0);
        }
        expandedUnits += tabLen;
        expandedChars += tabLen;
      } else {
        expandedUnits++;
        if (!_isLowSurrogate(unit)) {
          expandedChars++;
        }
      }
      collapsed++;
    }
    return (
      Point(output.row, collapsed + math.max(0, column - expandedUnits)),
      expandedChars,
      0,
    );
  }

  Point get maxPoint => foldPointToTabPoint(foldSnapshot.maxPoint);

  int lineLen(int row) {
    final max = maxPoint;
    if (row < max.row) {
      return foldPointToTabPoint(Point(row, foldSnapshot.lineLen(row))).column;
    }
    return max.column;
  }

  Point clipPoint(Point point, Bias bias) => foldPointToTabPoint(
    foldSnapshot.clipPoint(tabPointToFoldPoint(point, bias).$1, bias),
  );

  /// the tab point of the point [point] of the buffer
  Point pointToTabPoint(Point point, Bias bias) {
    final inlayPoint = foldSnapshot.inlaySnapshot.toInlayPoint(point);
    return foldPointToTabPoint(foldSnapshot.toFoldPoint(inlayPoint, bias));
  }

  /// the point of the buffer of the tab point [point]
  Point tabPointToPoint(Point point, Bias bias) {
    final foldPoint = tabPointToFoldPoint(point, bias).$1;
    return foldSnapshot.inlaySnapshot.toBufferPoint(
      foldSnapshot.toInlayPoint(foldPoint),
    );
  }

  int bufferRowToTabRow(int bufferRow) =>
      pointToTabPoint(Point(bufferRow, 0), Bias.left).row;

  /// the pieces of the text from the tab point [start] to [end], with each
  /// tab as its spaces
  Iterable<TabChunk> chunks(
    Point start,
    Point end, [
    Highlights highlights = Highlights.none,
  ]) sync* {
    final (inputStart, expandedCharColumn, toNextStop) = tabPointToFoldPoint(
      start,
      Bias.left,
    );
    final inputEnd = tabPointToFoldPoint(end, Bias.right).$1;
    var inputColumn = inputStart.column;
    var chars = expandedCharColumn;
    var outputRow = start.row;
    var outputColumn = start.column;
    var from = foldSnapshot.toOffset(inputStart);
    final to = foldSnapshot.toOffset(inputEnd);

    if (toNextStop > 0) {
      // the start is inside a tab, and what is left of the tab comes first
      final len = end.row == outputRow
          ? math.min(toNextStop, end.column - outputColumn)
          : toNextStop;
      if (len > 0) {
        yield TabChunk(' ' * len, isTab: true);
      }
      outputColumn += len;
      chars += toNextStop;
      inputColumn++;
      from++;
    }
    if (from >= to) {
      return;
    }

    for (final chunk in foldSnapshot.chunks(from, to, highlights)) {
      final text = chunk.text;
      var runStart = 0;
      for (var i = 0; i < text.length; i++) {
        final unit = text.codeUnitAt(i);
        if (unit == 0x09) {
          if (i > runStart) {
            yield TabChunk(
              text.substring(runStart, i),
              fold: chunk.fold,
              inlay: chunk.inlay,
              style: chunk.style,
            );
          }
          runStart = i + 1;
          var len = inputColumn >= maxExpansionColumn
              ? 1
              : tabSize - (chars % tabSize);
          final tabLen = len;
          if (outputRow == end.row) {
            len = math.min(len, end.column - outputColumn);
          }
          if (len > 0) {
            yield TabChunk(' ' * len, isTab: true);
          }
          outputColumn += len;
          chars += tabLen;
          inputColumn++;
        } else if (unit == 0x0A) {
          outputRow++;
          outputColumn = 0;
          chars = 0;
          inputColumn = 0;
        } else {
          outputColumn++;
          inputColumn++;
          if (!_isLowSurrogate(unit)) {
            chars++;
          }
        }
      }
      if (text.length > runStart) {
        yield TabChunk(
          text.substring(runStart),
          fold: chunk.fold,
          inlay: chunk.inlay,
          style: chunk.style,
        );
      }
    }
  }

  /// the text with its tabs as spaces
  String get text =>
      [for (final chunk in chunks(Point.zero, maxPoint)) chunk.text].join();

  /// the text of the tab point range [start] to [end]
  String textForRange(Point start, Point end) =>
      [for (final chunk in chunks(start, end)) chunk.text].join();

  TextSummary get textSummary => textSummaryForRange(Point.zero, maxPoint);

  /// what the text from the tab point [start] to [end] comes to; its length
  /// is not counted, and its longest row is that of the text before the tabs
  /// were expanded
  TextSummary textSummaryForRange(Point start, Point end) {
    final inputStart = tabPointToFoldPoint(start, Bias.left).$1;
    final inputEnd = tabPointToFoldPoint(end, Bias.right).$1;
    final input = foldSnapshot.textSummaryForRange(inputStart, inputEnd);

    final lineEnd = start.row == end.row ? end : maxPoint;
    var firstLineChars = 0;
    count:
    for (final chunk in chunks(start, lineEnd)) {
      for (var i = 0; i < chunk.text.length; i++) {
        if (chunk.text.codeUnitAt(i) == 0x0A) {
          break count;
        }
        firstLineChars++;
      }
    }
    var lastLineChars = firstLineChars;
    if (start.row != end.row) {
      lastLineChars = 0;
      for (final chunk in chunks(Point(end.row, 0), end)) {
        lastLineChars += chunk.text.length;
      }
    }
    return TextSummary(
      lines: end - start,
      firstLineChars: firstLineChars,
      lastLineChars: lastLineChars,
      longestRow: input.longestRow,
      longestRowChars: input.longestRowChars,
    );
  }
}
