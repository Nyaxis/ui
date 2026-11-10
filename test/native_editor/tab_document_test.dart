import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor/tab_document.dart';
import 'package:ui/editor_core/buffer.dart' show LineEnding, Replacement;

NativeTabDocument _document(String text) =>
    NativeTabDocument(text, Uri.parse('file:///nyaxis/script0.luau'));

void main() {
  group('NativeTabDocument', () {
    test('it is clean until the text differs from what was saved', () async {
      final document = _document('abc');
      expect(await document.isDirty(), isFalse);
      document.controller.buffer.edit([const Replacement.insert(3, 'd')]);
      expect(await document.isDirty(), isTrue);
      // the text is back to what was saved, so it is clean again
      document.controller.undo();
      expect(await document.isDirty(), isFalse);
      document.controller.buffer.edit([const Replacement.insert(0, 'x')]);
      await document.markSaved();
      expect(await document.isDirty(), isFalse);
      await document.close();
    });

    test('the text is saved with the line endings the file has', () async {
      final document = _document('one\r\ntwo\r\n');
      expect(document.controller.text, 'one\ntwo\n');
      expect(await document.getText(), 'one\r\ntwo\r\n');
      document.changeLineEnding(LineEnding.lf);
      expect(await document.isDirty(), isTrue);
      expect(await document.getText(), 'one\ntwo\n');
      await document.markSaved();
      expect(await document.isDirty(), isFalse);
      await document.close();
    });

    test('setting the text replaces it, and is a change to save', () async {
      final document = _document('old');
      var told = 0;
      document.onChanged = (_) => told++;
      await document.setText('new text');
      expect(document.controller.text, 'new text');
      expect(told, greaterThan(0));
      expect(await document.isDirty(), isTrue);
      await document.close();
    });
  });

  group('EditorController', () {
    test('it goes to a line and column, as far as the text has them', () async {
      final document = _document('one\ntwo\nthree');
      final controller = document.controller;
      controller.goToLineColumn(2, 3);
      expect(controller.selections.first.head, 6);
      controller.goToLineColumn(99, 99);
      expect(controller.selections.first.head, controller.buffer.length);
      controller.goToLineColumn(1);
      expect(controller.selections.first.head, 0);
      await document.close();
    });

    test('indentation is changed with its levels kept', () async {
      final document = _document('a\n    b\n        c\n  d');
      final controller = document.controller;
      controller.setIndentation(spaces: false, size: 4);
      expect(controller.text, 'a\n\tb\n\t\tc\n  d');
      expect(controller.useTabs, isTrue);
      controller.setIndentation(spaces: true, size: 2);
      expect(controller.text, 'a\n  b\n    c\n  d');
      expect(controller.display.tabSize, 2);
      await document.close();
    });
  });
}
