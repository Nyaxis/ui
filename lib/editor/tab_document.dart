import '../editor_core/buffer.dart' show LineEnding, Replacement;
import '../native_editor/editor_controller.dart';

/// the text of a tab: the buffer of a controller, which the editor view shows
class NativeTabDocument {
  NativeTabDocument(String text, this.uri, {int tabSize = 4, this.onChanged})
    : controller = EditorController(text: text, tabSize: tabSize) {
    _saved = controller.buffer.text.toString();
    controller.buffer.addListener(_changed);
  }

  final EditorController controller;

  /// names the document to the language server
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

  /// the text as it is saved, with the line endings the file has
  Future<String> getText() async => controller.buffer.textForSave();

  Future<void> setText(String text) async {
    final buffer = controller.buffer;
    buffer.lineEnding = LineEnding.detect(text);
    buffer.edit([Replacement(0, buffer.length, text)]);
    controller.selections.selectRanges([(0, 0)]);
  }

  /// whether the text is not what was last saved
  Future<bool> isDirty() async {
    if (_lineEndingChanged) {
      return true;
    }
    final text = controller.buffer.text;
    return text.length != _saved.length || text.toString() != _saved;
  }

  Future<void> markSaved() async {
    _saved = controller.buffer.text.toString();
    _lineEndingChanged = false;
  }

  Future<void> close() async {
    onClosed?.call(this);
    controller.buffer.removeListener(_changed);
    controller.dispose();
  }
}
