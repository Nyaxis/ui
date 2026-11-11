import '../editor_core/buffer.dart';
import '../editor_core/patch.dart';
import '../editor_core/rope.dart';
import 'lsp_client.dart';

/// keeps a language server told of the text of one buffer: it opens the
/// document, sends what each change did, and closes it
class LspDocumentSync {
  LspDocumentSync({
    required this.client,
    required this.buffer,
    required this.uri,
    required this.languageId,
  });

  final LspClient client;
  final TextBuffer buffer;
  final String uri;
  final String languageId;

  /// the text that the server has
  late Rope _synced;
  int _version = 0;
  bool _open = false;

  /// the version of the text that the server was last told of
  int get version => _version;

  bool get isOpen => _open;

  void open() {
    if (_open) {
      return;
    }
    _open = true;
    _synced = buffer.text;
    _version = 1;
    client.didOpen(uri, languageId, _version, _synced.toString());
    buffer.addListener(_onChange);
  }

  void close() {
    if (!_open) {
      return;
    }
    _open = false;
    buffer.removeListener(_onChange);
    client.didClose(uri);
  }

  void _onChange(BufferChange change) {
    if (!_open || change.patch.isEmpty) {
      return;
    }
    final text = buffer.text;
    final changes = switch (client.textSync) {
      TextSync.none => null,
      TextSync.full => [
        <String, Object?>{'text': text.toString()},
      ],
      TextSync.incremental => changesOf(change.patch, _synced, text),
    };
    _synced = text;
    if (changes == null) {
      return;
    }
    _version++;
    client.didChange(uri, _version, changes);
  }

  /// where [offset] is in [text], as a row and a column of UTF-16 code units
  static LspPosition positionAt(Rope text, int offset) {
    final row = text.rowAt(offset);
    return LspPosition(row, offset - text.lineStart(row));
  }

  /// what [patch] did, as changes for the server. they go from the end of the
  /// text to its start, so that each is still right after the ones before it,
  /// as the server applies them one by one; [before] is the text the patch was
  /// made on, and [after] what it made
  static List<Map<String, Object?>> changesOf(
    Patch patch,
    Rope before,
    Rope after,
  ) {
    final changes = <Map<String, Object?>>[];
    var shift = 0;
    final placed = <(Edit, int)>[];
    for (final edit in patch.edits) {
      placed.add((edit, edit.start + shift));
      shift += edit.newLength - edit.oldLength;
    }
    for (final (edit, newStart) in placed.reversed) {
      changes.add({
        'range': LspRange(
          positionAt(before, edit.start),
          positionAt(before, edit.oldEnd),
        ).toJson(),
        'text': after.substring(newStart, newStart + edit.newLength),
      });
    }
    return changes;
  }
}
