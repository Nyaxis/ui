import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor_core/buffer.dart';
import 'package:ui/editor_core/patch.dart';
import 'package:ui/editor_core/point.dart';
import 'package:ui/editor_core/selection.dart';

/// a clock that moves on [step] each time it is read
class _Clock {
  _Clock(this.step);

  final Duration step;
  DateTime now = DateTime(2026);

  DateTime call() {
    now = now.add(step);
    return now;
  }
}

TextBuffer _buffer(String text, {Duration step = const Duration(seconds: 5)}) =>
    TextBuffer(text, const Duration(milliseconds: 300), _Clock(step).call);

void main() {
  group('line endings', () {
    test('the buffer holds lf, and gives the file its endings back', () {
      final buffer = TextBuffer('one\r\ntwo\r\nthree');
      expect(buffer.lineEnding, LineEnding.crlf);
      expect(buffer.text.toString(), 'one\ntwo\nthree');
      expect(buffer.lineCount, 3);
      expect(buffer.textForSave(), 'one\r\ntwo\r\nthree');
    });

    test('the ending that most lines have is the one kept', () {
      expect(LineEnding.detect('a\nb\r\nc\n'), LineEnding.lf);
      expect(LineEnding.detect('a\r\nb\r\nc\n'), LineEnding.crlf);
      expect(LineEnding.detect('no lines'), LineEnding.lf);
    });

    test('a lone carriage return is a line ending, and text put in is too', () {
      final buffer = TextBuffer('a\rb');
      expect(buffer.text.toString(), 'a\nb');
      buffer.edit([const Replacement.insert(1, '\r\nx\r')]);
      expect(buffer.text.toString(), 'a\nx\n\nb');
    });
  });

  group('edit', () {
    test('ranges are replaced at once, in the offsets of the old text', () {
      final buffer = _buffer('hello big world');
      final patch = buffer.edit([
        const Replacement(10, 15, 'there'),
        const Replacement(0, 5, 'HI'),
      ]);
      expect(buffer.text.toString(), 'HI big there');
      expect(patch.edits, const [Edit(0, 5, 2), Edit(10, 5, 5)]);
      expect(buffer.version, 1);
    });

    test('ranges that overlap, or are outside the text, are refused', () {
      final buffer = _buffer('abcdef');
      expect(
        () => buffer.edit([
          const Replacement(0, 4, ''),
          const Replacement(3, 5, ''),
        ]),
        throwsArgumentError,
      );
      expect(
        () => buffer.edit([const Replacement(2, 9, '')]),
        throwsArgumentError,
      );
      expect(
        () => buffer.edit([const Replacement(4, 2, '')]),
        throwsArgumentError,
      );
      expect(buffer.text.toString(), 'abcdef');
    });

    test('an edit that does nothing is not one', () {
      final buffer = _buffer('abc');
      final patch = buffer.edit([const Replacement.insert(1, '')]);
      expect(patch.isEmpty, isTrue);
      expect(buffer.version, 0);
      expect(buffer.canUndo, isFalse);
    });

    test('listeners are told what changed', () {
      final buffer = _buffer('abc');
      final changes = <BufferChange>[];
      buffer.addListener(changes.add);
      buffer.edit([const Replacement(1, 2, 'XY')]);
      expect(changes.single.kind, ChangeKind.edit);
      expect(changes.single.patch.edits, const [Edit(1, 1, 2)]);
      buffer.removeListener(changes.add);
      buffer.edit([const Replacement.insert(0, 'z')]);
      expect(changes, hasLength(1));
    });

    test('points and offsets are those of the text', () {
      final buffer = _buffer('ab\ncd');
      expect(buffer.offsetToPoint(4), const Point(1, 1));
      expect(buffer.pointToOffset(const Point(1, 0)), 3);
    });
  });

  group('undo and redo', () {
    test('an edit is undone and done again', () {
      final buffer = _buffer('abc');
      buffer.edit([const Replacement(1, 2, 'XYZ')]);
      expect(buffer.text.toString(), 'aXYZc');
      expect(buffer.undo(), isNotNull);
      expect(buffer.text.toString(), 'abc');
      expect(buffer.canRedo, isTrue);
      expect(buffer.redo(), isNotNull);
      expect(buffer.text.toString(), 'aXYZc');
      expect(buffer.undo(), isNotNull);
      expect(buffer.undo(), isNull);
    });

    test('edits that come soon after one another are undone together', () {
      final clock = _Clock(const Duration(milliseconds: 50));
      final buffer = TextBuffer(
        '',
        const Duration(milliseconds: 300),
        clock.call,
      );
      buffer.edit([const Replacement.insert(0, 'a')]);
      buffer.edit([const Replacement.insert(1, 'b')]);
      buffer.edit([const Replacement.insert(2, 'c')]);
      expect(buffer.text.toString(), 'abc');
      buffer.undo();
      expect(buffer.text.toString(), '');
      expect(buffer.canUndo, isFalse);
    });

    test('edits that are far apart in time are undone one by one', () {
      final buffer = _buffer('');
      buffer.edit([const Replacement.insert(0, 'a')]);
      buffer.edit([const Replacement.insert(1, 'b')]);
      buffer.undo();
      expect(buffer.text.toString(), 'a');
    });

    test('a group made of several edits is undone as one', () {
      final buffer = _buffer('abc');
      buffer.beginTransaction();
      buffer.edit([const Replacement.insert(0, '1')]);
      buffer.edit([const Replacement.insert(4, '2')]);
      buffer.beginTransaction();
      buffer.edit([const Replacement.insert(2, '3')]);
      buffer.endTransaction();
      buffer.endTransaction();
      expect(buffer.text.toString(), '1a3bc2');
      buffer.undo();
      expect(buffer.text.toString(), 'abc');
      buffer.redo();
      expect(buffer.text.toString(), '1a3bc2');
    });

    test('undo gives back the selections of before, and redo of after', () {
      final buffer = _buffer('abc');
      const before = [Selection(id: 0, start: 1, end: 1)];
      const after = [Selection(id: 0, start: 2, end: 2)];
      buffer.beginTransaction(before);
      buffer.edit([const Replacement.insert(1, 'x')]);
      buffer.endTransaction(after);
      expect(buffer.undo()!.selectionsBefore, before);
      expect(buffer.redo()!.selectionsAfter, after);
    });

    test('a new edit takes away what could be done again', () {
      final buffer = _buffer('abc');
      buffer.edit([const Replacement.insert(0, 'x')]);
      buffer.undo();
      buffer.edit([const Replacement.insert(0, 'y')]);
      expect(buffer.canRedo, isFalse);
      expect(buffer.text.toString(), 'yabc');
    });

    test('nothing is undone while a group is open', () {
      final buffer = _buffer('abc');
      buffer.edit([const Replacement.insert(0, 'x')]);
      buffer.beginTransaction();
      expect(buffer.undo(), isNull);
      buffer.endTransaction();
    });

    test('an edit after an undo is a group of its own, however soon', () {
      final clock = _Clock(const Duration(milliseconds: 10));
      final buffer = TextBuffer(
        '',
        const Duration(milliseconds: 300),
        clock.call,
      );
      buffer.edit([const Replacement.insert(0, 'a')]);
      buffer.edit([const Replacement.insert(1, 'b')]);
      buffer.undo();
      buffer.edit([const Replacement.insert(0, 'c')]);
      buffer.undo();
      expect(buffer.text.toString(), '');
      expect(buffer.canUndo, isFalse);
    });

    test('a group can be closed so that the next edit does not join it', () {
      final clock = _Clock(const Duration(milliseconds: 10));
      final buffer = TextBuffer(
        '',
        const Duration(milliseconds: 300),
        clock.call,
      );
      buffer.edit([const Replacement.insert(0, 'a')]);
      buffer.finalizeLastTransaction();
      buffer.edit([const Replacement.insert(1, 'b')]);
      buffer.undo();
      expect(buffer.text.toString(), 'a');
    });

    test(
      'undo tells listeners the patch in the offsets of the text it changed',
      () {
        final buffer = _buffer('abcdef');
        buffer.edit([
          const Replacement(1, 3, 'X'),
          const Replacement(4, 5, 'YZ'),
        ]);
        final changes = <BufferChange>[];
        buffer.addListener(changes.add);
        buffer.undo();
        expect(buffer.text.toString(), 'abcdef');
        expect(changes.single.kind, ChangeKind.undo);
        // the text before was aXdYZf
        expect(changes.single.patch.edits, const [
          Edit(1, 1, 2),
          Edit(3, 2, 1),
        ]);
        buffer.redo();
        expect(changes.last.kind, ChangeKind.redo);
        expect(changes.last.patch.edits, const [Edit(1, 2, 1), Edit(4, 1, 2)]);
      },
    );

    test('random edits are all undone to the first text and done again', () {
      final random = Random(11);
      final pieces = ['a', 'xy', '\n', 'line\n', '\u{1F600}', ''];
      const start = 'start\ntext\nof the buffer\n';
      final buffer = _buffer(start);
      var model = start;
      final states = [model];
      for (var step = 0; step < 300; step++) {
        final count = 1 + random.nextInt(3);
        final cuts = {
          for (var i = 0; i < count * 2; i++) random.nextInt(model.length + 1),
        }.toList()..sort();
        final replacements = <Replacement>[];
        for (var i = 0; i + 1 < cuts.length; i += 2) {
          final text = pieces[random.nextInt(pieces.length)];
          if (_splitsPair(model, cuts[i]) || _splitsPair(model, cuts[i + 1])) {
            continue;
          }
          replacements.add(Replacement(cuts[i], cuts[i + 1], text));
        }
        buffer.edit(replacements);
        for (final r in replacements.reversed) {
          model = model.replaceRange(r.start, r.end, r.text);
        }
        expect(buffer.text.toString(), model);
        // an edit that is not nothing for nothing is a step, even when the
        // text it leaves is the one that was there
        if (replacements.any((r) => r.start != r.end || r.text.isNotEmpty)) {
          states.add(model);
        }
      }
      // every group was far from the others, so each state is one undo
      for (var i = states.length - 2; i >= 0; i--) {
        expect(buffer.undo(), isNotNull);
        expect(buffer.text.toString(), states[i], reason: 'undo to state $i');
      }
      expect(buffer.canUndo, isFalse);
      for (var i = 1; i < states.length; i++) {
        expect(buffer.redo(), isNotNull);
        expect(buffer.text.toString(), states[i], reason: 'redo to state $i');
      }
    });
  });
}

bool _splitsPair(String text, int at) =>
    at > 0 &&
    at < text.length &&
    text.codeUnitAt(at - 1) >= 0xD800 &&
    text.codeUnitAt(at - 1) <= 0xDBFF &&
    text.codeUnitAt(at) >= 0xDC00 &&
    text.codeUnitAt(at) <= 0xDFFF;
