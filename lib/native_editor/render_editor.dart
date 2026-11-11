import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../editor_core/buffer.dart' show Anchor;
import '../editor_core/display_map.dart';
import '../editor_core/patch.dart' show Bias;
import '../editor_core/point.dart';
import 'editor_controller.dart';
import 'editor_style.dart';
import 'scrollbar_layout.dart';
import 'selection_path.dart';
import 'wavy_underline.dart';

/// a mark in the track of a scrollbar, and the color it is painted in
class ScrollbarMarker {
  const ScrollbarMarker(this.rect, this.color);

  final Rect rect;
  final Color color;
}

/// a row of the screen, laid out as one line of text, with where each of its
/// columns is
class _RowLayout {
  _RowLayout(this.painter, this.columnToIndex, [this.wavy = const []]);

  final TextPainter painter;

  /// the runs of the painted text that are underlined with a wave, and its
  /// color: of text with the same underline, one run
  final List<({int start, int end, int color})> wavy;

  /// draws the waves under the text, at the vertical place of an underline,
  /// below the baseline by a part of the descent
  void paintWavy(Canvas canvas, Offset origin) {
    if (wavy.isEmpty) {
      return;
    }
    final lines = painter.computeLineMetrics();
    if (lines.isEmpty) {
      return;
    }
    final y = lines.first.baseline + lines.first.descent * 0.618;
    for (final run in wavy) {
      final from = painter
          .getOffsetForCaret(TextPosition(offset: run.start), Rect.zero)
          .dx;
      final to = painter
          .getOffsetForCaret(TextPosition(offset: run.end), Rect.zero)
          .dx;
      paintWavyUnderline(
        canvas,
        origin + Offset(from, y),
        to - from,
        Color(run.color),
      );
    }
  }

  /// for each column of the row, which is a code unit of what the display map
  /// says is on it, the index in the text that was painted
  final List<int> columnToIndex;

  double xOf(int column) {
    final i = column < 0
        ? 0
        : column >= columnToIndex.length
        ? columnToIndex.last
        : columnToIndex[column];
    return painter.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dx;
  }
}

/// paints the text of an [EditorController]: the rows in view, the numbers of
/// the lines, the selections and the cursors
class RenderEditor extends RenderBox {
  RenderEditor({
    required EditorController controller,
    required EditorStyle style,
    required bool softWrap,
    required bool showLineNumbers,
    ScrollbarSettings scrollbars = const ScrollbarSettings(),
  }) : this._(controller, style, softWrap, showLineNumbers, scrollbars);

  RenderEditor._(
    this._controller,
    this._style,
    this._softWrap,
    this._showLineNumbers,
    this._scrollbars,
  );

  EditorController _controller;
  EditorStyle _style;
  bool _softWrap;
  bool _showLineNumbers;
  ScrollbarSettings _scrollbars;

  ScrollbarSettings get scrollbars => _scrollbars;

  set scrollbars(ScrollbarSettings value) {
    if (value == _scrollbars) {
      return;
    }
    _scrollbars = value;
    markNeedsLayout();
  }

  bool _scrollbarsShown = true;

  /// whether the scrollbars are shown at the moment, which the view says when
  /// it hides them after a while without scrolling
  bool get scrollbarsShown => _scrollbarsShown;

  set scrollbarsShown(bool value) {
    if (value == _scrollbarsShown) {
      return;
    }
    _scrollbarsShown = value;
    markNeedsPaint();
  }

  /// the width that the scrollbar takes at the right, which the text does not
  /// go under, also when it is not drawn for a moment
  double get _scrollbarWidth =>
      _scrollbars.show == ScrollbarVisibility.never ? 0 : _style.scrollbarWidth;

  /// whether the scrollbars are drawn: when they are always, when they are
  /// shown, and with auto also when there is something to mark in them: the
  /// other places that the selected text is, or diagnostics, or when a cursor
  /// is out of sight
  bool get scrollbarsVisible => switch (_scrollbars.show) {
    ScrollbarVisibility.always => true,
    ScrollbarVisibility.never => false,
    ScrollbarVisibility.system => _scrollbarsShown,
    ScrollbarVisibility.auto =>
      (_scrollbars.selectedText && _controller.occurrences.isNotEmpty) ||
          (_scrollbars.diagnostics != ScrollbarDiagnostics.none &&
              _controller.hasDiagnostics) ||
          _cursorsOutOfSight() ||
          _scrollbarsShown,
  };

  /// whether a cursor is on a row that is not on the screen
  bool _cursorsOutOfSight() {
    if (!hasSize) {
      return false;
    }
    final first = (_controller.scrollY / _lineHeight).floor();
    final last = ((_controller.scrollY + size.height) / _lineHeight).ceil() - 1;
    for (final s in _controller.selections.all) {
      final row = _snapshot.offsetToDisplayPoint(s.head).row;
      if (row < first || row > last) {
        return true;
      }
    }
    return false;
  }

  EditorController get controller => _controller;

  set controller(EditorController value) {
    if (identical(value, _controller)) {
      return;
    }
    if (attached) {
      _controller.removeListener(_changed);
      value.addListener(_changed);
    }
    _controller = value;
    markNeedsLayout();
  }

  EditorStyle get style => _style;

  set style(EditorStyle value) {
    if (identical(value, _style)) {
      return;
    }
    _style = value;
    _metricsFor = null;
    _clearRows();
    markNeedsLayout();
  }

  bool get softWrap => _softWrap;

  set softWrap(bool value) {
    if (value == _softWrap) {
      return;
    }
    _softWrap = value;
    markNeedsLayout();
  }

  bool get showLineNumbers => _showLineNumbers;

  set showLineNumbers(bool value) {
    if (value == _showLineNumbers) {
      return;
    }
    _showLineNumbers = value;
    markNeedsLayout();
  }

  // measures

  EditorStyle? _metricsFor;
  double _charWidth = 8;
  double _lineHeight = 20;

  /// the width of a column
  double get charWidth => _charWidth;

  /// the height of a row
  double get lineHeight => _lineHeight;

  /// where the text starts, after the gutter
  double get textLeft => _gutterWidth + _style.textPadding;

  double _gutterWidth = 0;
  late DisplaySnapshot _snapshot;
  int _layoutRevision = -1;
  final Map<int, _RowLayout> _rows = {};

  void _measure() {
    if (identical(_metricsFor, _style)) {
      return;
    }
    final probe = TextPainter(
      text: TextSpan(text: 'M' * 20, style: _style.textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    _charWidth = probe.width / 20;
    _lineHeight = probe.height;
    probe.dispose();
    _metricsFor = _style;
  }

  void _clearRows() {
    for (final row in _rows.values) {
      row.painter.dispose();
    }
    _rows.clear();
  }

  void _changed() {
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(_changed);
  }

  @override
  void detach() {
    _controller.removeListener(_changed);
    _clearRows();
    super.detach();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void performLayout() {
    size = constraints.biggest;
    _measure();
    final lines = _controller.buffer.lineCount;
    _gutterWidth = _showLineNumbers
        ? lines.toString().length.clamp(2, 12) * _charWidth +
              2 * _style.gutterPadding
        : 0;
    final columns = _softWrap
        ? math.max(1, (_textWidth / _charWidth).floor())
        : null;
    _controller.setWrapColumns(columns);
    _controller.viewportRows = math.max(
      1,
      (size.height / _lineHeight).floor() - 1,
    );
    _snapshot = _controller.snapshot;
    if (_layoutRevision != _controller.revision) {
      _layoutRevision = _controller.revision;
      _clearRows();
    }

    if (_controller.revealCursorRequested) {
      _controller.revealCursorRequested = false;
      _revealCursor();
    }
    _clampScroll();
  }

  /// the width that the text has, between the gutter and the scrollbar
  double get _textWidth =>
      size.width - textLeft - _style.textPadding - _scrollbarWidth;

  /// how far the contents go
  Size get contentSize {
    final width = _softWrap
        ? 0.0
        : (_snapshot.lineLen(_snapshot.longestRow) + 1) * _charWidth;
    return Size(width, _snapshot.rowCount * _lineHeight);
  }

  void _clampScroll() {
    final content = contentSize;
    final maxY = math.max(0.0, content.height - _lineHeight);
    final maxX = math.max(0.0, content.width - _textWidth);
    _controller.scrollY = _controller.scrollY.clamp(0.0, maxY);
    _controller.scrollX = _controller.scrollX.clamp(0.0, maxX);
  }

  void _revealCursor() {
    final heads = _controller.selections.all;
    if (heads.isEmpty) {
      return;
    }
    final head = _controller.selections.newest.head;
    final point = _snapshot.offsetToDisplayPoint(head);
    final top = point.row * _lineHeight;
    if (top < _controller.scrollY) {
      _controller.scrollY = top;
    } else if (top + _lineHeight > _controller.scrollY + size.height) {
      _controller.scrollY = top + _lineHeight - size.height;
    }
    if (!_softWrap) {
      final x = _row(point.row).xOf(point.column);
      final width = _textWidth;
      if (x < _controller.scrollX) {
        _controller.scrollX = math.max(0, x - 2 * _charWidth);
      } else if (x + _charWidth > _controller.scrollX + width) {
        _controller.scrollX = x + _charWidth - width + 2 * _charWidth;
      }
    }
  }

  // rows

  _RowLayout _row(int row) => _rows.putIfAbsent(row, () => _layoutRow(row));

  _RowLayout _layoutRow(int row) {
    final spans = <InlineSpan>[];
    final columnToIndex = <int>[];
    final wavy = <({int start, int end, int color})>[];
    var painted = 0;
    for (final chunk in _snapshot.highlightedRowChunks(
      row,
      _controller.highlights,
    )) {
      final shown = chunk.replacement ?? chunk.text;
      final underline = chunk.style;
      if (underline != null &&
          underline.wavy == true &&
          underline.underlineColor != null) {
        final last = wavy.isEmpty ? null : wavy.last;
        if (last != null &&
            last.end == painted &&
            last.color == underline.underlineColor) {
          wavy[wavy.length - 1] = (
            start: last.start,
            end: painted + shown.length,
            color: last.color,
          );
        } else {
          wavy.add((
            start: painted,
            end: painted + shown.length,
            color: underline.underlineColor!,
          ));
        }
      }
      var style = _style.apply(chunk.style);
      if (chunk.replacement != null) {
        style = style.copyWith(color: _style.invisible);
      }
      spans.add(TextSpan(text: shown, style: style));
      final length = chunk.text.length;
      if (chunk.replacement == null) {
        for (var i = 0; i < length; i++) {
          columnToIndex.add(painted + i);
        }
      } else {
        for (var i = 0; i < length; i++) {
          columnToIndex.add(painted);
        }
      }
      painted += shown.length;
    }
    columnToIndex.add(painted);
    final painter = TextPainter(
      text: TextSpan(style: _style.textStyle, children: spans),
      textDirection: TextDirection.ltr,
    )..layout();
    return _RowLayout(painter, columnToIndex, wavy);
  }

  /// where the left edge of the row [row] is on the screen
  double _rowTop(int row) => row * _lineHeight - _controller.scrollY;

  double _columnX(int row, int column) =>
      textLeft - _controller.scrollX + _row(row).xOf(column);

  // positions

  /// the box of the cursor at the text offset [offset], in the editor's own
  /// coordinates
  Rect caretRectForOffset(int offset, [Bias bias = Bias.left]) {
    final point = _snapshot.offsetToDisplayPoint(offset, bias);
    final x = _columnX(point.row, point.column);
    return Rect.fromLTWH(
      x,
      _rowTop(point.row),
      _style.cursorWidth,
      _lineHeight,
    );
  }

  /// the text offset that [position], in the editor's own coordinates, is at
  int offsetForPosition(Offset position) {
    final row = (((position.dy + _controller.scrollY) / _lineHeight).floor())
        .clamp(0, _snapshot.rowCount - 1);
    final layout = _row(row);
    final x = position.dx - textLeft + _controller.scrollX;
    final index = layout.painter
        .getPositionForOffset(Offset(math.max(0, x), _lineHeight / 2))
        .offset;
    // from the place in the painted text back to a column
    var column = layout.columnToIndex.length - 1;
    for (var i = 0; i < layout.columnToIndex.length; i++) {
      if (layout.columnToIndex[i] >= index) {
        column = i;
        break;
      }
    }
    final clipped = _snapshot.clipPoint(Point(row, column), Bias.left);
    return _snapshot.displayPointToOffset(clipped);
  }

  // scrollbars

  final Map<ScrollbarAxis, ThumbState> _thumbStates = {};

  /// what is being done to the thumb of the scrollbar that goes [axis]
  ThumbState thumbState(ScrollbarAxis axis) =>
      _thumbStates[axis] ?? ThumbState.idle;

  void setThumbState(ScrollbarAxis axis, ThumbState state) {
    if (thumbState(axis) == state) {
      return;
    }
    _thumbStates[axis] = state;
    markNeedsPaint();
  }

  /// the scrollbars for the scroll as it is. the one that goes down is always
  /// there, and the one that goes along when the text is wider than the view;
  /// a setting can say that one is not
  List<ScrollbarLayout> scrollbarLayouts() {
    if (_scrollbars.show == ScrollbarVisibility.never || !hasSize) {
      return const [];
    }
    final width = _scrollbarWidth;
    final content = contentSize;
    return [
      if (_scrollbars.vertical)
        ScrollbarLayout.compute(
          axis: ScrollbarAxis.vertical,
          track: Rect.fromLTWH(size.width - width, 0, width, size.height),
          viewportSize: size.height,
          // the text goes as far as its last row, and there is room to scroll
          // until that row is at the top
          scrollRange:
              math.max(0.0, content.height - _lineHeight) + size.height,
          glyph: _lineHeight,
          scrollPosition: _controller.scrollY / _lineHeight,
        ),
      if (_scrollbars.horizontal && !_softWrap && content.width > _textWidth)
        ScrollbarLayout.compute(
          axis: ScrollbarAxis.horizontal,
          track: Rect.fromLTWH(
            0,
            size.height - width,
            size.width - width,
            width,
          ),
          viewportSize: _textWidth,
          scrollRange: content.width,
          glyph: _charWidth,
          scrollPosition: _controller.scrollX / _charWidth,
          contentOffset: textLeft,
        ),
    ];
  }

  /// the scrollbar that [position], in the editor's own coordinates, is in
  ScrollbarLayout? scrollbarAt(Offset position) {
    for (final layout in scrollbarLayouts()) {
      if (layout.track.contains(position)) {
        return layout;
      }
    }
    return null;
  }

  /// the scrollbar that goes [axis], if there is one
  ScrollbarLayout? scrollbar(ScrollbarAxis axis) {
    for (final layout in scrollbarLayouts()) {
      if (layout.axis == axis) {
        return layout;
      }
    }
    return null;
  }

  /// scrolls to [units] along [axis]: rows for the one that goes down, and
  /// columns for the one that goes along
  void scrollToUnits(ScrollbarAxis axis, double units) {
    if (axis == ScrollbarAxis.vertical) {
      _controller.setScroll(y: units * _lineHeight);
    } else {
      _controller.setScroll(x: units * _charWidth);
    }
  }

  /// the display row of a place in the text
  int _rowOf(Anchor anchor) => _snapshot
      .offsetToDisplayPoint(_controller.buffer.snapshot.offsetForAnchor(anchor))
      .row;

  /// the marks in the track that go down, at the rows of the cursors: two
  /// pixels high, across the track, and one where the rows are next to each
  /// other. there are none when the setting says so, or when there are too
  /// many to tell apart
  List<ScrollbarMarker> cursorMarkers() {
    final cursors = _controller.selections.all;
    if (!_scrollbars.cursors || cursors.length > 100) {
      return const [];
    }
    return _markerRects([
      for (final s in cursors)
        (
          _snapshot.offsetToDisplayPoint(s.head).row,
          _snapshot.offsetToDisplayPoint(s.head).row,
          _style.cursor,
        ),
    ]);
  }

  /// the marks in the middle third of the track, for the other places that
  /// the selected text is: at least five pixels high, and one where they are
  /// next to each other
  List<ScrollbarMarker> occurrenceMarkers() {
    if (!_scrollbars.selectedText) {
      return const [];
    }
    return _markerRects([
      for (final range in _controller.occurrences)
        (_rowOf(range.start), _rowOf(range.end), _style.scrollbarMarker),
    ], column: 1);
  }

  /// the marks in the last third of the track, for the diagnostics that the
  /// setting says: in the color of how bad each is, the least bad first, so
  /// that the worst is painted last
  List<ScrollbarMarker> diagnosticMarkers() {
    if (_scrollbars.diagnostics == ScrollbarDiagnostics.none) {
      return const [];
    }
    final diagnostics = _controller.diagnosticRanges;
    final colors = _controller.diagnosticColors;
    final levels = [
      (diagnostics.hints, 3, colors.hint),
      (diagnostics.information, 2, colors.information),
      (diagnostics.warnings, 1, colors.warning),
      (diagnostics.errors, 0, colors.error),
    ];
    return _markerRects([
      for (final (ranges, rank, color) in levels)
        if (_scrollbars.diagnostics.shows(rank))
          for (final range in ranges)
            (_rowOf(range.start), _rowOf(range.end), Color(color)),
    ], column: 2);
  }

  /// the marks of rows of the text in the track that goes down. without a
  /// [column] they are two pixels high and across the track, and with one
  /// they are in that third of it, at least five pixels high. marks that are
  /// next to each other and of one color are one.
  List<ScrollbarMarker> _markerRects(
    List<(int, int, Color)> rowRanges, {
    int? column,
  }) {
    final bar = scrollbar(ScrollbarAxis.vertical);
    if (bar == null || rowRanges.isEmpty) {
      return const [];
    }
    final minHeight = column == null ? 2.0 : 5.0;
    final maxHeight = column == null ? 2.0 : double.infinity;
    final height = bar.unitSize.clamp(minHeight, maxHeight);
    final ranges = <(double, double, Color)>[];
    for (final (start, end, color) in rowRanges) {
      final top = bar.track.top + start * bar.unitSize;
      final bottom = bar.track.top + end * bar.unitSize + height;
      if (ranges.isNotEmpty &&
          ranges.last.$2 >= top - 1 &&
          ranges.last.$3 == color) {
        ranges[ranges.length - 1] = (
          ranges.last.$1,
          math.max(ranges.last.$2, bottom),
          color,
        );
      } else {
        ranges.add((top, bottom, color));
      }
    }
    final double left;
    final double right;
    if (column == null) {
      left = bar.track.left + ScrollbarLayout.borderWidth;
      right = bar.track.right;
    } else {
      final columnWidth = ((bar.track.width - ScrollbarLayout.borderWidth) / 3)
          .floorToDouble();
      left =
          bar.track.left + ScrollbarLayout.borderWidth + column * columnWidth;
      right = left + columnWidth;
    }
    return [
      for (final (top, bottom, color) in ranges)
        ScrollbarMarker(Rect.fromLTRB(left, top, right, bottom), color),
    ];
  }

  void _paintScrollbars(Canvas canvas) {
    if (!scrollbarsVisible) {
      return;
    }
    for (final layout in scrollbarLayouts()) {
      canvas.drawRect(layout.track, Paint()..color = _style.scrollbarTrack);
      if (layout.axis == ScrollbarAxis.vertical) {
        // the line between the text and the scrollbar
        canvas.drawRect(
          Rect.fromLTWH(
            layout.track.left,
            layout.track.top,
            ScrollbarLayout.borderWidth,
            layout.track.height,
          ),
          Paint()..color = _style.scrollbarTrackBorder,
        );
        // the cursors are painted last, over the others
        for (final marker in [
          ...occurrenceMarkers(),
          ...diagnosticMarkers(),
          ...cursorMarkers(),
        ]) {
          canvas.drawRect(marker.rect, Paint()..color = marker.color);
        }
      }
      final thumb = layout.thumb;
      if (thumb == null) {
        continue;
      }
      final color = switch (thumbState(layout.axis)) {
        ThumbState.dragging => _style.scrollbarThumbActive,
        ThumbState.hovered => _style.scrollbarThumbHover,
        ThumbState.idle => _style.scrollbarThumb,
      };
      canvas.drawRect(thumb, Paint()..color = color);
    }
  }

  // painting

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = _style.background);

    final firstRow = math.max(0, (_controller.scrollY / _lineHeight).floor());
    final lastRow = math.min(
      _snapshot.rowCount - 1,
      ((_controller.scrollY + size.height) / _lineHeight).ceil(),
    );
    final selections = _controller.selections.all;

    // the line the cursor is on
    final cursorRows = <int>{
      for (final s in selections)
        if (s.isEmpty) _snapshot.offsetToDisplayPoint(s.head).row,
    };
    for (final row in cursorRows) {
      if (row >= firstRow && row <= lastRow) {
        canvas.drawRect(
          Rect.fromLTWH(
            0,
            _rowTop(row),
            // the scrollbar is drawn over it, and when it is not there the
            // line goes to the edge
            size.width,
            _lineHeight,
          ),
          Paint()..color = _style.currentLine,
        );
      }
    }

    // the selections, which are one shape with rounded corners, and go a little
    // past the end of the rows that they go on from
    final selectionPaint = Paint()..color = _style.selection;
    final radius = _style.roundedSelection ? 0.15 * _lineHeight : 0.0;
    for (final s in selections) {
      if (s.isEmpty) {
        continue;
      }
      final from = _snapshot.offsetToDisplayPoint(s.start, Bias.right);
      final to = _snapshot.offsetToDisplayPoint(s.end, Bias.left);
      // the row after the end is not one of them when it ends at its start
      final firstShown = math.max(from.row, firstRow);
      final lastShown = math.min(to.column == 0 ? to.row - 1 : to.row, lastRow);
      if (lastShown < firstShown) {
        continue;
      }
      final lines = <SelectionLine>[
        for (var row = firstShown; row <= lastShown; row++)
          (
            row == from.row
                ? _columnX(row, from.column)
                : textLeft - _controller.scrollX,
            row == to.row
                ? _columnX(row, to.column)
                : _columnX(row, _snapshot.lineLen(row)) + radius * 2,
          ),
      ];
      for (final path in selectionPaths(
        _rowTop(firstShown),
        lines,
        _lineHeight,
        radius,
      )) {
        canvas.drawPath(path, selectionPaint);
      }
    }

    // the text
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(
        _gutterWidth,
        0,
        // the whole width: the scrollbar is drawn over the text
        size.width - _gutterWidth,
        size.height,
      ),
    );
    for (var row = firstRow; row <= lastRow; row++) {
      if (_snapshot.isBlockLine(row)) {
        continue;
      }
      final layout = _row(row);
      final origin = Offset(textLeft - _controller.scrollX, _rowTop(row));
      layout.painter.paint(canvas, origin);
      layout.paintWavy(canvas, origin);
    }

    // the cursors
    if (_controller.hasFocus && _controller.cursorVisible) {
      final cursorPaint = Paint()..color = _style.cursor;
      for (final s in selections) {
        final point = _snapshot.offsetToDisplayPoint(s.head);
        if (point.row < firstRow || point.row > lastRow) {
          continue;
        }
        canvas.drawRect(
          Rect.fromLTWH(
            _columnX(point.row, point.column),
            _rowTop(point.row),
            _style.cursorWidth,
            _lineHeight,
          ),
          cursorPaint,
        );
      }
    }
    canvas.restore();

    // the numbers of the lines
    if (_showLineNumbers) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, _gutterWidth, size.height),
        Paint()..color = _style.background,
      );
      for (var row = firstRow; row <= lastRow; row++) {
        final info = _snapshot.rowInfo(row);
        final bufferRow = info.bufferRow;
        if (bufferRow == null || info.softWrapped) {
          continue;
        }
        final onCursor = cursorRows.contains(row);
        final number = TextPainter(
          text: TextSpan(
            text: '${bufferRow + 1}',
            style: _style.textStyle.copyWith(
              color: onCursor ? _style.currentGutterText : _style.gutterText,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        number.paint(
          canvas,
          Offset(
            _gutterWidth - _style.gutterPadding - number.width,
            _rowTop(row),
          ),
        );
        number.dispose();
      }
    }
    _paintScrollbars(canvas);
    canvas.restore();
  }

  @override
  void dispose() {
    _clearRows();
    super.dispose();
  }
}
