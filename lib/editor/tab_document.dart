import 'package:flutter_monaco/flutter_monaco.dart';

import '../editor_core/buffer.dart' show LineEnding, Replacement;
import '../native_editor/editor_controller.dart';

/// the text of a tab, whichever editor shows it
abstract class TabDocument {
  /// names the document to the language server
  Uri get uri;

  /// the text as it is saved, with the line endings the file has
  Future<String> getText();

  Future<void> setText(String text);

  /// whether the text is not what was last saved
  Future<bool> isDirty();

  Future<void> markSaved();

  Future<void> close();

  /// makes it the one the editor shows
  Future<void> activate();
}

/// a document of the monaco page
class MonacoTabDocument implements TabDocument {
  MonacoTabDocument(this.document, this._controller);

  final MonacoDocument document;
  final MonacoController _controller;

  @override
  Uri get uri => document.uri!;

  @override
  Future<String> getText() => document.getText();

  @override
  Future<void> setText(String text) => document.setText(text);

  @override
  Future<bool> isDirty() => document.isDirty();

  @override
  Future<void> markSaved() => document.markSaved();

  @override
  Future<void> close() => document.close();

  @override
  Future<void> activate() => _controller.activateDocument(document);
}

/// a document of the editor that flutter draws: its text is the buffer of a
/// controller, which the editor view shows
class NativeTabDocument implements TabDocument {
  NativeTabDocument(String text, this.uri, {int tabSize = 4, this.onChanged})
    : controller = EditorController(text: text, tabSize: tabSize) {
    _saved = controller.buffer.text.toString();
    controller.buffer.addListener(_changed);
  }

  final EditorController controller;

  @override
  final Uri uri;

  /// told when the text changes
  void Function(NativeTabDocument document)? onChanged;

  /// told when the document is closed
  void Function(NativeTabDocument document)? onClosed;

  late String _saved;
  bool _lineEndingChanged = false;

  void _changed(Object _) => onChanged?.call(this);

  /// the line ending of the file was changed, which is a change of its text
  void changeLineEnding(LineEnding lineEnding) {
    if (controller.buffer.lineEnding == lineEnding) {
      return;
    }
    controller.buffer.lineEnding = lineEnding;
    _lineEndingChanged = true;
    onChanged?.call(this);
  }

  @override
  Future<String> getText() async => controller.buffer.textForSave();

  @override
  Future<void> setText(String text) async {
    final buffer = controller.buffer;
    buffer.lineEnding = LineEnding.detect(text);
    buffer.edit([Replacement(0, buffer.length, text)]);
    controller.selections.selectRanges([(0, 0)]);
  }

  @override
  Future<bool> isDirty() async {
    if (_lineEndingChanged) {
      return true;
    }
    final text = controller.buffer.text;
    return text.length != _saved.length || text.toString() != _saved;
  }

  @override
  Future<void> markSaved() async {
    _saved = controller.buffer.text.toString();
    _lineEndingChanged = false;
  }

  @override
  Future<void> close() async {
    onClosed?.call(this);
    controller.buffer.removeListener(_changed);
    controller.dispose();
  }

  @override
  Future<void> activate() async {}
}
