import 'patch.dart';

/// where a selection tries to stay as it is moved up and down, so that a short
/// line does not move the column it came from
sealed class SelectionGoal {
  const SelectionGoal();

  static const none = NoGoal();
}

class NoGoal extends SelectionGoal {
  const NoGoal();
}

class HorizontalPosition extends SelectionGoal {
  const HorizontalPosition(this.x);

  final double x;

  @override
  bool operator ==(Object other) => other is HorizontalPosition && other.x == x;

  @override
  int get hashCode => x.hashCode;
}

class HorizontalRange extends SelectionGoal {
  const HorizontalRange(this.start, this.end);

  final double start;
  final double end;

  @override
  bool operator ==(Object other) =>
      other is HorizontalRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// a range of a text that is selected; a cursor is a selection with nothing
/// in it. [start] is never after [end], and [reversed] says that the head, the
/// end that moves, is [start].
class Selection {
  const Selection({
    required this.id,
    required this.start,
    required this.end,
    this.reversed = false,
    this.goal = SelectionGoal.none,
  }) : assert(start <= end);

  final int id;
  final int start;
  final int end;
  final bool reversed;
  final SelectionGoal goal;

  bool get isEmpty => start == end;
  int get length => end - start;

  /// where the selection stopped at
  int get head => reversed ? start : end;

  /// where the selection began from
  int get tail => reversed ? end : start;

  Selection copyWith({
    int? start,
    int? end,
    bool? reversed,
    SelectionGoal? goal,
  }) {
    return Selection(
      id: id,
      start: start ?? this.start,
      end: end ?? this.end,
      reversed: reversed ?? this.reversed,
      goal: goal ?? this.goal,
    );
  }

  Selection collapseTo(int offset, [SelectionGoal goal = SelectionGoal.none]) {
    return Selection(id: id, start: offset, end: offset, goal: goal);
  }

  /// the selection with its head moved to [head], which may pass the tail
  Selection withHead(int head, [SelectionGoal goal = SelectionGoal.none]) {
    final tail = this.tail;
    return head < tail
        ? Selection(id: id, start: head, end: tail, reversed: true, goal: goal)
        : Selection(id: id, start: tail, end: head, goal: goal);
  }

  /// the selection with its tail moved to [tail], which may pass the head
  Selection withTail(int tail, [SelectionGoal goal = SelectionGoal.none]) {
    final head = this.head;
    return tail <= head
        ? Selection(id: id, start: tail, end: head, goal: goal)
        : Selection(id: id, start: head, end: tail, reversed: true, goal: goal);
  }

  Selection withHeadAndTail(
    int head,
    int tail, [
    SelectionGoal goal = SelectionGoal.none,
  ]) {
    return head < tail
        ? Selection(id: id, start: head, end: tail, reversed: true, goal: goal)
        : Selection(id: id, start: tail, end: head, goal: goal);
  }

  Selection swapHeadAndTail() => copyWith(reversed: !reversed);

  @override
  bool operator ==(Object other) =>
      other is Selection &&
      other.id == id &&
      other.start == start &&
      other.end == end &&
      other.reversed == reversed &&
      other.goal == goal;

  @override
  int get hashCode => Object.hash(id, start, end, reversed, goal);

  @override
  String toString() =>
      'Selection#$id($start..$end${reversed ? ', reversed' : ''})';
}

/// whether two selections, the first of which does not start after the
/// second, are to become one: when they overlap or start in the same place,
/// or when a cursor is at the edge of the other. two selections that only
/// touch, the one ending where the other starts, stay apart.
bool shouldMerge(int aStart, int aEnd, int bStart, int bEnd) {
  final overlapping = bStart < aEnd;
  final sameStart = aStart == bStart;
  final aIsCursor = aStart == aEnd;
  final bIsCursor = bStart == bEnd;
  final cursorAtEdge =
      (aIsCursor && (aStart == bStart || aEnd == bEnd)) ||
      (bIsCursor && (bStart == aStart || bEnd == aEnd));
  return overlapping || sameStart || cursorAtEdge;
}

/// the selections of an editor: one or more, in order, and none that
/// overlaps another
class SelectionsCollection {
  SelectionsCollection() {
    _selections = [Selection(id: _nextId++, start: 0, end: 0)];
  }

  late List<Selection> _selections;
  int _nextId = 0;

  List<Selection> get all => List.unmodifiable(_selections);

  int get length => _selections.length;

  /// the selection that was made last, which is the one to scroll to
  Selection get newest => _selections.reduce((a, b) => b.id > a.id ? b : a);

  /// the selection that was made first
  Selection get oldest => _selections.reduce((a, b) => b.id < a.id ? b : a);

  Selection get first => _selections.first;
  Selection get last => _selections.last;

  /// a selection of [start] to [end] that has an id of its own, to be given to
  /// [select]; [end] before [start] makes a reversed one
  Selection make(int start, int end, {SelectionGoal? goal}) {
    final reversed = start > end;
    return Selection(
      id: _nextId++,
      start: reversed ? end : start,
      end: reversed ? start : end,
      reversed: reversed,
      goal: goal ?? SelectionGoal.none,
    );
  }

  /// replaces the selections; they are put in order, and the ones that
  /// should be one are made one. there is always at least one.
  void select(Iterable<Selection> selections) {
    final sorted = selections.toList()
      ..sort((a, b) {
        final byStart = a.start.compareTo(b.start);
        return byStart != 0 ? byStart : a.end.compareTo(b.end);
      });
    if (sorted.isEmpty) {
      sorted.add(Selection(id: _nextId++, start: 0, end: 0));
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
    _selections = merged;
  }

  /// the selections [ranges] of start and end, each a cursor when they are
  /// the same
  void selectRanges(Iterable<(int, int)> ranges) {
    select([for (final (start, end) in ranges) make(start, end)]);
  }

  /// puts a cursor in the selections, which is one more cursor to type with
  void addCursor(int offset) {
    select([..._selections, make(offset, offset)]);
  }

  /// follows the text through [patch]. a selection does not take in what is
  /// put in at its edges, and a cursor goes after what is put in at it.
  void mapEdits(Patch patch) {
    if (patch.isEmpty) {
      return;
    }
    select([
      for (final s in _selections)
        if (s.isEmpty)
          s.collapseTo(patch.mapOffset(s.start, Bias.right), s.goal)
        else
          _mapRange(s, patch),
    ]);
  }

  Selection _mapRange(Selection s, Patch patch) {
    final start = patch.mapOffset(s.start, Bias.right);
    final end = patch.mapOffset(s.end, Bias.left);
    // a range that was all replaced has nothing left of it
    return s.copyWith(start: start, end: end < start ? start : end);
  }
}
