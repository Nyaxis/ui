import 'dart:math' as math;

import '../buffer.dart' show BufferSnapshot;
import '../highlight.dart' show HighlightStyle, Highlights;
import '../edit_patch.dart';
import '../point.dart';
import '../sum_tree.dart';
import '../text_metrics.dart';
import '../text_summary.dart';
import 'layer_edit.dart';
import 'line_wrapper.dart';
import 'tab_map.dart';

/// rows of the wrap layer that changed: what was rows [oldStart] to [oldEnd]
/// is now rows [newStart] to [newEnd]
typedef RowEdit = LayerEdit;

/// a line that is wrapped lets other work go on after this many rows
const int _wrapYieldRowInterval = 100;

class _Transform {
  const _Transform(this.summary, [this.displayText]);

  /// text of the tab layer, shown as it is
  factory _Transform.isomorphic(TextSummary summary) {
    final s = _withoutLen(summary);
    return _Transform(_Summary(s, s));
  }

  /// a place where a line wraps: the end of a row, and the indent of the next
  factory _Transform.wrap(int indent) => _Transform(
    _Summary(
      TextSummary.zero,
      TextSummary(
        lines: Point(1, indent),
        lastLineChars: indent,
        longestRow: 1,
        longestRowChars: indent,
      ),
    ),
    '\n${' ' * indent}',
  );

  final _Summary summary;
  final String? displayText;

  bool get isIsomorphic => displayText == null;
}

/// the layers from the tabs up do not count how long text is
TextSummary _withoutLen(TextSummary s) => s.len == 0
    ? s
    : TextSummary(
        lines: s.lines,
        firstLineChars: s.firstLineChars,
        lastLineChars: s.lastLineChars,
        longestRow: s.longestRow,
        longestRowChars: s.longestRowChars,
      );

class _Summary {
  const _Summary(this.input, this.output);

  static const zero = _Summary(TextSummary.zero, TextSummary.zero);

  /// the text of the tab layer
  final TextSummary input;

  /// the text as it is wrapped
  final TextSummary output;

  bool get hasWraps => input.lines != output.lines;

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

typedef _Tree = SumTree<_Transform, _Summary>;

SeekTarget<_Summary> _tabPoint(Point point) =>
    (p) => point.compareTo(p.input.lines);
SeekTarget<_Summary> _wrapPoint(Point point) =>
    (p) => point.compareTo(p.output.lines);

_Tree _pushOrExtend(_Tree tree, _Transform transform) {
  final last = tree.last;
  if (transform.isIsomorphic && last != null && last.isIsomorphic) {
    return tree.updateLast((_) => _Transform(last.summary + transform.summary));
  }
  return tree.push(transform);
}

void _pushIsomorphic(List<_Transform> transforms, TextSummary summary) {
  final transform = _Transform.isomorphic(summary);
  if (transforms.isNotEmpty && transforms.last.isIsomorphic) {
    transforms[transforms.length - 1] = _Transform(
      transforms.last.summary + transform.summary,
    );
  } else {
    transforms.add(transform);
  }
}

_Tree _initial(TabSnapshot tabSnapshot) {
  final extent = tabSnapshot.textSummary;
  final tree = _Tree(_ops);
  return extent.lines == Point.zero
      ? tree
      : tree.push(_Transform.isomorphic(extent));
}

/// decides where lines wrap. it is the fourth layer of the display: its text
/// is the text of the tab layer with each line that is too wide broken into
/// rows.
///
/// wrapping many rows takes long, so it is not always done at once. work that
/// is not done within a short time goes on in the background, a part at a
/// time; until it is done, the layout is one that is interpolated: what was
/// edited is shown as it is in the tab layer, without being wrapped. when the
/// work is done the listeners are told, and the next [sync] gives the rows
/// that changed.
class WrapMap {
  WrapMap(
    TabSnapshot tabSnapshot, {
    this._metrics = const CellMetrics(),
    double? wrapWidth,
    this._softWrapIndent = const IndentAdjustment.sameIndent(),
    this.rewrapBudget = const Duration(milliseconds: 5),
    this.flushBudget = const Duration(milliseconds: 1),
    this.yieldRowInterval = _wrapYieldRowInterval,
  }) : _snapshot = WrapSnapshot._(tabSnapshot, _initial(tabSnapshot), true) {
    setWrapWidth(wrapWidth);
    _editsSinceSync = EditPatch();
  }

  /// work on fewer rows than this is done at once, and work on more lets
  /// other work in after every this many rows
  final int yieldRowInterval;

  /// how long every line being wrapped again may hold up what asked for it,
  /// before it goes on in the background
  final Duration rewrapBudget;

  /// the same, for the rows that edits changed
  final Duration flushBudget;

  TextMetrics _metrics;
  double? _wrapWidth;
  IndentAdjustment _softWrapIndent;
  WrapSnapshot _snapshot;

  /// what the tab layer did that is not wrapped yet
  final List<(TabSnapshot, List<PointEdit>)> _pendingEdits = [];

  /// what the interpolated layouts changed, which is taken back when the
  /// rows are wrapped
  EditPatch _interpolatedEdits = EditPatch();
  EditPatch _editsSinceSync = EditPatch();
  _WrapJob? _backgroundTask;
  final List<void Function()> _listeners = [];

  WrapSnapshot get snapshot => _snapshot;
  double? get wrapWidth => _wrapWidth;

  /// whether rows are still being wrapped, so that the layout is not the one
  /// it will be
  bool get isRewrapping =>
      _backgroundTask != null || (_wrapWidth != null && _snapshot.interpolated);

  /// [listener] is told when rows that were being wrapped in the background
  /// are done
  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  /// stops what goes on in the background
  void dispose() {
    _backgroundTask?.cancelled = true;
    _backgroundTask = null;
    _listeners.clear();
  }

  /// follows the tab layer to [tabSnapshot], which [tabEdits] were made to,
  /// and gives the layout with the rows that changed in it since the last
  /// time
  (WrapSnapshot, List<RowEdit>) sync(
    TabSnapshot tabSnapshot,
    List<PointEdit> tabEdits,
  ) {
    if (_wrapWidth != null) {
      _pendingEdits.add((tabSnapshot, tabEdits));
      _flushEdits();
    } else {
      final (snapshot, edits) = _snapshot._interpolate(tabSnapshot, tabEdits);
      _editsSinceSync = _editsSinceSync.compose(edits);
      _snapshot = snapshot._withInterpolated(false);
    }
    final edits = _editsSinceSync.edits;
    _editsSinceSync = EditPatch();
    return (_snapshot, edits);
  }

  /// sets the width that lines wrap to, or null for lines that do not wrap;
  /// says whether it changed
  bool setWrapWidth(double? wrapWidth) {
    if (wrapWidth == _wrapWidth) {
      return false;
    }
    _wrapWidth = wrapWidth;
    _rewrap();
    return true;
  }

  /// sets how wide characters are, as when the font changes
  bool setMetrics(TextMetrics metrics) {
    if (identical(metrics, _metrics)) {
      return false;
    }
    _metrics = metrics;
    _rewrap();
    return true;
  }

  bool setSoftWrapIndent(IndentAdjustment indent) {
    if (indent == _softWrapIndent) {
      return false;
    }
    _softWrapIndent = indent;
    _rewrap();
    return true;
  }

  /// lays out every line again
  void _rewrap() {
    _backgroundTask?.cancelled = true;
    _backgroundTask = null;
    _interpolatedEdits = EditPatch();
    _pendingEdits.clear();

    final width = _wrapWidth;
    final tab = _snapshot.tabSnapshot;
    if (width != null) {
      final max = tab.maxPoint;
      final job = _WrapJob(
        _snapshot,
        [
          (tab, [PointEdit(Point.zero, max, Point.zero, max)]),
        ],
        width,
        _softWrapIndent,
        LineWrapper(_metrics),
        yieldRowInterval,
      );
      _run(job, max.row + 1 < yieldRowInterval ? null : rewrapBudget);
      return;
    }
    final oldRows = _snapshot.maxPoint.row + 1;
    _snapshot = WrapSnapshot._(tab, _initial(tab), false);
    _editsSinceSync = _editsSinceSync.compose([
      RowEdit(0, oldRows, 0, _snapshot.maxPoint.row + 1),
    ]);
  }

  /// does [job] for as long as [budget], or all of it when there is none;
  /// what is left of it then goes on in the background
  void _run(_WrapJob job, Duration? budget) {
    if (job.runFor(budget)) {
      _snapshot = job.snapshot;
      _editsSinceSync = _editsSinceSync.compose(job.edits.edits);
      return;
    }
    _backgroundTask = job;
    _continueInBackground(job);
  }

  Future<void> _continueInBackground(_WrapJob job) async {
    while (true) {
      // other work is let in between the parts
      await Future<void>.delayed(Duration.zero);
      if (job.cancelled) {
        return;
      }
      if (job.runFor(const Duration(milliseconds: 4))) {
        break;
      }
    }
    _snapshot = job.snapshot;
    final interpolated = _interpolatedEdits;
    _interpolatedEdits = EditPatch();
    _editsSinceSync = _editsSinceSync
        .compose(interpolated.invert().edits)
        .compose(job.edits.edits);
    _backgroundTask = null;
    _flushEdits();
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  /// the pending edits that the layout already has are done with
  int _wrappedPendingEdits() {
    var count = 0;
    for (final (tab, _) in _pendingEdits) {
      if (tab.version <= _snapshot.tabSnapshot.version) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  void _flushEdits() {
    if (!_snapshot.interpolated) {
      _pendingEdits.removeRange(0, _wrappedPendingEdits());
    }
    if (_pendingEdits.isEmpty) {
      return;
    }

    final width = _wrapWidth;
    if (width != null && _backgroundTask == null) {
      final pending = List.of(_pendingEdits);
      var totalNewRows = 0;
      for (final (_, edits) in pending) {
        for (final edit in edits) {
          totalNewRows += math.max(0, edit.newEnd.row - edit.newStart.row) + 1;
        }
      }
      _run(
        _WrapJob(
          _snapshot,
          pending,
          width,
          _softWrapIndent,
          LineWrapper(_metrics),
          yieldRowInterval,
        ),
        pending.length + totalNewRows < yieldRowInterval ? null : flushBudget,
      );
    }

    // what is not wrapped yet is shown as the tab layer has it
    final wasInterpolated = _snapshot.interpolated;
    var toRemove = 0;
    for (final (tab, edits) in _pendingEdits) {
      if (tab.version <= _snapshot.tabSnapshot.version) {
        toRemove++;
      } else {
        final (snapshot, interpolated) = _snapshot._interpolate(tab, edits);
        _snapshot = snapshot;
        _editsSinceSync = _editsSinceSync.compose(interpolated);
        _interpolatedEdits = _interpolatedEdits.compose(interpolated);
      }
    }
    if (!wasInterpolated) {
      _pendingEdits.removeRange(0, toRemove);
    }
  }
}

/// rows being wrapped, which can be done a part at a time
class _WrapJob {
  _WrapJob(
    this.snapshot,
    List<(TabSnapshot, List<PointEdit>)> pending,
    double wrapWidth,
    IndentAdjustment indent,
    LineWrapper wrapper,
    this._yieldRowInterval,
  ) {
    _steps = _run(pending, wrapWidth, indent, wrapper).iterator;
  }

  final int _yieldRowInterval;

  /// the layout, which is the one after all the edits when the job is done
  WrapSnapshot snapshot;

  /// the rows that changed
  EditPatch edits = EditPatch();
  bool cancelled = false;
  late final Iterator<void> _steps;

  Iterable<void> _run(
    List<(TabSnapshot, List<PointEdit>)> pending,
    double wrapWidth,
    IndentAdjustment indent,
    LineWrapper wrapper,
  ) sync* {
    for (final (tab, tabEdits) in pending) {
      final result = _UpdateResult();
      yield* snapshot._update(
        tab,
        tabEdits,
        wrapWidth,
        indent,
        wrapper,
        _yieldRowInterval,
        result,
      );
      snapshot = result.snapshot;
      edits = edits.compose(result.edits);
    }
  }

  /// goes on for [budget], or to the end when there is none; says whether
  /// the job is done
  bool runFor(Duration? budget) {
    final timer = Stopwatch()..start();
    while (_steps.moveNext()) {
      if (budget != null && timer.elapsed >= budget) {
        return false;
      }
    }
    return true;
  }
}

class _UpdateResult {
  late WrapSnapshot snapshot;
  late List<RowEdit> edits;
}

/// a piece of the text of the wrap layer
class WrapChunk {
  const WrapChunk(this.text, {this.tab, this.isWrap = false});

  final String text;

  /// how the text is drawn, from the highlights that are on it
  HighlightStyle? get style => tab?.style;

  /// the piece of the tab layer that the text is, or null for the end of a
  /// row and the indent of the next, which no layer below has
  final TabChunk? tab;
  final bool isWrap;
}

/// the text as it is wrapped at one time. a point "of the wraps" has the row
/// of the screen that a place is on, before blocks are put between rows.
class WrapSnapshot {
  WrapSnapshot._(this.tabSnapshot, this._transforms, this.interpolated);

  final TabSnapshot tabSnapshot;
  final _Tree _transforms;

  /// the buffer that the layers are of
  BufferSnapshot get bufferSnapshot =>
      tabSnapshot.foldSnapshot.inlaySnapshot.bufferSnapshot;

  /// whether some of the rows are shown as the tab layer has them, their
  /// wrapping not being done yet
  final bool interpolated;

  WrapSnapshot _withInterpolated(bool interpolated) =>
      interpolated == this.interpolated
      ? this
      : WrapSnapshot._(tabSnapshot, _transforms, interpolated);

  /// the layout after [tabEdits], with nothing wrapped again: what changed is
  /// taken as it is in the tab layer. this is what there is when lines do not
  /// wrap.
  (WrapSnapshot, List<RowEdit>) _interpolate(
    TabSnapshot newTab,
    List<PointEdit> tabEdits,
  ) {
    _Tree newTransforms;
    if (tabEdits.isEmpty) {
      newTransforms = _transforms;
    } else if (!_transforms.summary.hasWraps &&
        newTab.textSummary.lines != Point.zero) {
      // without wraps, the text is passed through as it is
      newTransforms = _Tree(_ops)
          .push(_Transform.isomorphic(newTab.textSummary));
    } else {
      final oldCursor = _transforms.cursor(_dim);
      newTransforms = oldCursor.slice(
        _tabPoint(tabEdits.first.oldStart),
        Bias.right,
      );
      for (var i = 0; i < tabEdits.length; i++) {
        final edit = tabEdits[i];
        final at = newTransforms.summary.input.lines;
        if (edit.newStart > at) {
          newTransforms = _pushOrExtend(
            newTransforms,
            _Transform.isomorphic(
              newTab.textSummaryForRange(at, edit.newStart),
            ),
          );
        }
        if (edit.newStart != edit.newEnd) {
          newTransforms = _pushOrExtend(
            newTransforms,
            _Transform.isomorphic(
              newTab.textSummaryForRange(edit.newStart, edit.newEnd),
            ),
          );
        }
        oldCursor.seekForward(_tabPoint(edit.oldEnd), Bias.right);
        final cursorEnd = oldCursor.end.input.lines;
        if (i + 1 < tabEdits.length) {
          final next = tabEdits[i + 1];
          if (next.oldStart > cursorEnd) {
            if (cursorEnd > edit.oldEnd) {
              newTransforms = _pushOrExtend(
                newTransforms,
                _Transform.isomorphic(
                  tabSnapshot.textSummaryForRange(edit.oldEnd, cursorEnd),
                ),
              );
            }
            oldCursor.next();
            newTransforms = newTransforms.append(
              oldCursor.slice(_tabPoint(next.oldStart), Bias.right),
            );
          }
        } else {
          if (cursorEnd > edit.oldEnd) {
            newTransforms = _pushOrExtend(
              newTransforms,
              _Transform.isomorphic(
                tabSnapshot.textSummaryForRange(edit.oldEnd, cursorEnd),
              ),
            );
          }
          oldCursor.next();
          newTransforms = newTransforms.append(oldCursor.suffix());
        }
      }
    }
    final next = WrapSnapshot._(newTab, newTransforms, true);
    return (next, _computeEdits(tabEdits, next));
  }

  /// puts in [result] the layout after [tabEdits], with the rows that they
  /// are on wrapped again to [wrapWidth]. it is done in steps, so that what
  /// asks for it can let other work in between them.
  Iterable<void> _update(
    TabSnapshot newTab,
    List<PointEdit> tabEdits,
    double wrapWidth,
    IndentAdjustment indentAdjustment,
    LineWrapper wrapper,
    int yieldRowInterval,
    _UpdateResult result,
  ) sync* {
    // the rows that the edits are on, with the edits that share rows as one
    final rowEdits = <List<int>>[];
    for (final edit in tabEdits) {
      if (rowEdits.isNotEmpty && edit.oldStart.row <= rowEdits.last[1]) {
        final last = rowEdits.last;
        last[1] = math.max(last[1], edit.oldEnd.row + 1);
        last[3] = math.max(last[3], edit.newEnd.row + 1);
      } else {
        rowEdits.add([
          edit.oldStart.row,
          edit.oldEnd.row + 1,
          edit.newStart.row,
          edit.newEnd.row + 1,
        ]);
      }
    }

    _Tree newTransforms;
    if (rowEdits.isEmpty) {
      newTransforms = _transforms;
    } else {
      final oldCursor = _transforms.cursor(_dim);
      newTransforms = oldCursor.slice(
        _tabPoint(Point(rowEdits.first[0], 0)),
        Bias.right,
      );
      for (var e = 0; e < rowEdits.length; e++) {
        final oldRowsEnd = rowEdits[e][1];
        final newRowsStart = rowEdits[e][2];
        final newRowsEnd = rowEdits[e][3];

        final at = newTransforms.summary.input.lines;
        if (newRowsStart > at.row) {
          newTransforms = _pushOrExtend(
            newTransforms,
            _Transform.isomorphic(
              newTab.textSummaryForRange(at, Point(newRowsStart, 0)),
            ),
          );
        }

        final lines = _lines(
          newTab,
          Point(newRowsStart, 0),
          newTab.maxPoint,
        ).iterator;
        final editTransforms = <_Transform>[];
        for (var row = newRowsStart; row < newRowsEnd; row++) {
          if (!lines.moveNext() || lines.current.isEmpty) {
            break;
          }
          final line = lines.current;
          var previous = 0;
          for (final boundary in wrapper.wrapLine(
            line,
            wrapWidth,
            indentAdjustment,
          )) {
            _pushIsomorphic(
              editTransforms,
              TextSummary.of(line, previous, boundary.ix),
            );
            editTransforms.add(_Transform.wrap(boundary.nextIndent));
            previous = boundary.ix;
          }
          if (previous < line.length) {
            _pushIsomorphic(editTransforms, TextSummary.of(line, previous));
          }
          if ((row - newRowsStart) % yieldRowInterval == yieldRowInterval - 1) {
            yield null;
          }
        }
        if (editTransforms.isNotEmpty) {
          newTransforms = _pushOrExtend(newTransforms, editTransforms.first);
          newTransforms = newTransforms.extend(editTransforms.skip(1));
        }

        final oldEnd = Point(oldRowsEnd, 0);
        oldCursor.seekForward(_tabPoint(oldEnd), Bias.right);
        final cursorEnd = oldCursor.end.input.lines;
        if (e + 1 < rowEdits.length) {
          final nextOldStart = rowEdits[e + 1][0];
          if (nextOldStart > cursorEnd.row) {
            if (cursorEnd > oldEnd) {
              newTransforms = _pushOrExtend(
                newTransforms,
                _Transform.isomorphic(
                  tabSnapshot.textSummaryForRange(oldEnd, cursorEnd),
                ),
              );
            }
            oldCursor.next();
            newTransforms = newTransforms.append(
              oldCursor.slice(_tabPoint(Point(nextOldStart, 0)), Bias.right),
            );
          }
          yield null;
        } else {
          if (cursorEnd > oldEnd) {
            newTransforms = _pushOrExtend(
              newTransforms,
              _Transform.isomorphic(
                tabSnapshot.textSummaryForRange(oldEnd, cursorEnd),
              ),
            );
          }
          oldCursor.next();
          newTransforms = newTransforms.append(oldCursor.suffix());
        }
      }
    }
    final next = WrapSnapshot._(newTab, newTransforms, false);
    result
      ..snapshot = next
      ..edits = _computeEdits(tabEdits, next);
  }

  /// the lines of [tab] from [start] to [end], each with the `\n` that ends
  /// it, read only as they are asked for
  static Iterable<String> _lines(
    TabSnapshot tab,
    Point start,
    Point end,
  ) sync* {
    var line = StringBuffer();
    for (final chunk in tab.chunks(start, end)) {
      var text = chunk.text;
      while (true) {
        final newline = text.indexOf('\n');
        if (newline < 0) {
          line.write(text);
          break;
        }
        line.write(text.substring(0, newline + 1));
        yield line.toString();
        line = StringBuffer();
        text = text.substring(newline + 1);
      }
    }
    yield line.toString();
  }

  List<RowEdit> _computeEdits(List<PointEdit> tabEdits, WrapSnapshot next) {
    final edits = <RowEdit>[];
    final oldCursor = _transforms.cursor(_dim);
    final newCursor = next._transforms.cursor(_dim);
    for (final edit in tabEdits) {
      final oldStart = Point(edit.oldStart.row, 0);
      final oldEnd = Point(edit.oldEnd.row + 1, 0);
      final newStart = Point(edit.newStart.row, 0);
      final newEnd = Point(edit.newEnd.row + 1, 0);

      oldCursor.seek(_tabPoint(oldStart), Bias.right);
      final oldStartRow =
          (oldCursor.start.output.lines +
                  (oldStart - oldCursor.start.input.lines))
              .row;
      oldCursor.seekForward(_tabPoint(oldEnd), Bias.right);
      final oldEndRow =
          (oldCursor.start.output.lines +
                  (oldEnd - oldCursor.start.input.lines))
              .row;
      newCursor.seek(_tabPoint(newStart), Bias.right);
      final newStartRow =
          (newCursor.start.output.lines +
                  (newStart - newCursor.start.input.lines))
              .row;
      newCursor.seekForward(_tabPoint(newEnd), Bias.right);
      final newEndRow =
          (newCursor.start.output.lines +
                  (newEnd - newCursor.start.input.lines))
              .row;
      edits.add(RowEdit(oldStartRow, oldEndRow, newStartRow, newEndRow));
    }
    // the ones that touch are one
    final out = <RowEdit>[];
    for (final edit in edits) {
      if (out.isNotEmpty && out.last.oldEnd >= edit.oldStart) {
        final last = out.last;
        out[out.length - 1] = RowEdit(
          last.oldStart,
          math.max(last.oldEnd, edit.oldEnd),
          last.newStart,
          math.max(last.newEnd, edit.newEnd),
        );
      } else {
        out.add(edit);
      }
    }
    return out;
  }

  Point get maxPoint => _transforms.summary.output.lines;
  int get longestRow => _transforms.summary.output.longestRow;

  /// how long row [row] is, with the indent it has when it continues a line
  int lineLen(int row) {
    final (start, _, item) = _transforms.find(
      _dim,
      _wrapPoint(Point(row + 1, 0)),
      Bias.left,
    );
    if (item != null && item.isIsomorphic) {
      final overshoot = row - start.output.lines.row;
      final tabRow = start.input.lines.row + overshoot;
      final tabLineLen = tabSnapshot.lineLen(tabRow);
      return overshoot == 0
          ? start.output.lines.column + (tabLineLen - start.input.lines.column)
          : tabLineLen;
    }
    return start.output.lines.column;
  }

  /// whether row [row] continues a line that wrapped
  bool isSoftWrapped(int row) => row > 0 && softWrapIndent(row - 1) != null;

  /// the indent of the row after [row] when that row continues a line that
  /// wrapped, or null when it starts a line
  int? softWrapIndent(int row) {
    final (_, _, item) = _transforms.find(
      _dim,
      _wrapPoint(Point(row + 1, 0)),
      Bias.left,
    );
    return item == null || item.isIsomorphic
        ? null
        : item.summary.output.lines.column;
  }

  /// the tab point of the wrap point [point]
  Point toTabPoint(Point point) {
    final (start, _, item) = _transforms.find(
      _dim,
      _wrapPoint(point),
      Bias.right,
    );
    return item != null && item.isIsomorphic
        ? start.input.lines + (point - start.output.lines)
        : start.input.lines;
  }

  /// the point of the buffer of the wrap point [point]
  Point toPoint(Point point, Bias bias) =>
      tabSnapshot.tabPointToPoint(toTabPoint(point), bias);

  /// the wrap point of the point [point] of the buffer
  Point makeWrapPoint(Point point, Bias bias) =>
      tabPointToWrapPoint(tabSnapshot.pointToTabPoint(point, bias));

  /// the wrap point of the tab point [point]
  Point tabPointToWrapPoint(Point point) {
    final (start, _, _) = _transforms.find(_dim, _tabPoint(point), Bias.right);
    return start.output.lines + (point - start.input.lines);
  }

  Point clipPoint(Point point, Bias bias) {
    var at = point;
    if (bias == Bias.left) {
      final (start, _, item) = _transforms.find(
        _dim,
        _wrapPoint(at),
        Bias.right,
      );
      if (item != null && !item.isIsomorphic) {
        // in the indent of a row that continues a line: the end of the row
        // before it
        at = Point(start.output.lines.row, start.output.lines.column - 1);
      }
    }
    return tabPointToWrapPoint(tabSnapshot.clipPoint(toTabPoint(at), bias));
  }

  /// the row at or before the row of [point] that starts a line of the tab
  /// layer, found without going over every row
  int prevRowBoundary(Point point) {
    if (_transforms.isEmpty) {
      return 0;
    }
    final at = Point(point.row, 0);
    final cursor = _transforms.cursor(_dim)..seek(_wrapPoint(at), Bias.right);
    if (cursor.item == null) {
      cursor.prev();
    }
    while (true) {
      final item = cursor.item;
      if (item == null) {
        return 0;
      }
      if (item.isIsomorphic) {
        // a transform of text as it is has only the ends of lines in it
        if (item.summary.input.lines.row > 1) {
          return math.min(cursor.end.output.lines.row - 1, at.row);
        } else if (cursor.start.input.lines.column == 0) {
          return math.min(cursor.end.output.lines.row, at.row);
        }
      }
      cursor.prev();
    }
  }

  /// the row after the row of [point] that starts a line of the tab layer
  int? nextRowBoundary(Point point) {
    final at = point + const Point(1, 0);
    final cursor = _transforms.cursor(_dim)..seek(_wrapPoint(at), Bias.right);
    while (true) {
      final item = cursor.item;
      if (item == null) {
        return null;
      }
      if (item.isIsomorphic && cursor.start.input.lines.column == 0) {
        return math.max(cursor.start.output.lines.row, at.row);
      }
      cursor.next();
    }
  }

  /// what rows [startRow] to [endRow] come to
  TextSummary textSummaryForRange(int startRow, int endRow) {
    var summary = TextSummary.zero;
    final start = Point(startRow, 0);
    final end = Point(endRow, 0);
    final cursor = _transforms.cursor(_dim)
      ..seek(_wrapPoint(start), Bias.right);
    final first = cursor.item;
    if (first != null) {
      final from = start - cursor.start.output.lines;
      final stop = end < cursor.end.output.lines
          ? end
          : cursor.end.output.lines;
      final to = stop - cursor.start.output.lines;
      if (first.isIsomorphic) {
        summary += _withoutLen(
          tabSnapshot.textSummaryForRange(
            cursor.start.input.lines + from,
            cursor.start.input.lines + to,
          ),
        );
      } else {
        final indent = to.column - from.column;
        summary += TextSummary(
          lines: Point(0, indent),
          firstLineChars: indent,
          lastLineChars: indent,
          longestRowChars: indent,
        );
      }
      cursor.next();
    }
    if (endRow > cursor.start.output.lines.row) {
      summary += cursor.summary(_dim, _wrapPoint(end), Bias.right).output;
      final last = cursor.item;
      if (last != null) {
        final to = end - cursor.start.output.lines;
        if (last.isIsomorphic) {
          summary += _withoutLen(
            tabSnapshot.textSummaryForRange(
              cursor.start.input.lines,
              cursor.start.input.lines + to,
            ),
          );
        } else {
          summary += const TextSummary(lines: Point(1, 0));
        }
      }
    }
    return summary;
  }

  /// the pieces of the text from the wrap point [start] to [end]
  Iterable<WrapChunk> chunks(
    Point start,
    Point end, [
    Highlights highlights = Highlights.none,
  ]) sync* {
    final max = maxPoint;
    final stop = end < max ? end : max;
    final cursor = _transforms.cursor(_dim)
      ..seek(_wrapPoint(start), Bias.right);
    while (true) {
      final item = cursor.item;
      final itemStart = cursor.start.output.lines;
      if (item == null || itemStart >= stop) {
        return;
      }
      final itemEnd = cursor.end.output.lines;
      final from = (start > itemStart ? start : itemStart) - itemStart;
      final to = (stop < itemEnd ? stop : itemEnd) - itemStart;
      final text = item.displayText;
      if (text != null) {
        final piece = text.substring(
          pointToOffsetIn(text, from),
          pointToOffsetIn(text, to),
        );
        if (piece.isNotEmpty) {
          yield WrapChunk(piece, isWrap: true);
        }
      } else {
        final tabStart = cursor.start.input.lines;
        for (final chunk in tabSnapshot.chunks(
          tabStart + from,
          tabStart + to,
          highlights,
        )) {
          yield WrapChunk(chunk.text, tab: chunk);
        }
      }
      cursor.next();
    }
  }

  /// the text as it is wrapped
  String get text =>
      [for (final chunk in chunks(Point.zero, maxPoint)) chunk.text].join();

  /// the row of the buffer that row [row] shows part of, and whether the row
  /// continues a line that wrapped
  ({int bufferRow, bool softWrapped}) rowInfo(int row) {
    final tabPoint = toTabPoint(Point(row, 0));
    return (
      bufferRow: tabSnapshot
          .tabPointToPoint(Point(tabPoint.row, 0), Bias.left)
          .row,
      softWrapped: isSoftWrapped(row),
    );
  }
}
