import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor_core/buffer.dart';
import 'package:ui/editor_core/selections_collection.dart';

SelectionsCollection _collection([TextBuffer? buffer]) =>
    SelectionsCollection(buffer ?? TextBuffer('0123456789' * 4));

void main() {
  group('Selection', () {
    test('the head is where it stopped, and the tail where it began', () {
      const forward = Selection(id: 1, start: 2, end: 6);
      expect(forward.head, 6);
      expect(forward.tail, 2);
      final back = forward.swapHeadAndTail();
      expect(back.reversed, isTrue);
      expect(back.head, 2);
      expect(back.tail, 6);
    });

    test('moving the head past the tail turns the selection around', () {
      const s = Selection(id: 1, start: 4, end: 8);
      final past = s.withHead(1);
      expect((past.start, past.end, past.reversed), (1, 4, true));
      final back = past.withHead(10);
      expect((back.start, back.end, back.reversed), (4, 10, false));
      expect(s.withHead(6).end, 6);
    });

    test('moving the tail past the head turns the selection around', () {
      const s = Selection(id: 1, start: 4, end: 8);
      final past = s.withTail(11);
      expect((past.start, past.end, past.reversed), (8, 11, true));
      expect(past.head, 8);
      expect(s.withTail(5).start, 5);
    });

    test('a head and a tail make a selection in either order', () {
      const s = Selection(id: 1, start: 0, end: 0);
      // the head is the end that moves, so one before the tail is reversed
      final a = s.withHeadAndTail(2, 9);
      expect((a.start, a.end, a.reversed), (2, 9, true));
      expect(a.head, 2);
      final b = s.withHeadAndTail(9, 2);
      expect((b.start, b.end, b.reversed), (2, 9, false));
      expect(b.head, 9);
    });

    test('collapsing leaves a cursor', () {
      final c = const Selection(
        id: 1,
        start: 3,
        end: 9,
        reversed: true,
      ).collapseTo(5);
      expect(c.isEmpty, isTrue);
      expect(c.reversed, isFalse);
      expect(c.start, 5);
    });
  });

  group('shouldMerge', () {
    test('selections that overlap, or start together, are one', () {
      expect(shouldMerge(0, 5, 3, 8), isTrue);
      expect(shouldMerge(0, 5, 0, 2), isTrue);
    });

    test('selections that only touch stay apart', () {
      expect(shouldMerge(0, 5, 5, 8), isFalse);
      expect(shouldMerge(0, 5, 7, 9), isFalse);
    });

    test('a cursor at the edge of a selection is taken in', () {
      expect(shouldMerge(0, 5, 5, 5), isTrue);
      expect(shouldMerge(3, 3, 3, 9), isTrue);
      expect(shouldMerge(4, 4, 4, 4), isTrue);
      expect(shouldMerge(3, 3, 4, 9), isFalse);
    });
  });

  group('SelectionsCollection', () {
    test('it starts with one cursor at the start', () {
      final selections = _collection();
      expect(selections.length, 1);
      expect(selections.first.isEmpty, isTrue);
      expect(selections.first.start, 0);
    });

    test('selections are put in order, and overlapping ones become one', () {
      final selections = _collection()
        ..selectRanges([(10, 14), (0, 3), (12, 20), (30, 30)]);
      expect(
        [for (final s in selections.all) (s.start, s.end)],
        [(0, 3), (10, 20), (30, 30)],
      );
    });

    test('a range given backwards is a reversed selection', () {
      final selections = _collection()..selectRanges([(9, 4)]);
      expect(selections.first.start, 4);
      expect(selections.first.end, 9);
      expect(selections.first.reversed, isTrue);
      expect(selections.first.head, 4);
    });

    test('a cursor is added, and two in one place are one', () {
      final selections = _collection()
        ..addCursor(5)
        ..addCursor(9)
        ..addCursor(5);
      expect([for (final s in selections.all) s.start], [0, 5, 9]);
    });

    test('the newest is the one made last and the oldest the first', () {
      final selections = _collection()
        ..addCursor(5)
        ..addCursor(9);
      expect(selections.newest.start, 9);
      expect(selections.oldest.start, 0);
    });

    test('nothing selected leaves one cursor', () {
      final selections = _collection()..select([]);
      expect(selections.length, 1);
    });

    test('it follows the text through an edit', () {
      final buffer = TextBuffer('0123456789' * 4);
      final selections = _collection(buffer)
        ..selectRanges([(2, 2), (6, 10), (14, 14)]);
      // four code units put in at 0, and the one at 8 taken out
      buffer.edit([
        const Replacement.insert(0, 'abcd'),
        const Replacement(8, 9, ''),
      ]);
      expect(
        [for (final s in selections.all) (s.start, s.end)],
        [(6, 6), (10, 13), (17, 17)],
      );
    });

    test('a selection does not take in text put in at its edges', () {
      final buffer = TextBuffer('0123456789' * 4);
      final selections = _collection(buffer)..selectRanges([(4, 8)]);
      buffer.edit([
        const Replacement.insert(4, 'ab'),
        const Replacement.insert(8, 'cde'),
      ]);
      expect(selections.first.start, 6);
      expect(selections.first.end, 10);
    });

    test('a cursor goes after the text put in at it', () {
      final buffer = TextBuffer('0123456789' * 4);
      final selections = _collection(buffer)..selectRanges([(4, 4)]);
      buffer.edit([const Replacement.insert(4, 'ab')]);
      expect(selections.first.start, 6);
      expect(selections.first.isEmpty, isTrue);
    });

    test('a selection that is all replaced is left a cursor', () {
      final buffer = TextBuffer('0123456789' * 4);
      final selections = _collection(buffer)..selectRanges([(4, 8)]);
      buffer.edit([const Replacement(3, 10, 'ab')]);
      expect(selections.first.isEmpty, isTrue);
      expect(selections.first.start, 5);
    });

    test('selections come back with undo, whatever was edited since', () {
      final buffer = TextBuffer('0123456789' * 4, Duration.zero);
      final selections = _collection(buffer)..selectRanges([(6, 9)]);
      buffer.beginTransaction(selections.anchors);
      buffer.edit([const Replacement(6, 9, 'x')]);
      selections.selectRanges([(7, 7)]);
      buffer.endTransaction(selections.anchors);
      buffer.edit([const Replacement.insert(0, 'abc')]);
      final undone = buffer.undoStack.first;
      buffer.undoOrRedo(undone);
      selections.selectAnchors(undone.selectionsBefore!);
      expect(buffer.text.toString().substring(0, 12), 'abc012345678');
      expect([for (final s in selections.all) (s.start, s.end)], [(9, 12)]);
    });
  });
}
