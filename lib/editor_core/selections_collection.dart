import 'buffer.dart';
import 'selection.dart';

export 'selection.dart';

/// the selections of an editor: one or more, in order, and none that
/// overlaps another. they are kept as anchors of the buffer, so that they
/// follow the text through every edit, and are resolved when asked for.
class SelectionsCollection {
  SelectionsCollection(this.buffer) {
    _anchors = [AnchorSelection.of(_make(0, 0), buffer.snapshot)];
  }

  final TextBuffer buffer;
  late List<AnchorSelection> _anchors;
  int _nextId = 1;

  List<Selection>? _resolved;
  int _resolvedVersion = -1;

  Selection _make(int start, int end, {SelectionGoal? goal}) {
    final reversed = start > end;
    return Selection(
      id: _nextId++,
      start: reversed ? end : start,
      end: reversed ? start : end,
      reversed: reversed,
      goal: goal ?? SelectionGoal.none,
    );
  }

  /// the selections as they are in the text now, in order, those that have
  /// come to overlap made one
  List<Selection> get all {
    final snapshot = buffer.snapshot;
    final cached = _resolved;
    if (cached != null && _resolvedVersion == snapshot.version) {
      return cached;
    }
    final resolved = _coalesce([
      for (final anchored in _anchors) anchored.resolve(snapshot),
    ]);
    _resolved = List.unmodifiable(resolved);
    _resolvedVersion = snapshot.version;
    return _resolved!;
  }

  /// the selections as anchors, which are the same text whatever is edited
  List<AnchorSelection> get anchors => List.unmodifiable(_anchors);

  int get length => all.length;

  /// the selection that was made last, which is the one to scroll to
  Selection get newest => all.reduce((a, b) => b.id > a.id ? b : a);

  /// the selection that was made first
  Selection get oldest => all.reduce((a, b) => b.id < a.id ? b : a);

  Selection get first => all.first;
  Selection get last => all.last;

  /// a selection of [start] to [end] that has an id of its own, to be given to
  /// [select]; [end] before [start] makes a reversed one
  Selection make(int start, int end, {SelectionGoal? goal}) =>
      _make(start, end, goal: goal);

  /// replaces the selections; they are put in order, and the ones that
  /// should be one are made one. there is always at least one.
  void select(Iterable<Selection> selections) {
    final merged = _coalesce(selections.toList());
    if (merged.isEmpty) {
      merged.add(_make(0, 0));
    }
    selectAnchors([
      for (final s in merged) AnchorSelection.of(s, buffer.snapshot),
    ]);
  }

  /// replaces the selections with ones that are anchors already, such as the
  /// ones a transaction gives back
  void selectAnchors(Iterable<AnchorSelection> selections) {
    _anchors = selections.toList();
    if (_anchors.isEmpty) {
      _anchors = [AnchorSelection.of(_make(0, 0), buffer.snapshot)];
    }
    _resolved = null;
  }

  /// the selections [ranges] of start and end, each a cursor when they are
  /// the same
  void selectRanges(Iterable<(int, int)> ranges) {
    select([for (final (start, end) in ranges) _make(start, end)]);
  }

  /// puts a cursor in the selections, which is one more cursor to type with
  void addCursor(int offset) {
    select([...all, _make(offset, offset)]);
  }

  /// [selections] in order, with the ones that should be one made one
  static List<Selection> _coalesce(List<Selection> selections) {
    final sorted = List.of(selections)
      ..sort((a, b) {
        final byStart = a.start.compareTo(b.start);
        return byStart != 0 ? byStart : a.end.compareTo(b.end);
      });
    if (sorted.isEmpty) {
      return [];
    }
    final merged = <Selection>[sorted.first];
    for (var i = 1; i < sorted.length; i++) {
      final prev = merged.last;
      final current = sorted[i];
      if (shouldMerge(prev.start, prev.end, current.start, current.end)) {
        if (current.end > prev.end) {
          merged[merged.length - 1] = prev.copyWith(end: current.end);
        }
      } else {
        merged.add(current);
      }
    }
    return merged;
  }
}
