import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart' show FocusNode;

import '../editor_core/buffer.dart';
import '../editor_core/display_map.dart';
import '../editor_core/patch.dart' show Bias;
import '../editor_core/point.dart';
import '../editor_core/selections_collection.dart';
import '../editor_core/text_metrics.dart';
import '../syntax/syntax_layer.dart';

/// an editor's text and everything that is done to it: the buffer, how it is
/// laid out on the screen, the selections, and where the view is scrolled to
class EditorController extends ChangeNotifier {
  EditorController({
    String text = '',
    int tabSize = 4,
    TextMetrics metrics = const CellMetrics(),
  }) : buffer = TextBuffer(text) {
    display = DisplayMap(buffer, tabSize: tabSize, metrics: metrics)
      ..addListener(_changed);
    selections = SelectionsCollection(buffer);
    buffer.addListener(_onBufferChange);
  }

  final TextBuffer buffer;
  late final DisplayMap display;
  late final SelectionsCollection selections;

  Highlights _highlights = Highlights.none;

  /// how scrolled the view is, in logical pixels
  double scrollX = 0;
  double scrollY = 0;

  /// whether the next layout is to scroll so that the cursor can be seen
  bool revealCursorRequested = false;

  /// whether the editor is focused, which the cursor is shown by
  bool hasFocus = false;

  /// whether the cursor is on the screen in its blinking
  bool cursorVisible = true;

  int _revision = 0;

  /// grows every time anything that is drawn changed
  int get revision => _revision;

  Highlights get highlights => _highlights;

  set highlights(Highlights value) {
    _highlights = value;
    _changed();
  }

  SyntaxLayer? _syntax;

  /// what the text is drawn by, from the grammar of the language
  SyntaxLayer? get syntax => _syntax;

  /// draws the text by [layer], or plain when it is null. the controller
  /// owns the layer from now on, and the one it had
  void setSyntax(SyntaxLayer? layer) {
    if (identical(layer, _syntax)) {
      return;
    }
    _syntax?.dispose();
    _syntax = layer;
    highlights = _highlights.withSyntax(layer);
  }

  /// draws everything again, which is for when what it is drawn with changed
  void redraw() => _changed();

  DisplaySnapshot get snapshot => display.snapshot;

  String get text => buffer.text.toString();

  void _changed() {
    _revision++;
    notifyListeners();
  }

  void _onBufferChange(BufferChange change) => _changed();

  /// the layout is to wrap at [columns] columns, or not at all
  void setWrapColumns(int? columns) {
    final width = columns?.toDouble();
    if (width == display.wrapWidth) {
      return;
    }
    display.setWrapWidth(width);
    // not told to the listeners: this is called while the view is laid out
    _revision++;
  }

  void setTabSize(int tabSize) {
    if (tabSize == display.tabSize) {
      return;
    }
    display.setTabSize(tabSize);
    _changed();
  }

  void setScroll({double? x, double? y}) {
    final newX = x ?? scrollX;
    final newY = y ?? scrollY;
    if (newX == scrollX && newY == scrollY) {
      return;
    }
    scrollX = newX;
    scrollY = newY;
    notifyListeners();
  }

  void requestRevealCursor() {
    revealCursorRequested = true;
    notifyListeners();
  }

  void setFocus(bool focused) {
    if (hasFocus == focused) {
      return;
    }
    hasFocus = focused;
    cursorVisible = true;
    notifyListeners();
  }

  void setCursorVisible(bool visible) {
    if (cursorVisible == visible) {
      return;
    }
    cursorVisible = visible;
    notifyListeners();
  }

  // editing

  /// replaces every selection with [text], and leaves a cursor after each
  void replaceSelections(String text) {
    final current = selections.all;
    if (current.isEmpty) {
      return;
    }
    final normalized = normalizeLineEndings(text);
    buffer.beginTransaction(selections.anchors);
    buffer.edit([
      for (final s in current) Replacement(s.start, s.end, normalized),
    ]);
    var delta = 0;
    final cursors = <Selection>[];
    for (final s in current) {
      final at = s.start + delta + normalized.length;
      cursors.add(selections.make(at, at));
      delta += normalized.length - (s.end - s.start);
    }
    selections.select(cursors);
    buffer.endTransaction(selections.anchors);
    requestRevealCursor();
  }

  /// deletes each selection, or when it is a cursor the character before it
  void backspace() => _delete(forward: false);

  /// deletes each selection, or when it is a cursor the character after it
  void deleteForward() => _delete(forward: true);

  void _delete({required bool forward}) {
    final current = selections.all;
    final ranges = <(int, int)>[];
    for (final s in current) {
      if (!s.isEmpty) {
        ranges.add((s.start, s.end));
      } else if (forward) {
        final to = _next(s.start);
        if (to > s.start) {
          ranges.add((s.start, to));
        }
      } else {
        final from = _previous(s.start);
        if (from < s.start) {
          ranges.add((from, s.start));
        }
      }
    }
    if (ranges.isEmpty) {
      return;
    }
    buffer.beginTransaction(selections.anchors);
    buffer.edit([for (final (a, b) in ranges) Replacement(a, b, '')]);
    selections.select([
      for (final s in selections.all) selections.make(s.head, s.head),
    ]);
    buffer.endTransaction(selections.anchors);
    requestRevealCursor();
  }

  void undo() {
    final transaction = buffer.undo();
    if (transaction?.selectionsBefore != null) {
      selections.selectAnchors(transaction!.selectionsBefore!);
    }
    requestRevealCursor();
  }

  void redo() {
    final transaction = buffer.redo();
    if (transaction?.selectionsAfter != null) {
      selections.selectAnchors(transaction!.selectionsAfter!);
    }
    requestRevealCursor();
  }

  // moving

  int _previous(int offset) =>
      offset <= 0 ? 0 : buffer.text.clipOffset(offset - 1, Bias.left);

  int _next(int offset) => offset >= buffer.length
      ? buffer.length
      : buffer.text.clipOffset(offset + 1, Bias.right);

  /// moves the head of every selection one character, a selection being
  /// made smaller to a cursor at the edge it moves toward when it is not
  /// [extend]ed
  void moveHorizontally({required bool forward, bool extend = false}) {
    selections.select([
      for (final s in selections.all)
        if (extend)
          s.withHead(forward ? _next(s.head) : _previous(s.head))
        else if (!s.isEmpty)
          selections.make(forward ? s.end : s.start, forward ? s.end : s.start)
        else
          selections.make(
            forward ? _next(s.head) : _previous(s.head),
            forward ? _next(s.head) : _previous(s.head),
          ),
    ]);
    requestRevealCursor();
  }

  /// moves the head of every selection to the same column of the row above
  /// or below, as far as it has one, remembering the column it came from
  void moveVertically({required bool down, bool extend = false}) =>
      moveByRows(down ? 1 : -1, extend: extend);

  /// moves to the start of the row, or with [toEnd] to its end
  void moveToRowEdge({required bool toEnd, bool extend = false}) {
    final shown = snapshot;
    selections.select([
      for (final s in selections.all)
        () {
          final head = shown.offsetToDisplayPoint(s.head);
          final column = toEnd ? shown.lineLen(head.row) : 0;
          final offset = shown.displayPointToOffset(
            shown.clipPoint(
              Point(head.row, column),
              toEnd ? Bias.left : Bias.right,
            ),
          );
          return extend ? s.withHead(offset) : s.collapseTo(offset);
        }(),
    ]);
    requestRevealCursor();
  }

  void selectAll() {
    selections.selectRanges([(0, buffer.length)]);
    requestRevealCursor();
  }

  /// how many rows are in view, which the page keys move by
  int viewportRows = 20;

  /// puts the selected text on the clipboard; with nothing selected, the
  /// whole line of each cursor
  Future<void> copy() async {
    final text = _textToCopy();
    if (text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  /// copies, and then deletes what was copied
  Future<void> cut() async {
    final text = _textToCopy();
    if (text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    final source = buffer.text;
    final ranges = <(int, int)>[];
    for (final s in selections.all) {
      if (!s.isEmpty) {
        ranges.add((s.start, s.end));
      } else {
        final row = source.rowAt(s.head);
        ranges.add((
          source.lineStart(row),
          math.min(source.length, source.lineEnd(row) + 1),
        ));
      }
    }
    _deleteRanges(ranges);
  }

  /// puts the text of the clipboard in the place of the selections; when it
  /// has as many lines as there are cursors, each gets one
  Future<void> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      return;
    }
    final lines = normalizeLineEndings(text).split('\n');
    final current = selections.all;
    if (current.length > 1 && lines.length == current.length) {
      buffer.beginTransaction(selections.anchors);
      buffer.edit([
        for (var i = 0; i < current.length; i++)
          Replacement(current[i].start, current[i].end, lines[i]),
      ]);
      var delta = 0;
      final cursors = <Selection>[];
      for (var i = 0; i < current.length; i++) {
        final at = current[i].start + delta + lines[i].length;
        cursors.add(selections.make(at, at));
        delta += lines[i].length - (current[i].end - current[i].start);
      }
      selections.select(cursors);
      buffer.endTransaction(selections.anchors);
      requestRevealCursor();
      return;
    }
    replaceSelections(text);
  }

  String _textToCopy() {
    final text = buffer.text;
    return selections.all
        .map(
          (s) => s.isEmpty
              ? '${text.lineText(text.rowAt(s.head))}\n'
              : text.substring(s.start, s.end),
        )
        .join('\n');
  }

  /// the text that is selected, the selections one under another
  String selectedText() => selections.all
      .where((s) => !s.isEmpty)
      .map((s) => buffer.text.substring(s.start, s.end))
      .join('\n');

  // more editing

  /// whether Tab puts in a tab character, and not the spaces to the next stop
  bool useTabs = false;

  /// the focus of the view that shows this text, which is kept here so that
  /// whatever opens the editor can give it the focus back
  final FocusNode focusNode = FocusNode(debugLabel: 'editor');

  void focus() => focusNode.requestFocus();

  /// puts the cursor at [line] and [column], which are counted from 1, as
  /// far as the text has them
  void goToLineColumn(int line, [int column = 1]) {
    final text = buffer.text;
    final row = (line - 1).clamp(0, text.lineCount - 1);
    final at = text.pointToOffset(Point(row, math.max(0, column - 1)));
    selections.selectRanges([(at, at)]);
    requestRevealCursor();
  }

  /// indents the text with [spaces] or tabs, [size] wide. the indentation it
  /// has keeps its levels, each as wide as the tab size was, and a remainder
  /// that is not a whole level stays as spaces
  void setIndentation({required bool spaces, required int size}) {
    final old = display.tabSize;
    final text = buffer.text;
    final edits = <Replacement>[];
    for (var row = 0; row < text.lineCount; row++) {
      final start = text.lineStart(row);
      final end = text.lineEnd(row);
      var lead = start;
      while (lead < end && _isSpace(text.codeUnitAt(lead))) {
        lead++;
      }
      if (lead == start) {
        continue;
      }
      var columns = 0;
      for (var i = start; i < lead; i++) {
        columns += text.codeUnitAt(i) == 0x09 ? old - columns % old : 1;
      }
      final levels = columns ~/ old;
      final replacement =
          (spaces ? ' ' * (levels * size) : '\t' * levels) +
          ' ' * (columns % old);
      if (replacement != text.substring(start, lead)) {
        edits.add(Replacement(start, lead, replacement));
      }
    }
    useTabs = !spaces;
    setTabSize(size);
    if (edits.isNotEmpty) {
      buffer.finalizeLastTransaction();
      buffer.edit(edits);
      buffer.finalizeLastTransaction();
    }
    notifyListeners();
  }

  static bool _isSpace(int unit) => unit == 0x20 || unit == 0x09;

  static bool _isWordUnit(int unit) =>
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A) ||
      unit == 0x5F ||
      unit > 0x7F;

  int _classOf(int unit) => _isWordUnit(unit) ? 0 : 2;

  /// the offset that a word further on is at: past the spaces after [offset],
  /// and then past the word or the run of signs that comes next; the end of a
  /// line is a stop of its own
  int nextWordBoundary(int offset) {
    final text = buffer.text;
    var at = offset;
    if (at >= text.length) {
      return text.length;
    }
    if (text.codeUnitAt(at) == 0x0A) {
      return at + 1;
    }
    while (at < text.length && _isSpace(text.codeUnitAt(at))) {
      at++;
    }
    if (at >= text.length || text.codeUnitAt(at) == 0x0A) {
      return at;
    }
    final kind = _classOf(text.codeUnitAt(at));
    while (at < text.length &&
        text.codeUnitAt(at) != 0x0A &&
        !_isSpace(text.codeUnitAt(at)) &&
        _classOf(text.codeUnitAt(at)) == kind) {
      at++;
    }
    return text.clipOffset(at, Bias.right);
  }

  /// the offset that a word before [offset] starts at
  int previousWordBoundary(int offset) {
    final text = buffer.text;
    var at = offset;
    if (at <= 0) {
      return 0;
    }
    if (text.codeUnitAt(at - 1) == 0x0A) {
      return at - 1;
    }
    while (at > 0 && _isSpace(text.codeUnitAt(at - 1))) {
      at--;
    }
    if (at <= 0 || text.codeUnitAt(at - 1) == 0x0A) {
      return at;
    }
    final kind = _classOf(text.codeUnitAt(at - 1));
    while (at > 0 &&
        text.codeUnitAt(at - 1) != 0x0A &&
        !_isSpace(text.codeUnitAt(at - 1)) &&
        _classOf(text.codeUnitAt(at - 1)) == kind) {
      at--;
    }
    return text.clipOffset(at, Bias.left);
  }

  void moveByWord({required bool forward, bool extend = false}) {
    selections.select([
      for (final s in selections.all)
        () {
          final target = forward
              ? nextWordBoundary(s.head)
              : previousWordBoundary(s.head);
          if (extend) {
            return s.withHead(target);
          }
          if (!s.isEmpty) {
            final edge = forward ? s.end : s.start;
            return selections.make(edge, edge);
          }
          return selections.make(target, target);
        }(),
    ]);
    requestRevealCursor();
  }

  void deleteWord({required bool forward}) {
    final ranges = <(int, int)>[];
    for (final s in selections.all) {
      if (!s.isEmpty) {
        ranges.add((s.start, s.end));
      } else {
        final other = forward
            ? nextWordBoundary(s.head)
            : previousWordBoundary(s.head);
        if (other != s.head) {
          ranges.add((math.min(other, s.head), math.max(other, s.head)));
        }
      }
    }
    _deleteRanges(ranges);
  }

  void _deleteRanges(List<(int, int)> ranges) {
    if (ranges.isEmpty) {
      return;
    }
    buffer.beginTransaction(selections.anchors);
    buffer.edit([for (final (a, b) in ranges) Replacement(a, b, '')]);
    selections.select([
      for (final s in selections.all) selections.make(s.head, s.head),
    ]);
    buffer.endTransaction(selections.anchors);
    requestRevealCursor();
  }

  /// deletes from the cursors to the end of their lines
  void deleteToLineEnd() {
    final ranges = <(int, int)>[];
    for (final s in selections.all) {
      final end = buffer.text.lineEnd(buffer.text.rowAt(s.head));
      if (!s.isEmpty) {
        ranges.add((s.start, s.end));
      } else if (end > s.head) {
        ranges.add((s.head, end));
      } else if (end < buffer.length) {
        ranges.add((end, end + 1));
      }
    }
    _deleteRanges(ranges);
  }

  /// puts in a new line, with the indent of the line it is made in
  void insertNewline() {
    final current = selections.all;
    if (current.isEmpty) {
      return;
    }
    final text = buffer.text;
    final inserted = <String>[];
    for (final s in current) {
      final row = text.rowAt(s.start);
      final lineStart = text.lineStart(row);
      var indentEnd = lineStart;
      while (indentEnd < s.start && _isSpace(text.codeUnitAt(indentEnd))) {
        indentEnd++;
      }
      inserted.add('\n${text.substring(lineStart, indentEnd)}');
    }
    buffer.beginTransaction(selections.anchors);
    buffer.edit([
      for (var i = 0; i < current.length; i++)
        Replacement(current[i].start, current[i].end, inserted[i]),
    ]);
    var delta = 0;
    final cursors = <Selection>[];
    for (var i = 0; i < current.length; i++) {
      final at = current[i].start + delta + inserted[i].length;
      cursors.add(selections.make(at, at));
      delta += inserted[i].length - (current[i].end - current[i].start);
    }
    selections.select(cursors);
    buffer.endTransaction(selections.anchors);
    requestRevealCursor();
  }

  /// Tab: puts in the spaces to the next stop, or a tab character; when
  /// lines are selected they are indented instead
  void insertTab() {
    final current = selections.all;
    final text = buffer.text;
    if (current.any(
      (s) => !s.isEmpty && text.rowAt(s.start) != text.rowAt(s.end),
    )) {
      indentLines();
      return;
    }
    final size = display.tabSize;
    final inserted = <String>[];
    for (final s in current) {
      if (useTabs) {
        inserted.add('\t');
      } else {
        final column = s.start - text.lineStart(text.rowAt(s.start));
        inserted.add(' ' * (size - column % size));
      }
    }
    buffer.beginTransaction(selections.anchors);
    buffer.edit([
      for (var i = 0; i < current.length; i++)
        Replacement(current[i].start, current[i].end, inserted[i]),
    ]);
    var delta = 0;
    final cursors = <Selection>[];
    for (var i = 0; i < current.length; i++) {
      final at = current[i].start + delta + inserted[i].length;
      cursors.add(selections.make(at, at));
      delta += inserted[i].length - (current[i].end - current[i].start);
    }
    selections.select(cursors);
    buffer.endTransaction(selections.anchors);
    requestRevealCursor();
  }

  /// indents every line the selections touch, or with [outdent] takes one
  /// level of indent off each
  void indentLines({bool outdent = false}) {
    final text = buffer.text;
    final rows = <int>{};
    for (final s in selections.all) {
      final first = text.rowAt(s.start);
      var last = text.rowAt(s.end);
      // a selection that ends at the start of a line does not touch it
      if (last > first && s.end == text.lineStart(last)) {
        last--;
      }
      for (var row = first; row <= last; row++) {
        rows.add(row);
      }
    }
    final size = display.tabSize;
    final edits = <Replacement>[];
    for (final row in rows.toList()..sort()) {
      final start = text.lineStart(row);
      if (!outdent) {
        if (text.lineLength(row) > 0) {
          edits.add(Replacement.insert(start, useTabs ? '\t' : ' ' * size));
        }
        continue;
      }
      if (text.lineLength(row) > 0 && text.codeUnitAt(start) == 0x09) {
        edits.add(Replacement(start, start + 1, ''));
        continue;
      }
      var end = start;
      while (end < start + size &&
          end < text.length &&
          text.codeUnitAt(end) == 0x20) {
        end++;
      }
      if (end > start) {
        edits.add(Replacement(start, end, ''));
      }
    }
    if (edits.isEmpty) {
      return;
    }
    buffer.beginTransaction(selections.anchors);
    buffer.edit(edits);
    buffer.endTransaction(selections.anchors);
    requestRevealCursor();
  }

  /// moves like [moveVertically] by [rows] rows
  void moveByRows(int rows, {bool extend = false}) {
    final shown = snapshot;
    final next = <Selection>[];
    for (final s in selections.all) {
      final head = shown.offsetToDisplayPoint(s.head);
      final goal = s.goal is HorizontalPosition
          ? (s.goal as HorizontalPosition).x.round()
          : head.column;
      final row = head.row + rows;
      final int target;
      if (row < 0) {
        target = 0;
      } else if (row >= shown.rowCount) {
        target = buffer.length;
      } else {
        final point = shown.clipPoint(
          Point(row, math.min(goal, shown.lineLen(row))),
          rows > 0 ? Bias.right : Bias.left,
        );
        target = shown.displayPointToOffset(point);
      }
      final goalValue = HorizontalPosition(goal.toDouble());
      next.add(
        extend
            ? s.withHead(target, goalValue)
            : s.collapseTo(target, goalValue),
      );
    }
    selections.select(next);
    requestRevealCursor();
  }

  /// moves to the start of the text, or with [toEnd] to its end
  void moveToDocumentEdge({required bool toEnd, bool extend = false}) {
    final target = toEnd ? buffer.length : 0;
    selections.select([
      for (final s in selections.all)
        extend ? s.withHead(target) : s.collapseTo(target),
    ]);
    requestRevealCursor();
  }

  /// a click: puts the only cursor at [offset]; with [extend] the selection
  /// is made to reach it, and with [add] one more cursor is put there
  void clickAt(int offset, {bool extend = false, bool add = false}) {
    if (add) {
      selections.addCursor(offset);
    } else if (extend) {
      final newest = selections.newest;
      selections.select([newest.withHead(offset)]);
    } else {
      selections.selectRanges([(offset, offset)]);
    }
    notifyListeners();
  }

  /// a drag: the head of the newest selection follows the pointer
  void dragTo(int offset) {
    final newest = selections.newest;
    final others = selections.all.where((s) => s.id != newest.id);
    selections.select([...others, newest.withHead(offset)]);
    requestRevealCursor();
  }

  /// the range of the word at [offset], or of the spaces or signs there
  (int, int) wordRangeAt(int offset) {
    final text = buffer.text;
    if (text.isEmpty) {
      return (0, 0);
    }
    final at = math.min(offset, text.length);
    // the character after the offset, or the one before at the end of a line
    final index = at < text.length && text.codeUnitAt(at) != 0x0A
        ? at
        : math.max(0, at - 1);
    final unit = text.codeUnitAt(index);
    if (unit == 0x0A) {
      return (at, at);
    }
    int kindOf(int u) => _isSpace(u) ? 1 : _classOf(u);
    final kind = kindOf(unit);
    var start = index;
    while (start > 0 &&
        text.codeUnitAt(start - 1) != 0x0A &&
        kindOf(text.codeUnitAt(start - 1)) == kind) {
      start--;
    }
    var end = index + 1;
    while (end < text.length &&
        text.codeUnitAt(end) != 0x0A &&
        kindOf(text.codeUnitAt(end)) == kind) {
      end++;
    }
    return (
      text.clipOffset(start, Bias.left),
      text.clipOffset(end, Bias.right),
    );
  }

  /// selects the word at [offset]
  void selectWordAt(int offset, {bool add = false}) {
    final (start, end) = wordRangeAt(offset);
    final made = selections.make(start, end);
    selections.select(add ? [...selections.all, made] : [made]);
    notifyListeners();
  }

  /// selects the whole line at [offset], with its line ending
  void selectLineAt(int offset, {bool add = false}) {
    final text = buffer.text;
    final row = text.rowAt(offset);
    final start = text.lineStart(row);
    final end = math.min(text.length, text.lineEnd(row) + 1);
    final made = selections.make(start, end);
    selections.select(add ? [...selections.all, made] : [made]);
    notifyListeners();
  }

  @override
  void dispose() {
    buffer.removeListener(_onBufferChange);
    _syntax?.dispose();
    _syntax = null;
    display.dispose();
    focusNode.dispose();
    super.dispose();
  }
}
