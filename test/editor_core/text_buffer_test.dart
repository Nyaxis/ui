import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor_core/buffer.dart';
import 'package:ui/editor_core/display/layer_edit.dart';
import 'package:ui/editor_core/locator.dart';
import 'package:ui/editor_core/patch.dart';
import 'package:ui/editor_core/point.dart';
import 'package:ui/editor_core/rope.dart';
import 'package:ui/editor_core/text_summary.dart';

class _Clock {
  DateTime now = DateTime(2026);

  DateTime call() => now;
}

void _edit(TextBuffer buffer, int start, int end, String text) =>
    buffer.edit([Replacement(start, end, text)]);

String _text(TextBuffer buffer) => buffer.text.toString();

/// [old] with [edits], which say what changed from it to [now], done to it
String _replay(String old, Rope now, List<LayerEdit> edits) {
  var text = old;
  for (final edit in edits) {
    text = text.replaceRange(
      edit.newStart,
      edit.newStart + (edit.oldEnd - edit.oldStart),
      now.substring(edit.newStart, edit.newEnd),
    );
  }
  return text;
}

void main() {
  group('Locator', () {
    test('one made between two is between them', () {
      final random = Random(0);
      final locators = [Locator.min, Locator.max];
      for (var i = 0; i < 2000; i++) {
        // mostly after the last that was put in, as typing is
        final at = random.nextInt(4) == 0
            ? 1 + random.nextInt(locators.length - 1)
            : locators.length - 1;
        final made = Locator.between(locators[at - 1], locators[at]);
        expect(made > locators[at - 1], isTrue);
        expect(made < locators[at], isTrue);
        locators.insert(at, made);
      }
    });

    test('typing in order does not make long locators', () {
      var last = Locator.min;
      for (var i = 0; i < 10000; i++) {
        last = Locator.between(last, Locator.max);
      }
      expect(last.length, 1);
    });
  });

  group('EditPatch', () {
    test('two patches made one do what the two do', () {
      for (var seed = 0; seed < 500; seed++) {
        final random = Random(seed);
        final initial = [
          for (var i = random.nextInt(101); i > 0; i--)
            String.fromCharCode(0x61 + random.nextInt(26)),
        ];
        final patches = <EditPatch>[];
        final expected = List.of(initial);
        for (var i = 0; i < 2; i++) {
          var delta = 0;
          var lastEditEnd = 0;
          final edits = <LayerEdit>[];
          for (var op = 0; op < 20; op++) {
            if (lastEditEnd >= expected.length) {
              break;
            }
            final end =
                lastEditEnd + random.nextInt(expected.length - lastEditEnd + 1);
            final start = lastEditEnd + random.nextInt(end - lastEditEnd + 1);
            var newLen = random.nextInt(4);
            if (start == end && newLen == 0) {
              newLen++;
            }
            lastEditEnd = start + newLen + 1;
            edits.add(
              LayerEdit(start - delta, end - delta, start, start + newLen),
            );
            expected.replaceRange(start, end, [
              for (var n = 0; n < newLen; n++)
                String.fromCharCode(0x41 + random.nextInt(26)),
            ]);
            delta += newLen - (end - start);
          }
          patches.add(EditPatch(edits));
        }

        final composed = patches[0].compose(patches[1].edits);
        final actual = List.of(initial);
        for (final edit in composed.edits) {
          actual.replaceRange(
            edit.newStart,
            edit.newStart + (edit.oldEnd - edit.oldStart),
            expected.sublist(edit.newStart, edit.newEnd),
          );
        }
        expect(actual.join(), expected.join(), reason: 'seed $seed');
      }
    });

    test('an old place is found in the new text', () {
      final patch = EditPatch([
        const LayerEdit(2, 4, 2, 7),
        const LayerEdit(8, 8, 11, 12),
      ]);
      expect(patch.oldToNew(0), 0);
      expect(patch.oldToNew(2), 2);
      expect(patch.oldToNew(3), 2);
      expect(patch.oldToNew(4), 7);
      expect(patch.oldToNew(6), 9);
      expect(patch.oldToNew(8), 12);
      expect(patch.oldToNew(9), 13);
      expect(patch.invert().edits, const [
        LayerEdit(2, 7, 2, 4),
        LayerEdit(11, 12, 8, 8),
      ]);
    });
  });

  group('TextBuffer', () {
    test('edits are made', () {
      final buffer = TextBuffer('abc');
      _edit(buffer, 3, 3, 'def');
      expect(_text(buffer), 'abcdef');
      _edit(buffer, 0, 0, 'ghi');
      expect(_text(buffer), 'ghiabcdef');
      _edit(buffer, 5, 5, 'jkl');
      expect(_text(buffer), 'ghiabjklcdef');
      _edit(buffer, 6, 7, '');
      expect(_text(buffer), 'ghiabjlcdef');
      _edit(buffer, 4, 9, 'mno');
      expect(_text(buffer), 'ghiamnoef');
      buffer.snapshot.checkInvariants();
    });

    test('anchors stay with their text', () {
      final buffer = TextBuffer();
      _edit(buffer, 0, 0, 'abc');
      final left = buffer.anchorBefore(2);
      final right = buffer.anchorAfter(2);
      Point point(Anchor anchor) => buffer.snapshot.pointForAnchor(anchor);

      _edit(buffer, 1, 1, 'def\n');
      expect(_text(buffer), 'adef\nbc');
      expect(buffer.offsetForAnchor(left), 6);
      expect(buffer.offsetForAnchor(right), 6);
      expect(point(left), const Point(1, 1));
      expect(point(right), const Point(1, 1));

      _edit(buffer, 2, 3, '');
      expect(_text(buffer), 'adf\nbc');
      expect(buffer.offsetForAnchor(left), 5);
      expect(buffer.offsetForAnchor(right), 5);

      _edit(buffer, 5, 5, 'ghi\n');
      expect(_text(buffer), 'adf\nbghi\nc');
      expect(buffer.offsetForAnchor(left), 5);
      expect(buffer.offsetForAnchor(right), 9);
      expect(point(left), const Point(1, 1));
      expect(point(right), const Point(2, 0));

      _edit(buffer, 7, 9, '');
      expect(_text(buffer), 'adf\nbghc');
      expect(buffer.offsetForAnchor(left), 5);
      expect(buffer.offsetForAnchor(right), 7);
      expect(point(right), const Point(1, 3));

      final snapshot = buffer.snapshot;
      final at0 = snapshot.anchorBefore(0);
      final at1 = snapshot.anchorBefore(1);
      final at2 = snapshot.anchorBefore(2);
      expect(snapshot.compareAnchors(at0, at0), 0);
      expect(snapshot.compareAnchors(at1, at1), 0);
      expect(snapshot.compareAnchors(at0, at1), lessThan(0));
      expect(snapshot.compareAnchors(at1, at2), lessThan(0));
      expect(snapshot.compareAnchors(at0, at2), lessThan(0));
      expect(snapshot.compareAnchors(at1, at0), greaterThan(0));
      expect(snapshot.compareAnchors(at2, at1), greaterThan(0));
      expect(snapshot.compareAnchors(at2, at0), greaterThan(0));
    });

    test('anchors of the start and the end stay there', () {
      final buffer = TextBuffer();
      final beforeStart = buffer.anchorBefore(0);
      final afterEnd = buffer.anchorAfter(0);

      _edit(buffer, 0, 0, 'abc');
      expect(buffer.offsetForAnchor(beforeStart), 0);
      expect(buffer.offsetForAnchor(afterEnd), 3);

      final afterStart = buffer.anchorAfter(0);
      final beforeEnd = buffer.anchorBefore(3);
      _edit(buffer, 3, 3, 'def');
      _edit(buffer, 0, 0, 'ghi');
      expect(_text(buffer), 'ghiabcdef');
      expect(buffer.offsetForAnchor(beforeStart), 0);
      expect(buffer.offsetForAnchor(afterStart), 3);
      expect(buffer.offsetForAnchor(beforeEnd), 6);
      expect(buffer.offsetForAnchor(afterEnd), 9);
    });

    test('an anchor in text that is taken out is where the text was', () {
      final buffer = TextBuffer('abcdefgh');
      final deleted = buffer.anchorBefore(5);
      _edit(buffer, 3, 6, '');
      final snapshot = buffer.snapshot;
      expect(snapshot.offsetForAnchor(deleted), 3);
      expect(snapshot.isValid(deleted), isFalse);
      expect(snapshot.isValid(snapshot.anchorBefore(4)), isTrue);
      buffer.undo();
      expect(buffer.offsetForAnchor(deleted), 5);
      expect(buffer.snapshot.isValid(deleted), isTrue);
    });

    test('transactions are undone and redone in any order', () {
      final buffer = TextBuffer('1234', Duration.zero);
      _edit(buffer, 1, 1, 'abx');
      _edit(buffer, 3, 4, 'yzef');
      _edit(buffer, 3, 5, 'cd');
      expect(_text(buffer), '1abcdef234');

      final entries = buffer.undoStack;
      expect(entries, hasLength(3));

      buffer.undoOrRedo(entries[0]);
      expect(_text(buffer), '1cdef234');
      buffer.undoOrRedo(entries[0]);
      expect(_text(buffer), '1abcdef234');

      buffer.undoOrRedo(entries[1]);
      expect(_text(buffer), '1abcdx234');
      buffer.undoOrRedo(entries[2]);
      expect(_text(buffer), '1abx234');
      buffer.undoOrRedo(entries[1]);
      expect(_text(buffer), '1abyzef234');
      buffer.undoOrRedo(entries[2]);
      expect(_text(buffer), '1abcdef234');

      buffer.undoOrRedo(entries[2]);
      expect(_text(buffer), '1abyzef234');
      buffer.undoOrRedo(entries[0]);
      expect(_text(buffer), '1yzef234');
      buffer.undoOrRedo(entries[1]);
      expect(_text(buffer), '1234');
      buffer.snapshot.checkInvariants();
    });

    test('transactions close in time are undone together', () {
      final clock = _Clock();
      final buffer = TextBuffer(
        '123456',
        const Duration(milliseconds: 300),
        clock.call,
      );

      final first = buffer.beginTransaction()!;
      _edit(buffer, 2, 4, 'cd');
      buffer.endTransaction();
      expect(_text(buffer), '12cd56');

      buffer.beginTransaction();
      _edit(buffer, 4, 5, 'e');
      expect(buffer.endTransaction(), isNotNull);
      expect(_text(buffer), '12cde6');

      clock.now = clock.now.add(const Duration(milliseconds: 301));
      buffer.beginTransaction();
      _edit(buffer, 0, 1, 'a');
      _edit(buffer, 1, 1, 'b');
      expect(buffer.endTransaction(), isNotNull);
      expect(_text(buffer), 'ab2cde6');

      // the last was made after the interval, and is undone alone
      buffer.undo();
      expect(_text(buffer), '12cde6');
      // the first two were made in the interval, and are undone together
      buffer.undo();
      expect(_text(buffer), '123456');
      buffer.redo();
      expect(_text(buffer), '12cde6');
      buffer.redo();
      expect(_text(buffer), 'ab2cde6');

      buffer.beginTransaction();
      expect(buffer.endTransaction(), isNull);
      buffer.undo();
      expect(_text(buffer), '12cde6');

      // an edit takes away what could be redone
      buffer.beginTransaction();
      _edit(buffer, 0, 0, 'X');
      buffer.endTransaction();
      expect(_text(buffer), 'X12cde6');
      buffer.redo();
      expect(_text(buffer), 'X12cde6');
      buffer.undo();
      expect(_text(buffer), '12cde6');
      buffer.undo();
      expect(_text(buffer), '123456');

      // transactions are made one by hand
      buffer.redo();
      buffer.redo();
      expect(_text(buffer), 'X12cde6');
      buffer.groupUntilTransaction(first.id);
      buffer.undo();
      expect(_text(buffer), '123456');
      buffer.redo();
      expect(_text(buffer), 'X12cde6');
    });

    test('a finalized transaction is not added to', () {
      final clock = _Clock();
      final buffer = TextBuffer(
        '123456',
        const Duration(milliseconds: 1),
        clock.call,
      );

      buffer.beginTransaction();
      _edit(buffer, 2, 4, 'cd');
      buffer.endTransaction();
      expect(_text(buffer), '12cd56');

      buffer.finalizeLastTransaction();
      buffer.beginTransaction();
      _edit(buffer, 4, 5, 'e');
      buffer.endTransaction();
      expect(_text(buffer), '12cde6');

      buffer.beginTransaction();
      _edit(buffer, 0, 1, 'a');
      _edit(buffer, 1, 1, 'b');
      buffer.endTransaction();
      expect(_text(buffer), 'ab2cde6');

      buffer.undo();
      expect(_text(buffer), '12cd56');
      buffer.undo();
      expect(_text(buffer), '123456');
      buffer.redo();
      expect(_text(buffer), '12cd56');
      buffer.redo();
      expect(_text(buffer), 'ab2cde6');
    });

    test('the ranges a transaction put in follow later edits', () {
      final buffer = TextBuffer('1234567');
      buffer.beginTransaction();
      _edit(buffer, 2, 4, 'cd');
      _edit(buffer, 6, 6, 'efg');
      buffer.endTransaction();
      expect(_text(buffer), '12cd56efg7');

      final transaction = buffer.finalizeLastTransaction()!;
      expect(buffer.editedRangesForTransaction(transaction), [(2, 4), (6, 9)]);

      _edit(buffer, 5, 5, 'hijk');
      expect(_text(buffer), '12cd5hijk6efg7');
      expect(buffer.editedRangesForTransaction(transaction), [
        (2, 4),
        (10, 13),
      ]);

      _edit(buffer, 4, 4, 'l');
      expect(_text(buffer), '12cdl5hijk6efg7');
      expect(buffer.editedRangesForTransaction(transaction), [
        (2, 4),
        (11, 14),
      ]);
    });

    test('random edits, undos and redos', () {
      const pieces = ['a', 'b', 'cd', '\n', ' ', 'é', '😀', 'xyz'];
      for (var seed = 0; seed < 300; seed++) {
        final random = Random(seed);
        String randomText(int max) => List.generate(
          random.nextInt(max),
          (_) => pieces[random.nextInt(pieces.length)],
        ).join();

        var reference = randomText(3);
        final buffer = TextBuffer(
          reference,
          Duration(milliseconds: random.nextInt(201)),
        );
        (int, int) randomRange(int from, BufferSnapshot of) {
          final end = of.clipOffset(
            from + random.nextInt(of.length - from + 1),
            Bias.right,
          );
          final start = of.clipOffset(
            from + random.nextInt(end - from + 1),
            Bias.right,
          );
          return (start, end);
        }

        final versions = <(BufferSnapshot, Subscription)>[];
        for (var op = 0; op < 10; op++) {
          final why = 'seed $seed op $op';
          final edits = <Replacement>[];
          int? lastEnd;
          for (var i = 0; i < 5; i++) {
            if (lastEnd != null && lastEnd >= buffer.length) {
              break;
            }
            final (start, end) = randomRange(
              lastEnd == null ? 0 : lastEnd + 1,
              buffer.snapshot,
            );
            if (lastEnd != null && start <= lastEnd) {
              break;
            }
            lastEnd = end;
            edits.add(Replacement(start, end, randomText(10)));
          }
          buffer.edit(edits);
          for (final edit in edits.reversed) {
            reference = reference.replaceRange(edit.start, edit.end, edit.text);
          }
          expect(_text(buffer), reference, reason: why);

          if (random.nextInt(4) == 0) {
            for (var i = 1 + random.nextInt(5); i > 0; i--) {
              final stack = buffer.undoStack;
              if (stack.isNotEmpty) {
                buffer.undoOrRedo(stack[random.nextInt(stack.length)]);
              }
            }
            reference = _text(buffer);
          }

          final (start, end) = randomRange(0, buffer.snapshot);
          expect(
            buffer.text.textSummaryForRange(start, end),
            TextSummary.of(reference.substring(start, end)),
            reason: why,
          );
          buffer.snapshot.checkInvariants();

          if (random.nextInt(10) < 3) {
            versions.add((buffer.snapshot, buffer.subscribe()));
          }
        }

        final now = buffer.snapshot;
        for (final (old, subscription) in versions) {
          final why = 'seed $seed from version ${old.version}';
          final oldText = old.text.toString();
          final edits = now.editsSince(old.version);
          expect(_replay(oldText, now.text, edits), _text(buffer), reason: why);
          expect(
            now.textForVersion(old.version).toString(),
            oldText,
            reason: why,
          );

          for (var i = 0; i < 5; i++) {
            final end = old.clipOffset(
              random.nextInt(old.length + 1),
              Bias.right,
            );
            final start = old.clipOffset(random.nextInt(end + 1), Bias.left);
            final range = AnchorRange(
              old.anchorBefore(start),
              old.anchorAfter(end),
            );
            var text = oldText.substring(start, end);
            final newText = now.text.substring(
              now.offsetForAnchor(range.start),
              now.offsetForAnchor(range.end),
            );
            for (final (edit, _) in now.anchoredEditsSince(
              old.version,
              range,
            )) {
              text = text.replaceRange(
                edit.newStart,
                edit.newStart + (edit.oldEnd - edit.oldStart),
                newText.substring(edit.newStart, edit.newEnd),
              );
            }
            expect(text, newText, reason: '$why in $start..$end');
          }

          expect(now.hasEditsSince(old.version), edits.isNotEmpty, reason: why);
          expect(
            _replay(oldText, now.text, subscription.consume().edits),
            _text(buffer),
            reason: why,
          );
        }
      }
    });

    test('anchors are found in a text of many fragments', () {
      final random = Random(7);
      final buffer = TextBuffer('abcdefghij\n' * 100);
      final anchors = <(Anchor, int)>[];
      final dead = <int>{};
      for (var i = 0; i < 400; i++) {
        final at = random.nextInt(buffer.length + 1);
        final bias = random.nextBool() ? Bias.left : Bias.right;
        anchors.add((buffer.anchorAt(at, bias), at));
        if (i.isEven) {
          final start = random.nextInt(buffer.length + 1);
          final end = min(buffer.length, start + random.nextInt(4));
          final text = 'xy'.substring(0, random.nextInt(3));
          final patch = buffer.edit([Replacement(start, end, text)]);
          final edits = layerEditsFromPatch(patch);
          for (var n = 0; n < anchors.length; n++) {
            final (anchor, offset) = anchors[n];
            // an anchor whose character was taken out stays where that was,
            // before what is put in there later
            final bias = dead.contains(n) ? Bias.left : anchor.bias;
            if (start <= offset && offset < end) {
              dead.add(n);
            }
            anchors[n] = (anchor, mapOffsetThroughEdits(offset, bias, edits));
          }
        }
        for (final (anchor, offset) in anchors) {
          expect(buffer.offsetForAnchor(anchor), offset, reason: 'step $i');
        }
      }
    });
  });
}
