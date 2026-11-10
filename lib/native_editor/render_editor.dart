import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../editor_core/display_map.dart';
import '../editor_core/patch.dart' show Bias;
import '../editor_core/point.dart';
import 'editor_controller.dart';
import 'editor_style.dart';
import 'scrollbar_layout.dart';

/// a row of the screen, laid out as one line of text, with where each of its
/// columns is
class _RowLayout {
  _RowLayout(this.painter, this.columnToIndex);

  final TextPainter painter;

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
    bool showScrollbars = true,
  }) : this._(controller, style, softWrap, showLineNumbers, showScrollbars);

  RenderEditor._(
    this._controller,
    this._style,
    this._softWrap,
    this._showLineNumbers,
    this._showScrollbars,
  );

  EditorController _controller;
  EditorStyle _style;
  bool _softWrap;
  bool _showLineNumbers;
  bool _showScrollbars;

  bool get showScrollbars => _showScrollbars;

  set showScrollbars(bool value) {
    if (value == _showScrollbars) {
      return;
    }
    _showScrollbars = value;
    markNeedsLayout();
  }

  /// the width that the scrollbar takes at the right, which the text does not
  /// go under
  double get _scrollbarWidth => _showScrollbars ? _style.scrollbarWidth : 0;

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
    var painted = 0;
    for (final chunk in _snapshot.highlightedRowChunks(
      row,
      _controller.highlights,
    )) {
      final shown = chunk.replacement ?? chunk.text;
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
    return _RowLayout(painter, columnToIndex);
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
  /// there, and the one that goes along when the text is wider than the view
  List<ScrollbarLayout> scrollbarLayouts() {
    if (!_showScrollbars || !hasSize) {
      return const [];
    }
    final width = _scrollbarWidth;
    final content = contentSize;
    return [
      ScrollbarLayout.compute(
        axis: ScrollbarAxis.vertical,
        track: Rect.fromLTWH(size.width - width, 0, width, size.height),
        viewportSize: size.height,
        // there is room to scroll until the last line is at the top
        scrollRange: content.height + size.height,
        glyph: _lineHeight,
        scrollPosition: _controller.scrollY / _lineHeight,
      ),
      if (!_softWrap && content.width > _textWidth)
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

  void _paintScrollbars(Canvas canvas) {
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
            size.width - _scrollbarWidth,
            _lineHeight,
          ),
          Paint()..color = _style.currentLine,
        );
      }
    }

    // the selections
    final selectionPaint = Paint()..color = _style.selection;
    for (final s in selections) {
      if (s.isEmpty) {
        continue;
      }
      final from = _snapshot.offsetToDisplayPoint(s.start, Bias.right);
      final to = _snapshot.offsetToDisplayPoint(s.end, Bias.left);
      for (
        var row = math.max(from.row, firstRow);
        row <= math.min(to.row, lastRow);
        row++
      ) {
        final left = row == from.row ? _columnX(row, from.column) : textLeft;
        final right = row == to.row
            ? _columnX(row, to.column)
            : _columnX(row, _snapshot.lineLen(row)) + _charWidth;
        canvas.drawRect(
          Rect.fromLTRB(
            left - (row == from.row ? 0 : _controller.scrollX),
            _rowTop(row),
            right,
            _rowTop(row) + _lineHeight,
          ),
          selectionPaint,
        );
      }
    }

    // the text
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(
        _gutterWidth,
        0,
        size.width - _gutterWidth - _scrollbarWidth,
        size.height,
      ),
    );
    for (var row = firstRow; row <= lastRow; row++) {
      if (_snapshot.isBlockLine(row)) {
        continue;
      }
      _row(row).painter
          .paint(canvas, Offset(textLeft - _controller.scrollX, _rowTop(row)));
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
