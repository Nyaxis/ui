import 'anchor.dart';
import 'buffer.dart' show BufferSnapshot;
import 'patch.dart' show Bias;

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

/// a selection that stays with its text as the buffer is edited. like a
/// [Selection], it is resolved against a buffer snapshot to say where it is.
/// it does not take in text put in at its edges, and a cursor goes after the
/// text put in at it.
class AnchorSelection {
  const AnchorSelection({
    required this.id,
    required this.start,
    required this.end,
    this.reversed = false,
    this.goal = SelectionGoal.none,
  });

  /// [selection] made into anchors of [buffer]
  factory AnchorSelection.of(Selection selection, BufferSnapshot buffer) {
    final endBias = selection.isEmpty ? Bias.right : Bias.left;
    return AnchorSelection(
      id: selection.id,
      start: buffer.anchorAfter(selection.start),
      end: buffer.anchorAt(selection.end, endBias),
      reversed: selection.reversed,
      goal: selection.goal,
    );
  }

  final int id;
  final Anchor start;
  final Anchor end;
  final bool reversed;
  final SelectionGoal goal;

  /// where it is in [buffer]; what was all replaced is left a cursor
  Selection resolve(BufferSnapshot buffer) {
    final from = buffer.offsetForAnchor(start);
    final to = buffer.offsetForAnchor(end);
    final isCursor = to <= from;
    return Selection(
      id: id,
      start: from,
      end: isCursor ? from : to,
      reversed: reversed && !isCursor,
      goal: goal,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AnchorSelection &&
      other.id == id &&
      other.start == start &&
      other.end == end &&
      other.reversed == reversed &&
      other.goal == goal;

  @override
  int get hashCode => Object.hash(id, start, end, reversed, goal);

  @override
  String toString() => 'AnchorSelection#$id($start..$end)';
}
