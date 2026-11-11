import 'dart:math' as math;

import 'display/layer_edit.dart';

class _Mutable {
  _Mutable(LayerEdit edit)
    : oldStart = edit.oldStart,
      oldEnd = edit.oldEnd,
      newStart = edit.newStart,
      newEnd = edit.newEnd;

  int oldStart;
  int oldEnd;
  int newStart;
  int newEnd;

  int get oldLen => oldEnd - oldStart;
  int get newLen => newEnd - newStart;
}

/// the edits that take one text to another, in order and apart from each
/// other. the old side of each is in the text before all of them, and the new
/// side in the text after all of them.
class EditPatch {
  EditPatch([List<LayerEdit>? edits]) : _edits = edits ?? [];

  final List<LayerEdit> _edits;

  List<LayerEdit> get edits => _edits;

  bool get isEmpty => _edits.isEmpty;

  /// the patch that takes the new text back to the old
  EditPatch invert() => EditPatch([
    for (final edit in _edits)
      LayerEdit(edit.newStart, edit.newEnd, edit.oldStart, edit.oldEnd),
  ]);

  /// adds [edit], which is not before the last; one that changes nothing is
  /// left out, and one that touches the last is made one with it
  void push(LayerEdit edit) {
    if (edit.oldStart == edit.oldEnd && edit.newStart == edit.newEnd) {
      return;
    }
    pushMaybeEmpty(edit);
  }

  void pushMaybeEmpty(LayerEdit edit) {
    if (_edits.isNotEmpty && _edits.last.oldEnd >= edit.oldStart) {
      final last = _edits.last;
      _edits[_edits.length - 1] = LayerEdit(
        last.oldStart,
        edit.oldEnd,
        last.newStart,
        edit.newEnd,
      );
    } else {
      _edits.add(edit);
    }
  }

  /// this patch and then [newEdits], whose old side is the new side of this
  /// one, as one patch from the old text of this to the new text of those
  EditPatch compose(Iterable<LayerEdit> newEdits) {
    final olds = [for (final edit in _edits) _Mutable(edit)];
    final news = [for (final edit in newEdits) _Mutable(edit)];
    var oldIx = 0;
    var newIx = 0;
    final composed = EditPatch();
    var oldStart = 0;
    var newStart = 0;

    void emit(int oldLen, int newLen) {
      final oldEnd = oldStart + oldLen;
      final newEnd = newStart + newLen;
      composed.push(LayerEdit(oldStart, oldEnd, newStart, newEnd));
      oldStart = oldEnd;
      newStart = newEnd;
    }

    while (true) {
      final oldEdit = oldIx < olds.length ? olds[oldIx] : null;
      final newEdit = newIx < news.length ? news[newIx] : null;

      // the old edit comes first when it ends before the new one starts
      if (oldEdit != null &&
          (newEdit == null || oldEdit.newEnd < newEdit.oldStart)) {
        final catchup = oldEdit.oldStart - oldStart;
        oldStart += catchup;
        newStart += catchup;
        emit(oldEdit.oldLen, oldEdit.newLen);
        oldIx++;
        continue;
      }

      // the new edit comes first when it ends before the old one starts
      if (newEdit != null &&
          (oldEdit == null || newEdit.oldEnd < oldEdit.newStart)) {
        final catchup = newEdit.newStart - newStart;
        oldStart += catchup;
        newStart += catchup;
        emit(newEdit.oldLen, newEdit.newLen);
        newIx++;
        continue;
      }

      if (oldEdit == null || newEdit == null) {
        break;
      }

      // the two overlap, and are put together
      if (oldEdit.newStart < newEdit.oldStart) {
        final catchup = oldEdit.oldStart - oldStart;
        oldStart += catchup;
        newStart += catchup;

        final overshoot = newEdit.oldStart - oldEdit.newStart;
        final oldEnd = math.min(oldStart + overshoot, oldEdit.oldEnd);
        final newEnd = newStart + overshoot;
        composed.push(LayerEdit(oldStart, oldEnd, newStart, newEnd));

        oldEdit.oldStart = oldEnd;
        oldEdit.newStart += overshoot;
        oldStart = oldEnd;
        newStart = newEnd;
      } else {
        final catchup = newEdit.newStart - newStart;
        oldStart += catchup;
        newStart += catchup;

        final overshoot = oldEdit.newStart - newEdit.oldStart;
        final oldEnd = oldStart + overshoot;
        final newEnd = math.min(newStart + overshoot, newEdit.newEnd);
        composed.push(LayerEdit(oldStart, oldEnd, newStart, newEnd));

        newEdit.oldStart += overshoot;
        newEdit.newStart = newEnd;
        oldStart = oldEnd;
        newStart = newEnd;
      }

      if (oldEdit.newEnd > newEdit.oldEnd) {
        emit(math.min(oldEdit.oldLen, newEdit.oldLen), newEdit.newLen);
        oldEdit.oldStart = oldStart;
        oldEdit.newStart = newEdit.oldEnd;
        newIx++;
      } else {
        emit(oldEdit.oldLen, math.min(oldEdit.newLen, newEdit.newLen));
        newEdit.oldStart = oldEdit.newEnd;
        newEdit.newStart = newStart;
        oldIx++;
      }
    }

    return composed;
  }

  /// where the old place [old] is in the new text; a place inside an edit
  /// goes to where the edit starts
  int oldToNew(int old) {
    final edit = _editAtOrBefore(old);
    if (edit == null) {
      return old;
    }
    return old >= edit.oldEnd
        ? edit.newEnd + (old - edit.oldEnd)
        : edit.newStart;
  }

  /// the edit that has the old place [old] in it or at its ends; when there
  /// is none, an edit of nothing at where that place is
  LayerEdit editForOldPosition(int old) {
    final edit = _editAtOrBefore(old);
    if (edit == null) {
      return LayerEdit(old, old, old, old);
    }
    if (old > edit.oldEnd) {
      final translated = edit.newEnd + (old - edit.oldEnd);
      return LayerEdit(old, old, translated, translated);
    }
    return edit;
  }

  /// the last edit that does not start after [old]
  LayerEdit? _editAtOrBefore(int old) {
    var low = 0;
    var high = _edits.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_edits[mid].oldStart <= old) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low == 0 ? null : _edits[low - 1];
  }

  @override
  bool operator ==(Object other) {
    if (other is! EditPatch || other._edits.length != _edits.length) {
      return false;
    }
    for (var i = 0; i < _edits.length; i++) {
      if (_edits[i] != other._edits[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_edits);

  @override
  String toString() => 'EditPatch($_edits)';
}

/// the patch of a buffer since it was last asked for: every edit that the
/// buffer makes is put together with the ones that are waiting
class Subscription {
  EditPatch _patch = EditPatch();

  /// the edits since the last time, which are then forgotten
  EditPatch consume() {
    final patch = _patch;
    _patch = EditPatch();
    return patch;
  }

  void publish(Iterable<LayerEdit> edits) => _patch = _patch.compose(edits);
}
