import '../patch.dart';
import '../point.dart';

/// a range of one layer of the display that changed: what was from
/// [oldStart] to [oldEnd] is now from [newStart] to [newEnd]. each layer takes
/// the edits of the one below it, and gives the edits it made of them.
class LayerEdit {
  const LayerEdit(this.oldStart, this.oldEnd, this.newStart, this.newEnd);

  final int oldStart;
  final int oldEnd;
  final int newStart;
  final int newEnd;

  @override
  bool operator ==(Object other) =>
      other is LayerEdit &&
      other.oldStart == oldStart &&
      other.oldEnd == oldEnd &&
      other.newStart == newStart &&
      other.newEnd == newEnd;

  @override
  int get hashCode => Object.hash(oldStart, oldEnd, newStart, newEnd);

  @override
  String toString() => 'LayerEdit($oldStart..$oldEnd -> $newStart..$newEnd)';
}

/// a range of a layer that changed, in rows and columns: the layers from the
/// tabs up say what changed this way, since it is rows that are laid out
class PointEdit {
  const PointEdit(this.oldStart, this.oldEnd, this.newStart, this.newEnd);

  final Point oldStart;
  final Point oldEnd;
  final Point newStart;
  final Point newEnd;

  @override
  bool operator ==(Object other) =>
      other is PointEdit &&
      other.oldStart == oldStart &&
      other.oldEnd == oldEnd &&
      other.newStart == newStart &&
      other.newEnd == newEnd;

  @override
  int get hashCode => Object.hash(oldStart, oldEnd, newStart, newEnd);

  @override
  String toString() => 'PointEdit($oldStart..$oldEnd -> $newStart..$newEnd)';
}

/// the edits of [patch], with where each range is after them
List<LayerEdit> layerEditsFromPatch(Patch patch) {
  final edits = <LayerEdit>[];
  var delta = 0;
  for (final edit in patch.edits) {
    final newStart = edit.start + delta;
    edits.add(
      LayerEdit(edit.start, edit.oldEnd, newStart, newStart + edit.newLength),
    );
    delta += edit.newLength - edit.oldLength;
  }
  return edits;
}

/// where [offset] is after [edits]. what is put in comes before what was
/// taken out, so in a range that was replaced only a place at its start that
/// stays with the text before it, which is [Bias.left], is before what was
/// put in; every other place in it is after.
int mapOffsetThroughEdits(int offset, Bias bias, List<LayerEdit> edits) {
  var delta = 0;
  for (final edit in edits) {
    if (offset < edit.oldStart) {
      break;
    }
    if (offset > edit.oldEnd) {
      delta = edit.newEnd - edit.oldEnd;
      continue;
    }
    return offset == edit.oldStart && bias == Bias.left
        ? edit.newStart
        : edit.newEnd;
  }
  return offset + delta;
}

/// [edits] in order, with the ones that touch made one
List<LayerEdit> consolidateEdits(List<LayerEdit> edits) {
  final sorted = List.of(edits)
    ..sort((a, b) {
      final byStart = a.oldStart.compareTo(b.oldStart);
      return byStart != 0 ? byStart : b.oldEnd.compareTo(a.oldEnd);
    });
  final out = <LayerEdit>[];
  for (final edit in sorted) {
    if (out.isNotEmpty && out.last.oldEnd >= edit.oldStart) {
      final last = out.last;
      out[out.length - 1] = LayerEdit(
        last.oldStart,
        last.oldEnd > edit.oldEnd ? last.oldEnd : edit.oldEnd,
        last.newStart < edit.newStart ? last.newStart : edit.newStart,
        last.newEnd > edit.newEnd ? last.newEnd : edit.newEnd,
      );
    } else {
      out.add(edit);
    }
  }
  return out;
}

/// adds [edit], which is not before the last of [edits], and makes one of the
/// two when they touch
void pushLayerEdit(List<LayerEdit> edits, LayerEdit edit) {
  if (edit.oldStart == edit.oldEnd && edit.newStart == edit.newEnd) {
    return;
  }
  if (edits.isNotEmpty && edits.last.oldEnd >= edit.oldStart) {
    final last = edits.last;
    edits[edits.length - 1] = LayerEdit(
      last.oldStart,
      edit.oldEnd,
      last.newStart,
      edit.newEnd,
    );
  } else {
    edits.add(edit);
  }
}
