import 'dart:math' as math;

import 'ordered_tree.dart';

class _UndoEntry {
  const _UndoEntry(this.editId, this.undoId, this.count);

  final int editId;
  final int undoId;
  final int count;

  static int compare(_UndoEntry a, _UndoEntry b) {
    final byEdit = a.editId.compareTo(b.editId);
    return byEdit != 0 ? byEdit : a.undoId.compareTo(b.undoId);
  }
}

/// how many times each edit has been undone, and at which undo it came to
/// that many. an edit that was undone an odd number of times is undone, and
/// one undone an even number of times was done again.
class UndoMap {
  UndoMap() : _entries = OrderedTree(_UndoEntry.compare);

  UndoMap._(this._entries);

  final OrderedTree<_UndoEntry> _entries;

  /// this map with the undo at the time [undoId], which sets the number of
  /// times each edit of [counts] has been undone
  UndoMap insert(int undoId, Map<int, int> counts) => UndoMap._(
    _entries.insertAll([
      for (final MapEntry(:key, :value) in counts.entries)
        _UndoEntry(key, undoId, value),
    ]),
  );

  bool isUndone(int editId) => undoCount(editId).isOdd;

  /// whether the edit was undone at the time [version]
  bool wasUndone(int editId, int version) {
    var count = 0;
    for (final entry in _entries.from(_UndoEntry(editId, 0, 0))) {
      if (entry.editId != editId) {
        break;
      }
      if (entry.undoId <= version) {
        count = math.max(count, entry.count);
      }
    }
    return count.isOdd;
  }

  int undoCount(int editId) {
    var count = 0;
    for (final entry in _entries.from(_UndoEntry(editId, 0, 0))) {
      if (entry.editId != editId) {
        break;
      }
      count = math.max(count, entry.count);
    }
    return count;
  }
}
