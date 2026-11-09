/// which side of an edit at its place a position stays on
enum Bias {
  /// before what is put there
  left,

  /// after what is put there
  right,
}

/// one replaced range of a text: the old text from [start] for [oldLength]
/// code units became [newLength] code units, starting at [start] still
class Edit {
  const Edit(this.start, this.oldLength, this.newLength);

  final int start;
  final int oldLength;
  final int newLength;

  int get oldEnd => start + oldLength;

  @override
  bool operator ==(Object other) =>
      other is Edit &&
      other.start == start &&
      other.oldLength == oldLength &&
      other.newLength == newLength;

  @override
  int get hashCode => Object.hash(start, oldLength, newLength);

  @override
  String toString() => 'Edit($start, -$oldLength, +$newLength)';
}

/// what a batch of edits did to a text, in the offsets of the text before.
/// anything that holds offsets, such as selections and folds, follows the
/// text through a patch, since a position that is not an offset into the
/// current text stays right only this way.
class Patch {
  /// [edits] are ordered, and none overlaps another
  const Patch(this.edits);

  static const empty = Patch([]);

  final List<Edit> edits;

  bool get isEmpty => edits.isEmpty;

  /// where [offset] is after the edits. a position inside a range that was
  /// replaced, or at the edge of one, goes to the start of what replaced it
  /// with [Bias.left], and to its end with [Bias.right]; so does one where text
  /// is put in without anything taken out
  int mapOffset(int offset, Bias bias) {
    var delta = 0;
    for (final edit in edits) {
      if (offset < edit.start) {
        break;
      }
      if (offset > edit.oldEnd) {
        delta += edit.newLength - edit.oldLength;
        continue;
      }
      final start = edit.start + delta;
      return bias == Bias.left ? start : start + edit.newLength;
    }
    return offset + delta;
  }

  /// how much longer the text is
  int get delta {
    var total = 0;
    for (final edit in edits) {
      total += edit.newLength - edit.oldLength;
    }
    return total;
  }

  @override
  bool operator ==(Object other) {
    if (other is! Patch || other.edits.length != edits.length) {
      return false;
    }
    for (var i = 0; i < edits.length; i++) {
      if (edits[i] != other.edits[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(edits);

  @override
  String toString() => 'Patch($edits)';
}
