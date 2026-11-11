import 'package:flutter_test/flutter_test.dart';
import 'package:ui/editor_core/buffer.dart';
import 'package:ui/lsp/document_sync.dart';

import 'lsp_test_server.dart';

Future<(LspTestPair, TextBuffer, LspDocumentSync)> _open(
  String text, {
  Map<String, Object?> capabilities = const {'textDocumentSync': 2},
}) async {
  final pair = LspTestPair.create(capabilities: capabilities);
  await pair.client.initialize();
  final buffer = TextBuffer(text);
  final sync = LspDocumentSync(
    client: pair.client,
    buffer: buffer,
    uri: 'file:///a.luau',
    languageId: 'luau',
  );
  sync.open();
  await pair.settle();
  return (pair, buffer, sync);
}

void main() {
  test('the server is told the text when the document opens', () async {
    final (pair, _, sync) = await _open('local a = 1\n');
    final opened = pair.sent('textDocument/didOpen').single;
    expect(opened['textDocument'], {
      'uri': 'file:///a.luau',
      'languageId': 'luau',
      'version': 1,
      'text': 'local a = 1\n',
    });
    sync.close();
    await pair.settle();
    expect(pair.sent('textDocument/didClose'), hasLength(1));
    await pair.dispose();
  });

  test('an edit is sent as a range with its new text', () async {
    final (pair, buffer, sync) = await _open('local a = 1\nprint(a)\n');
    buffer.edit([const Replacement(10, 11, '42')]);
    await pair.settle();
    final change = pair.sent('textDocument/didChange').single;
    expect(change['textDocument'], {'uri': 'file:///a.luau', 'version': 2});
    expect(change['contentChanges'], [isChange(0, 10, 0, 11, '42')]);
    expect(sync.version, 2);
    await pair.dispose();
  });

  test('several edits go from the end to the start', () async {
    final (pair, buffer, _) = await _open('aaa\nbbb\n');
    buffer.edit([
      const Replacement.insert(0, 'X'),
      const Replacement(4, 5, 'YY'),
    ]);
    await pair.settle();
    final change = pair.sent('textDocument/didChange').single;
    expect(change['contentChanges'], [
      isChange(1, 0, 1, 1, 'YY'),
      isChange(0, 0, 0, 0, 'X'),
    ]);
    await pair.dispose();
  });

  test('a server that takes the whole text gets all of it', () async {
    final (pair, buffer, _) = await _open(
      'abc',
      capabilities: const {'textDocumentSync': 1},
    );
    buffer.edit([const Replacement.insert(3, 'd')]);
    await pair.settle();
    final change = pair.sent('textDocument/didChange').single;
    expect(change['contentChanges'], [
      {'text': 'abcd'},
    ]);
    await pair.dispose();
  });

  test('nothing is sent after the document closes', () async {
    final (pair, buffer, sync) = await _open('abc');
    sync.close();
    buffer.edit([const Replacement.insert(0, 'x')]);
    await pair.settle();
    expect(pair.sent('textDocument/didChange'), isEmpty);
    await pair.dispose();
  });
}
