import 'dart:math' as math;

import 'anchor.dart';
import 'display/layer_edit.dart';
import 'edit_patch.dart';
import 'locator.dart';
import 'ordered_tree.dart';
import 'patch.dart';
import 'point.dart';
import 'rope.dart';
import 'selection.dart';
import 'sum_tree.dart';
import 'undo_map.dart';

export 'anchor.dart';
export 'edit_patch.dart' show EditPatch, Subscription;

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

/// a run of text that one insertion put in, or a part of one that later edits
/// split off. the text of a buffer is its fragments in order; one that was
/// deleted stays, hidden, so that what is anchored in it can still be found
/// and so that undoing the deletion shows it again.
class _Fragment {
  const _Fragment({
    required this.id,
    required this.timestamp,
    required this.insertionOffset,
    required this.len,
    required this.visible,
    this.deletions = const [],
    this.maxUndos = 0,
  });

  /// where the fragment is among the others
  final Locator id;

  /// the time of the insertion that the text is of
  final int timestamp;

  /// how far into the text of that insertion the fragment starts
  final int insertionOffset;
  final int len;
  final bool visible;

  /// the times of the edits that deleted the fragment
  final List<int> deletions;

  /// the time of the last undo that changed whether the fragment is shown
  final int maxUndos;

  _Fragment copyWith({
    Locator? id,
    int? insertionOffset,
    int? len,
    bool? visible,
    List<int>? deletions,
    int? maxUndos,
  }) => _Fragment(
    id: id ?? this.id,
    timestamp: timestamp,
    insertionOffset: insertionOffset ?? this.insertionOffset,
    len: len ?? this.len,
    visible: visible ?? this.visible,
    deletions: deletions ?? this.deletions,
    maxUndos: maxUndos ?? this.maxUndos,
  );

  bool isVisible(UndoMap undos) =>
      !undos.isUndone(timestamp) && deletions.every(undos.isUndone);

  /// whether the fragment was shown at the time [version]
  bool wasVisible(int version, UndoMap undos) =>
      timestamp <= version &&
      !undos.wasUndone(timestamp, version) &&
      deletions.every((d) => d > version || undos.wasUndone(d, version));
}

class _FragmentSummary {
  const _FragmentSummary(
    this.visible,
    this.deleted,
    this.maxId,
    this.maxVersion,
  );

  static const zero = _FragmentSummary(0, 0, Locator.min, 0);

  /// the length of the fragments that are shown
  final int visible;

  /// the length of the ones that are hidden
  final int deleted;
  final Locator maxId;

  /// the last time anything happened to any of the fragments
  final int maxVersion;
}

class _FragmentOps extends SummaryOps<_Fragment, _FragmentSummary> {
  const _FragmentOps();

  @override
  _FragmentSummary get zero => _FragmentSummary.zero;

  @override
  _FragmentSummary add(_FragmentSummary a, _FragmentSummary b) =>
      _FragmentSummary(
        a.visible + b.visible,
        a.deleted + b.deleted,
        b.maxId,
        math.max(a.maxVersion, b.maxVersion),
      );

  @override
  _FragmentSummary summarize(_Fragment item) {
    var maxVersion = math.max(item.timestamp, item.maxUndos);
    for (final deletion in item.deletions) {
      maxVersion = math.max(maxVersion, deletion);
    }
    return _FragmentSummary(
      item.visible ? item.len : 0,
      item.visible ? 0 : item.len,
      item.id,
      maxVersion,
    );
  }
}

const _fragmentOps = _FragmentOps();
const _dim = SummaryDimension<_Fragment, _FragmentSummary>(_fragmentOps);

/// which fragment has the text of an insertion from [splitOffset] on, until
/// the next split of the same insertion
class _InsertionFragment {
  const _InsertionFragment(this.timestamp, this.splitOffset, this.fragmentId);

  _InsertionFragment.of(_Fragment fragment)
    : this(fragment.timestamp, fragment.insertionOffset, fragment.id);

  final int timestamp;
  final int splitOffset;
  final Locator fragmentId;

  static int compare(_InsertionFragment a, _InsertionFragment b) {
    final byTime = a.timestamp.compareTo(b.timestamp);
    return byTime != 0 ? byTime : a.splitOffset.compareTo(b.splitOffset);
  }
}

/// a part of an insertion that the edit [editId] put in or took out
class _InsertionSlice {
  const _InsertionSlice(this.editId, this.insertionId, this.start, this.end);

  _InsertionSlice.of(int editId, _Fragment fragment)
    : this(
        editId,
        fragment.timestamp,
        fragment.insertionOffset,
        fragment.insertionOffset + fragment.len,
      );

  final int editId;
  final int insertionId;
  final int start;
  final int end;

  static int compare(_InsertionSlice a, _InsertionSlice b) {
    var c = a.editId.compareTo(b.editId);
    if (c != 0) {
      return c;
    }
    c = a.insertionId.compareTo(b.insertionId);
    if (c != 0) {
      return c;
    }
    c = a.start.compareTo(b.start);
    return c != 0 ? c : a.end.compareTo(b.end);
  }
}

/// makes the two ropes of a buffer, the text that is shown and the text that
/// is hidden, out of the old ones as the fragments are gone over in order
class _RopeBuilder {
  _RopeBuilder(this._oldVisible, this._oldDeleted);

  final Rope _oldVisible;
  final Rope _oldDeleted;
  int _visibleOffset = 0;
  int _deletedOffset = 0;
  Rope _newVisible = Rope.empty;
  Rope _newDeleted = Rope.empty;

  void append(_FragmentSummary summary) {
    _push(summary.visible, true, true);
    _push(summary.deleted, false, false);
  }

  void pushFragment(_Fragment fragment, bool wasVisible) =>
      _push(fragment.len, wasVisible, fragment.visible);

  void _push(int len, bool wasVisible, bool isVisible) {
    if (len == 0) {
      return;
    }
    final Rope text;
    if (wasVisible) {
      text = _oldVisible.slice(_visibleOffset, _visibleOffset + len);
      _visibleOffset += len;
    } else {
      text = _oldDeleted.slice(_deletedOffset, _deletedOffset + len);
      _deletedOffset += len;
    }
    if (isVisible) {
      _newVisible += text;
    } else {
      _newDeleted += text;
    }
  }

  void pushString(String text) => _newVisible += Rope(text);

  (Rope visible, Rope deleted) finish() => (
    _newVisible + _oldVisible.slice(_visibleOffset, _oldVisible.length),
    _newDeleted + _oldDeleted.slice(_deletedOffset, _oldDeleted.length),
  );
}

/// the text of a buffer at one time, with what is needed to say where an
/// anchor is in it. it does not change, so it can be kept while the buffer is
/// edited.
class BufferSnapshot {
  BufferSnapshot._({
    required this.text,
    required this._deletedText,
    required this._fragments,
    required this._insertions,
    required this._insertionSlices,
    required this._undoMap,
    required this.version,
    required this.lineEnding,
  });

  /// the text that is shown
  final Rope text;
  final Rope _deletedText;
  final SumTree<_Fragment, _FragmentSummary> _fragments;
  final OrderedTree<_InsertionFragment> _insertions;
  final OrderedTree<_InsertionSlice> _insertionSlices;
  final UndoMap _undoMap;

  /// the time of the last edit or undo that the snapshot has
  final int version;
  final LineEnding lineEnding;

  int get length => text.length;
  bool get isEmpty => text.isEmpty;
  int get lineCount => text.lineCount;
  Point get maxPoint => text.maxPoint;

  Point offsetToPoint(int offset) => text.offsetToPoint(offset);
  int pointToOffset(Point point) => text.pointToOffset(point);
  int clipOffset(int offset, Bias bias) => text.clipOffset(offset, bias);
  Point clipPoint(Point point, Bias bias) => text.clipPoint(point, bias);

  BufferSnapshot _with({
    Rope? text,
    Rope? deletedText,
    SumTree<_Fragment, _FragmentSummary>? fragments,
    OrderedTree<_InsertionFragment>? insertions,
    OrderedTree<_InsertionSlice>? insertionSlices,
    UndoMap? undoMap,
    int? version,
    LineEnding? lineEnding,
  }) => BufferSnapshot._(
    text: text ?? this.text,
    deletedText: deletedText ?? _deletedText,
    fragments: fragments ?? _fragments,
    insertions: insertions ?? _insertions,
    insertionSlices: insertionSlices ?? _insertionSlices,
    undoMap: undoMap ?? _undoMap,
    version: version ?? this.version,
    lineEnding: lineEnding ?? this.lineEnding,
  );

  // anchors

  /// an anchor at [offset] that stays with the text before it
  Anchor anchorBefore(int offset) => anchorAt(offset, Bias.left);

  /// an anchor at [offset] that stays with the text after it
  Anchor anchorAfter(int offset) => anchorAt(offset, Bias.right);

  Anchor anchorAt(int offset, Bias bias) {
    if (bias == Bias.left && offset == 0) {
      return Anchor.min;
    }
    if (bias == Bias.right && offset >= length) {
      return Anchor.max;
    }
    final at = text.clipOffset(offset, bias);
    final (start, _, fragment) = _fragments.find(
      _dim,
      (p) => at.compareTo(p.visible),
      bias,
    );
    if (fragment == null) {
      return Anchor.max;
    }
    return Anchor(
      fragment.timestamp,
      fragment.insertionOffset + (at - start.visible),
      bias,
    );
  }

  /// anchors of [start] to [end] that stay around what is put in at the ends
  AnchorRange anchorRangeOutside(int start, int end) =>
      AnchorRange(anchorBefore(start), anchorAfter(end));

  /// anchors of [start] to [end] that leave out what is put in at the ends
  AnchorRange anchorRangeInside(int start, int end) =>
      AnchorRange(anchorAfter(start), anchorBefore(end));

  /// whether the snapshot is late enough to say where [anchor] is
  bool canResolve(Anchor anchor) =>
      anchor.isMin || anchor.isMax || anchor.timestamp <= version;

  _InsertionFragment? _tryFindFragment(Anchor anchor) {
    final key = _InsertionFragment(
      anchor.timestamp,
      anchor.offset,
      Locator.min,
    );
    final (previous, insertion) = _insertions.findWithPrevious(
      key,
      anchor.bias,
    );
    if (insertion == null) {
      return _insertions.last;
    }
    final comparison = _InsertionFragment.compare(insertion, key);
    if (comparison > 0 ||
        (anchor.bias == Bias.left && comparison == 0 && anchor.offset > 0)) {
      return previous;
    }
    return insertion;
  }

  _InsertionFragment _findFragment(Anchor anchor) {
    final insertion = _tryFindFragment(anchor);
    if (insertion == null || insertion.timestamp != anchor.timestamp) {
      throw StateError('$anchor is not of this buffer at version $version');
    }
    return insertion;
  }

  Locator _fragmentIdForAnchor(Anchor anchor) {
    if (anchor.isMin) {
      return Locator.min;
    }
    if (anchor.isMax) {
      return Locator.max;
    }
    return _findFragment(anchor).fragmentId;
  }

  /// where [anchor] is in the text
  int offsetForAnchor(Anchor anchor) {
    if (anchor.isMin) {
      return 0;
    }
    if (anchor.isMax) {
      return length;
    }
    final insertion = _findFragment(anchor);
    final (start, _, fragment) = _fragments.find(
      _dim,
      (p) => insertion.fragmentId.compareTo(p.maxId),
      Bias.left,
    );
    var offset = start.visible;
    if (fragment!.visible) {
      offset += anchor.offset - insertion.splitOffset;
    }
    return offset;
  }

  Point pointForAnchor(Anchor anchor) => offsetToPoint(offsetForAnchor(anchor));

  /// where each of [anchors] is in the text
  List<int> offsetsForAnchors(Iterable<Anchor> anchors) => [
    for (final anchor in anchors) offsetForAnchor(anchor),
  ];

  /// whether [anchor] is in text that is shown
  bool isValid(Anchor anchor) {
    if (anchor.isMin || anchor.isMax) {
      return true;
    }
    final insertion = _tryFindFragment(anchor);
    if (insertion == null || insertion.timestamp != anchor.timestamp) {
      return false;
    }
    final (_, _, fragment) = _fragments.find(
      _dim,
      (p) => insertion.fragmentId.compareTo(p.maxId),
      Bias.left,
    );
    return fragment != null && fragment.visible;
  }

  /// which of two anchors comes first in the text
  int compareAnchors(Anchor a, Anchor b) {
    if (a.timestamp != b.timestamp) {
      final byFragment = _fragmentIdForAnchor(a)
          .compareTo(_fragmentIdForAnchor(b));
      if (byFragment != 0) {
        return byFragment;
      }
    }
    final byOffset = a.offset.compareTo(b.offset);
    return byOffset != 0 ? byOffset : a.bias.index.compareTo(b.bias.index);
  }

  /// [anchor] staying with the text on the side of [bias]
  Anchor biasAnchor(Anchor anchor, Bias bias) =>
      anchor.bias == bias ? anchor : anchorAt(offsetForAnchor(anchor), bias);

  // edits since a version

  bool hasEditsSince(int since) {
    if (since == version) {
      return false;
    }
    final cursor = _fragments.filter(_dim, (s) => s.maxVersion > since)..next();
    while (true) {
      final fragment = cursor.item;
      if (fragment == null) {
        return false;
      }
      if (fragment.wasVisible(since, _undoMap) != fragment.visible) {
        return true;
      }
      cursor.next();
    }
  }

  /// what changed in the text since the time [since], as edits from the text
  /// of that time to this one
  List<LayerEdit> editsSince(int since) => [
    for (final (edit, _) in anchoredEditsSince(since)) edit,
  ];

  /// [editsSince], each edit with anchors around what it changed
  List<(LayerEdit, AnchorRange)> anchoredEditsSince(
    int since, [
    AnchorRange range = const AnchorRange(Anchor.min, Anchor.max),
  ]) {
    final out = <(LayerEdit, AnchorRange)>[];
    if (since == version) {
      return out;
    }
    final cursor = _fragments.filter(_dim, (s) => s.maxVersion > since)..next();
    final startId = _fragmentIdForAnchor(range.start);
    final endId = _fragmentIdForAnchor(range.end);
    final (start, _, startFragment) = _fragments.find(
      _dim,
      (p) => startId.compareTo(p.maxId),
      Bias.left,
    );
    var visibleOffset = start.visible;
    var deletedOffset = start.deleted;
    if (startFragment != null) {
      final overshoot = range.start.offset - startFragment.insertionOffset;
      if (startFragment.visible) {
        visibleOffset += overshoot;
      } else {
        deletedOffset += overshoot;
      }
    }

    var oldEnd = 0;
    var newEnd = 0;
    int? pendingOldStart;
    var pendingOldEnd = 0;
    var pendingNewStart = 0;
    var pendingNewEnd = 0;
    var pendingStart = Anchor.min;
    var pendingEnd = Anchor.min;

    void flush() {
      final oldStart = pendingOldStart;
      if (oldStart != null) {
        out.add((
          LayerEdit(oldStart, pendingOldEnd, pendingNewStart, pendingNewEnd),
          AnchorRange(pendingStart, pendingEnd),
        ));
        pendingOldStart = null;
      }
    }

    while (true) {
      final fragment = cursor.item;
      if (fragment == null) {
        break;
      }
      if (fragment.id < startId) {
        cursor.next();
        continue;
      }
      if (fragment.id > endId) {
        break;
      }

      if (cursor.start.visible > visibleOffset) {
        final skipped = cursor.start.visible - visibleOffset;
        visibleOffset = cursor.start.visible;
        oldEnd += skipped;
        newEnd += skipped;
      }

      if (pendingOldStart != null && pendingNewEnd < newEnd) {
        flush();
      }

      final startAnchor = Anchor(
        fragment.timestamp,
        fragment.insertionOffset,
        Bias.right,
      );
      final endAnchor = Anchor(
        fragment.timestamp,
        fragment.insertionOffset + fragment.len,
        Bias.left,
      );
      final wasVisible = fragment.wasVisible(since, _undoMap);

      if (!wasVisible && fragment.visible) {
        var visibleEnd = cursor.end.visible;
        if (fragment.id == endId) {
          visibleEnd = math.min(
            visibleEnd,
            cursor.start.visible +
                (range.end.offset - fragment.insertionOffset),
          );
        }
        final end = newEnd + (visibleEnd - visibleOffset);
        visibleOffset = visibleEnd;
        if (pendingOldStart != null) {
          pendingNewEnd = end;
          pendingEnd = endAnchor;
        } else {
          pendingOldStart = oldEnd;
          pendingOldEnd = oldEnd;
          pendingNewStart = newEnd;
          pendingNewEnd = end;
          pendingStart = startAnchor;
          pendingEnd = endAnchor;
        }
        newEnd = end;
      } else if (wasVisible && !fragment.visible) {
        var deletedEnd = cursor.end.deleted;
        if (fragment.id == endId) {
          deletedEnd = math.min(
            deletedEnd,
            cursor.start.deleted +
                (range.end.offset - fragment.insertionOffset),
          );
        }
        if (cursor.start.deleted > deletedOffset) {
          deletedOffset = cursor.start.deleted;
        }
        final end = oldEnd + (deletedEnd - deletedOffset);
        deletedOffset = deletedEnd;
        if (pendingOldStart != null) {
          pendingOldEnd = end;
          pendingEnd = endAnchor;
        } else {
          pendingOldStart = oldEnd;
          pendingOldEnd = end;
          pendingNewStart = newEnd;
          pendingNewEnd = newEnd;
          pendingStart = startAnchor;
          pendingEnd = endAnchor;
        }
        oldEnd = end;
      }

      cursor.next();
    }
    flush();
    return out;
  }

  /// the text as it was at the time [version]
  Rope textForVersion(int version) {
    var rope = Rope.empty;
    final cursor = _fragments.filter(_dim, (s) => s.maxVersion > version)
      ..next();
    var visibleOffset = 0;
    while (true) {
      final fragment = cursor.item;
      if (fragment == null) {
        break;
      }
      if (cursor.start.visible > visibleOffset) {
        rope += text.slice(visibleOffset, cursor.start.visible);
        visibleOffset = cursor.start.visible;
      }
      if (fragment.wasVisible(version, _undoMap)) {
        if (fragment.visible) {
          rope += text.slice(visibleOffset, cursor.end.visible);
          visibleOffset = cursor.end.visible;
        } else {
          rope += _deletedText.slice(cursor.start.deleted, cursor.end.deleted);
        }
      } else if (fragment.visible) {
        visibleOffset = cursor.end.visible;
      }
      cursor.next();
    }
    if (length > visibleOffset) {
      rope += text.slice(visibleOffset, length);
    }
    return rope;
  }

  // changes, each of which makes a new snapshot

  /// the snapshot after [edits], which are in order and apart, were made at
  /// the time [timestamp]; and what they did to the text
  (BufferSnapshot, List<LayerEdit>) _applyEdit(
    List<Replacement> edits,
    int timestamp,
  ) {
    final patch = EditPatch();
    final newInsertions = <_InsertionFragment>[];
    final insertionSlices = <_InsertionSlice>[];
    var insertionOffset = 0;

    final ropes = _RopeBuilder(text, _deletedText);
    final old = _fragments.cursor(_dim);
    var fragments = old.slice(
      (p) => edits.first.start.compareTo(p.visible),
      Bias.right,
    );
    ropes.append(fragments.summary);

    /// what is left of the fragment the cursor is at, from [fragmentStart]
    _Fragment rest(_Fragment fragment, int fragmentStart, int end) =>
        fragment.copyWith(
          len: end - fragmentStart,
          insertionOffset:
              fragment.insertionOffset + (fragmentStart - old.start.visible),
        );

    var fragmentStart = old.start.visible;
    for (final edit in edits) {
      final fragmentEnd = old.end.visible;

      // when the fragment the cursor is at ends before the edit, the
      // fragments up to the one the edit starts in are kept as they are
      if (fragmentEnd < edit.start) {
        // one that an earlier edit used part of is finished first
        if (fragmentStart > old.start.visible) {
          if (fragmentEnd > fragmentStart) {
            final suffix = rest(old.item!, fragmentStart, fragmentEnd);
            newInsertions.add(_InsertionFragment.of(suffix));
            ropes.pushFragment(suffix, suffix.visible);
            fragments = fragments.push(suffix);
          }
          old.next();
        }
        final slice = old.slice(
          (p) => edit.start.compareTo(p.visible),
          Bias.right,
        );
        ropes.append(slice.summary);
        fragments = fragments.append(slice);
        fragmentStart = old.start.visible;
      }

      // the part of the fragment that is before the edit is kept
      if (fragmentStart < edit.start) {
        final item = old.item!;
        final prefix = rest(
          item,
          fragmentStart,
          edit.start,
        ).copyWith(id: Locator.between(fragments.summary.maxId, item.id));
        newInsertions.add(_InsertionFragment.of(prefix));
        ropes.pushFragment(prefix, prefix.visible);
        fragments = fragments.push(prefix);
        fragmentStart = edit.start;
      }

      // the new text goes in before what the edit takes out
      if (edit.text.isNotEmpty) {
        final newStart = fragments.summary.visible;
        final fragment = _Fragment(
          id: Locator.between(
            fragments.summary.maxId,
            old.item?.id ?? Locator.max,
          ),
          timestamp: timestamp,
          insertionOffset: insertionOffset,
          len: edit.text.length,
          visible: true,
        );
        insertionSlices.add(_InsertionSlice.of(timestamp, fragment));
        newInsertions.add(_InsertionFragment.of(fragment));
        fragments = fragments.push(fragment);
        insertionOffset += edit.text.length;
        ropes.pushString(edit.text);
        patch.push(
          LayerEdit(
            fragmentStart,
            fragmentStart,
            newStart,
            newStart + edit.text.length,
          ),
        );
      }

      // every fragment the edit goes over is hidden, in the part it is in
      while (fragmentStart < edit.end) {
        final fragment = old.item!;
        final fragmentEnd = old.end.visible;
        final intersectionEnd = math.min(edit.end, fragmentEnd);
        var intersection = fragment;
        if (fragment.visible) {
          intersection = rest(fragment, fragmentStart, intersectionEnd)
              .copyWith(
                id: Locator.between(fragments.summary.maxId, fragment.id),
                deletions: [...fragment.deletions, timestamp],
                visible: false,
              );
        }
        if (intersection.len > 0) {
          if (fragment.visible && !intersection.visible) {
            final newStart = fragments.summary.visible;
            patch.push(
              LayerEdit(fragmentStart, intersectionEnd, newStart, newStart),
            );
            insertionSlices.add(_InsertionSlice.of(timestamp, intersection));
          }
          newInsertions.add(_InsertionFragment.of(intersection));
          ropes.pushFragment(intersection, fragment.visible);
          fragments = fragments.push(intersection);
          fragmentStart = intersectionEnd;
        }
        if (fragmentEnd <= edit.end) {
          old.next();
        }
      }
    }

    // the fragment the last edit ended in is finished
    if (fragmentStart > old.start.visible) {
      final fragmentEnd = old.end.visible;
      if (fragmentEnd > fragmentStart) {
        final suffix = rest(old.item!, fragmentStart, fragmentEnd);
        newInsertions.add(_InsertionFragment.of(suffix));
        ropes.pushFragment(suffix, suffix.visible);
        fragments = fragments.push(suffix);
      }
      old.next();
    }

    final suffix = old.suffix();
    ropes.append(suffix.summary);
    fragments = fragments.append(suffix);
    final (visible, deleted) = ropes.finish();

    return (
      _with(
        text: visible,
        deletedText: deleted,
        fragments: fragments,
        insertions: _insertions.insertAll(newInsertions),
        insertionSlices: _insertionSlices.insertAll(insertionSlices),
        version: math.max(version, timestamp),
      ),
      patch.edits,
    );
  }

  /// the fragments that the edits with the ids of [editIds] put in or hid
  List<Locator> _fragmentIdsForEdits(Iterable<int> editIds) {
    final slices = <_InsertionSlice>[];
    for (final editId in editIds) {
      slices.addAll(
        _insertionSlices
            .from(_InsertionSlice(editId, 0, 0, 0))
            .takeWhile((slice) => slice.editId == editId),
      );
    }
    slices.sort((a, b) {
      var c = a.insertionId.compareTo(b.insertionId);
      if (c != 0) {
        return c;
      }
      c = a.start.compareTo(b.start);
      return c != 0 ? c : b.end.compareTo(a.end);
    });

    final ids = <Locator>[];
    for (final slice in slices) {
      final parts = _insertions
          .from(_InsertionFragment(slice.insertionId, slice.start, Locator.min))
          .takeWhile(
            (item) =>
                item.timestamp == slice.insertionId &&
                item.splitOffset < slice.end,
          );
      for (final part in parts) {
        ids.add(part.fragmentId);
      }
    }
    ids.sort();
    return ids;
  }

  /// the snapshot after the undo at the time [timestamp], which sets how many
  /// times each of the edits of [counts] has been undone
  (BufferSnapshot, List<LayerEdit>) _applyUndo(
    int timestamp,
    Map<int, int> counts,
  ) {
    final undoMap = _undoMap.insert(timestamp, counts);
    final patch = EditPatch();
    final old = _fragments.cursor(_dim);
    var fragments = SumTree<_Fragment, _FragmentSummary>(_fragmentOps);
    final ropes = _RopeBuilder(text, _deletedText);

    Locator? previous;
    for (final id in _fragmentIdsForEdits(counts.keys)) {
      if (id == previous) {
        continue;
      }
      previous = id;
      final preceding = old.slice((p) => id.compareTo(p.maxId), Bias.left);
      ropes.append(preceding.summary);
      fragments = fragments.append(preceding);

      final item = old.item;
      if (item != null) {
        final wasVisible = item.visible;
        final fragment = item.copyWith(
          visible: item.isVisible(undoMap),
          maxUndos: math.max(item.maxUndos, timestamp),
        );
        final oldStart = old.start.visible;
        final newStart = fragments.summary.visible;
        if (wasVisible && !fragment.visible) {
          patch.push(
            LayerEdit(oldStart, oldStart + fragment.len, newStart, newStart),
          );
        } else if (!wasVisible && fragment.visible) {
          patch.push(
            LayerEdit(oldStart, oldStart, newStart, newStart + fragment.len),
          );
        }
        ropes.pushFragment(fragment, wasVisible);
        fragments = fragments.push(fragment);
        old.next();
      }
    }

    final suffix = old.suffix();
    ropes.append(suffix.summary);
    fragments = fragments.append(suffix);
    final (visible, deleted) = ropes.finish();
    return (
      _with(
        text: visible,
        deletedText: deleted,
        fragments: fragments,
        undoMap: undoMap,
        version: math.max(version, timestamp),
      ),
      patch.edits,
    );
  }

  /// throws when the parts of the snapshot do not agree with each other
  void checkInvariants() {
    var visible = 0;
    var deleted = 0;
    Locator? previous;
    for (final fragment in _fragments.items) {
      if (previous != null && fragment.id <= previous) {
        throw StateError('fragments are out of order');
      }
      previous = fragment.id;
      if (fragment.len == 0) {
        throw StateError('a fragment is empty');
      }
      if (fragment.visible != fragment.isVisible(_undoMap)) {
        throw StateError('a fragment is shown when it is not to be');
      }
      if (fragment.visible) {
        visible += fragment.len;
      } else {
        deleted += fragment.len;
      }
      final insertion = _insertions
          .from(
            _InsertionFragment(
              fragment.timestamp,
              fragment.insertionOffset,
              Locator.min,
            ),
          )
          .first;
      if (insertion.fragmentId != fragment.id) {
        throw StateError('an insertion does not name its fragment');
      }
    }
    if (visible != text.length || deleted != _deletedText.length) {
      throw StateError('the fragments are not as long as the text');
    }
  }
}

/// the edits that were made together, which one undo takes back
class Transaction {
  Transaction._(this.id, this.start, this.selectionsBefore);

  final int id;

  /// the version of the buffer before the first of the edits
  final int start;

  /// the times of the edits
  final List<int> editIds = [];

  /// the selections before the first edit, which undo goes back to
  final List<AnchorSelection>? selectionsBefore;

  /// the selections after the last edit, which redo goes back to
  List<AnchorSelection>? selectionsAfter;

  bool get isEmpty => editIds.isEmpty;
}

class _HistoryEntry {
  _HistoryEntry(this.transaction, this.firstEditAt) : lastEditAt = firstEditAt;

  final Transaction transaction;
  final DateTime firstEditAt;
  DateTime lastEditAt;
  bool suppressGrouping = false;
}

class _History {
  _History(this.groupInterval);

  final Duration groupInterval;
  final List<_HistoryEntry> undoStack = [];
  final List<_HistoryEntry> redoStack = [];
  int transactionDepth = 0;

  Transaction? startTransaction(
    int start,
    DateTime now,
    int Function() tick,
    List<AnchorSelection>? selections,
  ) {
    transactionDepth++;
    if (transactionDepth != 1) {
      return null;
    }
    final transaction = Transaction._(tick(), start, selections);
    undoStack.add(_HistoryEntry(transaction, now));
    return transaction;
  }

  _HistoryEntry? endTransaction(DateTime now) {
    assert(transactionDepth != 0, 'no transaction is open');
    transactionDepth--;
    if (transactionDepth != 0) {
      return null;
    }
    if (undoStack.last.transaction.isEmpty) {
      undoStack.removeLast();
      return null;
    }
    redoStack.clear();
    return undoStack.last..lastEditAt = now;
  }

  /// makes one entry of the last ones that were made close in time
  Transaction? group() {
    var count = 0;
    for (var i = undoStack.length - 1; i > 0; i--) {
      final entry = undoStack[i];
      final previous = undoStack[i - 1];
      if (!previous.suppressGrouping &&
          entry.firstEditAt.difference(previous.lastEditAt) < groupInterval) {
        count++;
      } else {
        break;
      }
    }
    return groupTrailing(count);
  }

  void groupUntil(int transactionId) {
    var count = 0;
    for (final entry in undoStack.reversed) {
      if (entry.transaction.id == transactionId) {
        groupTrailing(count);
        break;
      } else if (entry.suppressGrouping) {
        break;
      } else {
        count++;
      }
    }
  }

  Transaction? groupTrailing(int n) {
    final newLength = undoStack.length - n;
    if (newLength > 0 && n > 0) {
      final kept = undoStack[newLength - 1];
      for (var i = newLength; i < undoStack.length; i++) {
        kept.transaction.editIds.addAll(undoStack[i].transaction.editIds);
      }
      kept.lastEditAt = undoStack.last.lastEditAt;
      kept.transaction.selectionsAfter =
          undoStack.last.transaction.selectionsAfter;
    }
    undoStack.length = newLength;
    return undoStack.isEmpty ? null : undoStack.last.transaction;
  }

  Transaction? finalizeLastTransaction() {
    if (undoStack.isEmpty) {
      return null;
    }
    undoStack.last.suppressGrouping = true;
    return undoStack.last.transaction;
  }

  void pushUndo(int editId) {
    assert(transactionDepth != 0, 'no transaction is open');
    undoStack.last.transaction.editIds.add(editId);
  }

  _HistoryEntry? popUndo() {
    assert(transactionDepth == 0);
    if (undoStack.isEmpty) {
      return null;
    }
    redoStack.add(undoStack.removeLast());
    return redoStack.last;
  }

  _HistoryEntry? popRedo() {
    assert(transactionDepth == 0);
    if (redoStack.isEmpty) {
      return null;
    }
    undoStack.add(redoStack.removeLast());
    return undoStack.last;
  }

  Transaction? forget(int transactionId) {
    for (final stack in [undoStack, redoStack]) {
      final index = stack.lastIndexWhere(
        (entry) => entry.transaction.id == transactionId,
      );
      if (index >= 0) {
        return stack.removeAt(index).transaction;
      }
    }
    return null;
  }

  Transaction? transaction(int transactionId) {
    for (final stack in [undoStack, redoStack]) {
      for (final entry in stack.reversed) {
        if (entry.transaction.id == transactionId) {
          return entry.transaction;
        }
      }
    }
    return null;
  }
}

enum ChangeKind { edit, undo, redo }

/// what happened to the text of a buffer
class BufferChange {
  const BufferChange(this.patch, this.kind);

  final Patch patch;
  final ChangeKind kind;
}

/// the text of a document, which is edited in batches that can be undone.
///
/// the text is kept as fragments, one for each run that an edit put in, and
/// nothing is ever taken out of them: a deletion hides fragments, and an undo
/// shows or hides the ones its edits touched. this is what lets an [Anchor]
/// name a place for good, and what lets the buffer say what changed since any
/// earlier time.
class TextBuffer {
  TextBuffer([
    String text = '',
    Duration groupInterval = const Duration(milliseconds: 300),
    DateTime Function()? clock,
  ]) : _clock = clock ?? DateTime.now,
       _history = _History(groupInterval) {
    final normalized = Rope(normalizeLineEndings(text));
    var fragments = SumTree<_Fragment, _FragmentSummary>(_fragmentOps);
    var insertions = OrderedTree<_InsertionFragment>(
      _InsertionFragment.compare,
    );
    var version = 0;
    if (!normalized.isEmpty) {
      // the text the buffer starts with is the first insertion
      const timestamp = 1;
      version = timestamp;
      final fragment = _Fragment(
        id: Locator.between(Locator.min, Locator.max),
        timestamp: timestamp,
        insertionOffset: 0,
        len: normalized.length,
        visible: true,
      );
      insertions = insertions.insertAll([_InsertionFragment.of(fragment)]);
      fragments = fragments.push(fragment);
    }
    _snapshot = BufferSnapshot._(
      text: normalized,
      deletedText: Rope.empty,
      fragments: fragments,
      insertions: insertions,
      insertionSlices: OrderedTree(_InsertionSlice.compare),
      undoMap: UndoMap(),
      version: version,
      lineEnding: LineEnding.detect(text),
    );
  }

  final DateTime Function() _clock;
  final _History _history;
  late BufferSnapshot _snapshot;

  /// the time of the last thing that happened; the first is for the text the
  /// buffer starts with
  int _lamport = 1;

  final List<Subscription> _subscriptions = [];
  final List<void Function(BufferChange)> _listeners = [];

  int _tick() => ++_lamport;

  /// edits made within this long of each other are undone together
  Duration get groupInterval => _history.groupInterval;

  /// the buffer as it is now; it does not change, so it can be kept
  BufferSnapshot get snapshot => _snapshot;

  /// the text as it is now
  Rope get text => _snapshot.text;

  /// the time of the last edit or undo
  int get version => _snapshot.version;

  /// what the file had, and what it gets back when saved
  LineEnding get lineEnding => _snapshot.lineEnding;

  set lineEnding(LineEnding lineEnding) =>
      _snapshot = _snapshot._with(lineEnding: lineEnding);

  int get length => _snapshot.length;
  int get lineCount => _snapshot.lineCount;

  /// the text with the line endings the file has
  String textForSave() => lineEnding == LineEnding.lf
      ? text.toString()
      : text.toString().replaceAll('\n', lineEnding.text);

  bool get canUndo => _history.undoStack.isNotEmpty;
  bool get canRedo => _history.redoStack.isNotEmpty;

  /// the edits from now on are gathered for whoever holds what is returned,
  /// until they are asked for
  Subscription subscribe() {
    final subscription = Subscription();
    _subscriptions.add(subscription);
    return subscription;
  }

  void unsubscribe(Subscription subscription) =>
      _subscriptions.remove(subscription);

  void addListener(void Function(BufferChange) listener) =>
      _listeners.add(listener);

  void removeListener(void Function(BufferChange) listener) =>
      _listeners.remove(listener);

  Point offsetToPoint(int offset) => text.offsetToPoint(offset);
  int pointToOffset(Point point) => text.pointToOffset(point);

  Anchor anchorBefore(int offset) => _snapshot.anchorBefore(offset);
  Anchor anchorAfter(int offset) => _snapshot.anchorAfter(offset);
  Anchor anchorAt(int offset, Bias bias) => _snapshot.anchorAt(offset, bias);
  int offsetForAnchor(Anchor anchor) => _snapshot.offsetForAnchor(anchor);

  /// starts a group of edits that is undone as one, with the [selections] to
  /// go back to. groups may be started inside each other, and the outermost
  /// is the one that counts.
  Transaction? beginTransaction([List<AnchorSelection>? selections]) =>
      _history.startTransaction(version, _clock(), _tick, selections);

  /// ends the group, with the [selections] that redo goes back to. gives the
  /// transaction the edits are in, which is an earlier one when they were
  /// made soon after it; null when nothing was edited or a group is open
  /// still.
  Transaction? endTransaction([List<AnchorSelection>? selections]) {
    final entry = _history.endTransaction(_clock());
    if (entry == null) {
      return null;
    }
    entry.transaction.selectionsAfter = selections;
    return _history.group();
  }

  /// makes the next edit start a group of its own, however soon it comes
  Transaction? finalizeLastTransaction() => _history.finalizeLastTransaction();

  /// makes one group of the ones from the transaction [transactionId] on
  void groupUntilTransaction(int transactionId) =>
      _history.groupUntil(transactionId);

  /// takes the transaction out of what can be undone and redone
  Transaction? forgetTransaction(int transactionId) =>
      _history.forget(transactionId);

  Transaction? transaction(int transactionId) =>
      _history.transaction(transactionId);

  /// replaces the ranges of [replacements] at once. they are in the offsets of
  /// the text as it is, and may not overlap; the patch that is returned is
  /// what the edit did to the text.
  Patch edit(Iterable<Replacement> replacements) {
    final sorted = [
      for (final r in replacements)
        Replacement(r.start, r.end, normalizeLineEndings(r.text)),
    ]..sort((a, b) => a.start != b.start ? a.start - b.start : a.end - b.end);
    // one that puts nothing in the place of nothing is no edit
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
    if (sorted.isEmpty) {
      return Patch.empty;
    }

    beginTransaction();
    final timestamp = _tick();
    final (snapshot, edits) = _snapshot._applyEdit(sorted, timestamp);
    _snapshot = snapshot;
    _history.pushUndo(timestamp);
    endTransaction();
    return _publish(edits, ChangeKind.edit);
  }

  /// takes back the last group of edits, and returns it, so that its
  /// selections can be put back; null when there is nothing to undo
  Transaction? undo() {
    if (_history.transactionDepth != 0) {
      return null;
    }
    final entry = _history.popUndo();
    if (entry == null) {
      return null;
    }
    _undoOrRedo(entry.transaction, ChangeKind.undo);
    return entry.transaction;
  }

  /// does again what was undone, and returns it; null when there is nothing
  Transaction? redo() {
    if (_history.transactionDepth != 0) {
      return null;
    }
    final entry = _history.popRedo();
    if (entry == null) {
      return null;
    }
    _undoOrRedo(entry.transaction, ChangeKind.redo);
    return entry.transaction;
  }

  /// the transactions that can be undone, the oldest first
  List<Transaction> get undoStack => [
    for (final entry in _history.undoStack) entry.transaction,
  ];

  /// takes back [transaction] when it is done, and does it again when it is
  /// undone, wherever it is among the others
  void undoOrRedo(Transaction transaction) => _undoOrRedo(
    transaction,
    transaction.editIds.any(_snapshot._undoMap.isUndone)
        ? ChangeKind.redo
        : ChangeKind.undo,
  );

  /// undoes each edit of [transaction] once more than it has been, which
  /// takes back one that is done and does again one that is undone
  void _undoOrRedo(Transaction transaction, ChangeKind kind) {
    final counts = <int, int>{
      for (final editId in transaction.editIds)
        editId: _snapshot._undoMap.undoCount(editId) + 1,
    };
    final (snapshot, edits) = _snapshot._applyUndo(_tick(), counts);
    _snapshot = snapshot;
    _publish(edits, kind);
  }

  /// the ranges of the text as it is that the edits of [transaction] put in
  List<(int start, int end)> editedRangesForTransaction(
    Transaction transaction,
  ) {
    final ranges = <(int, int)>[];
    final cursor = _snapshot._fragments.cursor(_dim);
    Locator? previous;
    for (final id in _snapshot._fragmentIdsForEdits(transaction.editIds)) {
      if (id == previous) {
        continue;
      }
      previous = id;
      cursor.seekForward((p) => id.compareTo(p.maxId), Bias.left);
      final fragment = cursor.item;
      if (fragment == null) {
        continue;
      }
      final start = cursor.start.visible;
      final end = start + (fragment.visible ? fragment.len : 0);
      if (ranges.isNotEmpty && ranges.last.$2 == start) {
        ranges[ranges.length - 1] = (ranges.last.$1, end);
      } else {
        ranges.add((start, end));
      }
    }
    return ranges;
  }

  Patch _publish(List<LayerEdit> edits, ChangeKind kind) {
    for (final subscription in _subscriptions) {
      subscription.publish(edits);
    }
    final patch = Patch([
      for (final edit in edits)
        Edit(
          edit.oldStart,
          edit.oldEnd - edit.oldStart,
          edit.newEnd - edit.newStart,
        ),
    ]);
    if (edits.isNotEmpty) {
      final change = BufferChange(patch, kind);
      for (final listener in List.of(_listeners)) {
        listener(change);
      }
    }
    return patch;
  }
}
