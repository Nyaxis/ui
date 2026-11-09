import 'patch.dart';
import 'point.dart';
import 'rope.dart';
import 'selection.dart';

/// the line ending a file has, which is put back when it is saved
enum LineEnding {
  lf('\n'),
  crlf('\r\n');

  const LineEnding(this.text);

  final String text;

  /// the one that [text] has most of, and lf when it has none
  static LineEnding detect(String text) {
    var crlf = 0;
    var lf = 0;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        if (i > 0 && text.codeUnitAt(i - 1) == 0x0D) {
          crlf++;
        } else {
          lf++;
        }
      }
    }
    return crlf > lf ? LineEnding.crlf : LineEnding.lf;
  }
}

/// [text] with every line ending a `\n`, which is what the rope holds
String normalizeLineEndings(String text) {
  if (!text.contains('\r')) {
    return text;
  }
  return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

/// a range of the text to be replaced by [text]
class Replacement {
  const Replacement(this.start, this.end, this.text);

  /// [text] put in at [offset], taking nothing out
  const Replacement.insert(int offset, String text)
    : this(offset, offset, text);

  final int start;
  final int end;
  final String text;

  @override
  String toString() => 'Replacement($start..$end, ${text.length} units)';
}

/// the edits that were made together, which one undo takes back
class Transaction {
  Transaction._(this.startedAt, this.selectionsBefore) : lastEditAt = startedAt;

  final DateTime startedAt;
  DateTime lastEditAt;

  /// the selections before the first edit, which undo goes back to
  final List<Selection>? selectionsBefore;

  /// the selections after the last edit, which redo goes back to
  List<Selection>? selectionsAfter;

  final List<_Step> _steps = [];

  bool get isEmpty => _steps.isEmpty;
}

class _Step {
  _Step(this.forward, this.inverse);

  /// the replacements in the offsets of the text before the step
  final List<Replacement> forward;

  /// the replacements that take the step back, in the offsets after it
  final List<Replacement> inverse;
}

enum ChangeKind { edit, undo, redo }

/// what happened to the text of a buffer
class BufferChange {
  const BufferChange(this.patch, this.kind);

  final Patch patch;
  final ChangeKind kind;
}

/// the text of a document, which is edited in batches that can be undone
class TextBuffer {
  TextBuffer([
    String text = '',
    this.groupInterval = const Duration(milliseconds: 300),
    DateTime Function()? clock,
  ]) : lineEnding = LineEnding.detect(text),
       _clock = clock ?? DateTime.now,
       _text = Rope(normalizeLineEndings(text));

  final DateTime Function() _clock;

  /// edits made within this long of each other are undone together
  final Duration groupInterval;

  /// what the file had, and what it gets back when saved
  LineEnding lineEnding;

  Rope _text;
  int _version = 0;

  final List<Transaction> _undoStack = [];
  final List<Transaction> _redoStack = [];
  Transaction? _open;
  int _depth = 0;
  bool _sealed = false;

  final List<void Function(BufferChange)> _listeners = [];

  /// the text as it is now; it does not change, so it can be kept
  Rope get text => _text;

  /// the number of times the text has changed
  int get version => _version;

  int get length => _text.length;
  int get lineCount => _text.lineCount;

  /// the text with the line endings the file has
  String textForSave() => lineEnding == LineEnding.lf
      ? _text.toString()
      : _text.toString().replaceAll('\n', lineEnding.text);

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void addListener(void Function(BufferChange) listener) =>
      _listeners.add(listener);

  void removeListener(void Function(BufferChange) listener) =>
      _listeners.remove(listener);

  Point offsetToPoint(int offset) => _text.offsetToPoint(offset);
  int pointToOffset(Point point) => _text.pointToOffset(point);

  /// starts a group of edits that is undone as one, with the [selections] to
  /// go back to. groups may be started inside each other, and the outermost
  /// is the one that counts.
  void beginTransaction([List<Selection>? selections]) {
    if (_depth++ == 0) {
      _open = Transaction._(_clock(), selections);
    }
  }

  /// ends the group, with the [selections] that redo goes back to
  void endTransaction([List<Selection>? selections]) {
    assert(_depth > 0, 'no transaction is open');
    if (--_depth > 0) {
      return;
    }
    final transaction = _open!;
    _open = null;
    if (transaction.isEmpty) {
      return;
    }
    transaction.selectionsAfter = selections;
    final previous = _undoStack.isEmpty ? null : _undoStack.last;
    if (previous != null &&
        !_sealed &&
        transaction.startedAt.difference(previous.lastEditAt) <=
            groupInterval) {
      previous._steps.addAll(transaction._steps);
      previous.lastEditAt = transaction.lastEditAt;
      previous.selectionsAfter = selections;
    } else {
      _undoStack.add(transaction);
    }
    _sealed = false;
  }

  /// makes the next edit start a group of its own, however soon it comes
  void finalizeLastTransaction() {
    if (_open == null) {
      _sealed = true;
    }
  }

  /// replaces the ranges of [replacements] at once. they are in the offsets of
  /// the text as it is, and may not overlap; the patch that is returned is
  /// what the edit did to the text.
  Patch edit(Iterable<Replacement> replacements) {
    final sorted = [
      for (final r in replacements)
        Replacement(r.start, r.end, normalizeLineEndings(r.text)),
    ]..sort((a, b) => a.start != b.start ? a.start - b.start : a.end - b.end);
    // one that puts back what is there, or nothing for nothing, is no edit
    sorted.removeWhere((r) => r.start == r.end && r.text.isEmpty);
    var previousEnd = 0;
    for (final r in sorted) {
      if (r.start < previousEnd || r.end < r.start || r.end > length) {
        throw ArgumentError(
          'bad range ${r.start}..${r.end} for a text of $length units',
        );
      }
      previousEnd = r.end;
    }
    return _apply(sorted);
  }

  /// [edit] inside a group of its own when none is open
  Patch _apply(List<Replacement> sorted) {
    if (sorted.isEmpty) {
      return Patch.empty;
    }
    final own = _depth == 0;
    if (own) {
      beginTransaction();
    }
    final transaction = _open!;
    final inverse = <Replacement>[];
    final edits = <Edit>[];
    var delta = 0;
    for (final r in sorted) {
      final start = r.start + delta;
      inverse.add(
        Replacement(
          start,
          start + r.text.length,
          _text.substring(r.start, r.end),
        ),
      );
      edits.add(Edit(r.start, r.end - r.start, r.text.length));
      delta += r.text.length - (r.end - r.start);
    }
    var text = _text;
    for (var i = sorted.length - 1; i >= 0; i--) {
      text = text.replaceRange(sorted[i].start, sorted[i].end, sorted[i].text);
    }
    _text = text;
    _version++;
    transaction._steps.add(_Step(sorted, inverse));
    transaction.lastEditAt = _clock();
    _redoStack.clear();
    final patch = Patch(edits);
    if (own) {
      endTransaction();
    }
    _notify(BufferChange(patch, ChangeKind.edit));
    return patch;
  }

  /// takes back the last group of edits, and returns it, so that its
  /// selections can be put back; null when there is nothing to undo
  Transaction? undo() {
    if (_open != null || _undoStack.isEmpty) {
      return null;
    }
    final transaction = _undoStack.removeLast();
    for (final step in transaction._steps.reversed) {
      _replay(step.inverse, ChangeKind.undo);
    }
    _redoStack.add(transaction);
    _sealed = true;
    return transaction;
  }

  /// does again what was undone, and returns it; null when there is nothing
  Transaction? redo() {
    if (_open != null || _redoStack.isEmpty) {
      return null;
    }
    final transaction = _redoStack.removeLast();
    for (final step in transaction._steps) {
      _replay(step.forward, ChangeKind.redo);
    }
    _undoStack.add(transaction);
    _sealed = true;
    return transaction;
  }

  void _replay(List<Replacement> replacements, ChangeKind kind) {
    final edits = <Edit>[];
    for (final r in replacements) {
      edits.add(Edit(r.start, r.end - r.start, r.text.length));
    }
    var text = _text;
    for (var i = replacements.length - 1; i >= 0; i--) {
      text = text.replaceRange(
        replacements[i].start,
        replacements[i].end,
        replacements[i].text,
      );
    }
    _text = text;
    _version++;
    _notify(BufferChange(Patch(edits), kind));
  }

  void _notify(BufferChange change) {
    for (final listener in List.of(_listeners)) {
      listener(change);
    }
  }
}
