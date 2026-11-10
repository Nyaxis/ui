import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor_core/buffer.dart' show Replacement;
import 'package:ui/native_editor/editor_controller.dart';

/// the texts, as `start-end`, of the other places the selected text is
List<String> _found(EditorController controller) {
  final buffer = controller.buffer.snapshot;
  return [
    for (final range in controller.occurrences)
      '${buffer.offsetForAnchor(range.start)}-${buffer.offsetForAnchor(range.end)}',
  ];
}

void main() {
  group('other places the selected text is', () {
    test('every other one is found, and the selection is not one', () {
      final controller = EditorController(text: 'foo bar foo\nbaz foo');
      controller.selections.selectRanges([(0, 3)]);
      controller.notifyListeners();
      expect(_found(controller), ['8-11', '16-19']);
      controller.dispose();
    });

    test('they are of the text as it is written, in any word', () {
      final controller = EditorController(text: 'Foo foo food oo');
      controller.selections.selectRanges([(4, 7)]);
      controller.notifyListeners();
      // not case, not whole words: `foo` is in `food`, and `Foo` is not it
      expect(_found(controller), ['8-11']);
      controller.dispose();
    });

    test('they follow the selection as it changes', () {
      final controller = EditorController(text: 'ab cd ab cd');
      controller.selections.selectRanges([(0, 2)]);
      controller.notifyListeners();
      expect(_found(controller), ['6-8']);
      controller.selections.selectRanges([(3, 5)]);
      controller.notifyListeners();
      expect(_found(controller), ['9-11']);
      controller.selections.selectRanges([(3, 3)]);
      controller.notifyListeners();
      expect(_found(controller), isEmpty);
      controller.dispose();
    });

    test('they are not looked for when nothing, or blanks, are selected', () {
      final controller = EditorController(text: 'a  b  c  d');
      controller.selections.selectRanges([(1, 3)]);
      controller.notifyListeners();
      expect(_found(controller), isEmpty);
      controller.selections.selectRanges([(0, 0)]);
      controller.notifyListeners();
      expect(_found(controller), isEmpty);
      controller.dispose();
    });

    test('they are not looked for with several selections or rows', () {
      final controller = EditorController(text: 'ab\nab\nab');
      controller.selections.selectRanges([(0, 2), (3, 5)]);
      controller.notifyListeners();
      expect(_found(controller), isEmpty);
      controller.selections.selectRanges([(0, 5)]);
      controller.notifyListeners();
      expect(_found(controller), isEmpty);
      controller.selections.selectRanges([(0, 2)]);
      controller.notifyListeners();
      expect(_found(controller), ['3-5', '6-8']);
      controller.dispose();
    });

    test('they are found again after an edit', () {
      final controller = EditorController(text: 'ab ab');
      controller.selections.selectRanges([(0, 2)]);
      controller.notifyListeners();
      expect(_found(controller), ['3-5']);
      controller.buffer.edit([Replacement.insert(5, ' ab')]);
      controller.notifyListeners();
      expect(_found(controller), ['3-5', '6-8']);
      controller.dispose();
    });

    test('they are a highlight behind the text, in the color given', () {
      final controller = EditorController(text: 'ab ab')
        ..occurrenceBackground = 0x22112233;
      controller.selections.selectRanges([(0, 2)]);
      controller.notifyListeners();
      final highlight = controller.highlights.textHighlights.values.single;
      expect(highlight.style.background, 0x22112233);
      controller.occurrenceBackground = 0x33445566;
      expect(
        controller.highlights.textHighlights.values.single.style.background,
        0x33445566,
      );
      controller.dispose();
    });

    test('a change of them is a change of what is drawn, for the view', () {
      final controller = EditorController(text: 'ab ab');
      controller.selections.selectRanges([(0, 2)]);
      var before = controller.revision;
      // the cursor was moved, which tells the view to look at the cursor
      controller.requestRevealCursor();
      expect(_found(controller), ['3-5']);
      expect(controller.revision, greaterThan(before));
      // and so is the end of them
      controller.selections.selectRanges([(0, 0)]);
      before = controller.revision;
      controller.requestRevealCursor();
      expect(_found(controller), isEmpty);
      expect(controller.revision, greaterThan(before));
      controller.dispose();
    });

    test('when they are off there are none', () {
      final controller = EditorController(text: 'ab ab')
        ..highlightSelectedText = false;
      controller.selections.selectRanges([(0, 2)]);
      controller.notifyListeners();
      expect(_found(controller), isEmpty);
      controller.dispose();
    });

    test('a long text is searched a moment after', () async {
      final controller = EditorController(
        text: 'needle ${'x' * 120000} needle',
      );
      controller.selections.selectRanges([(0, 6)]);
      controller.notifyListeners();
      expect(_found(controller), isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(_found(controller), hasLength(1));
      controller.dispose();
    });
  });
}
