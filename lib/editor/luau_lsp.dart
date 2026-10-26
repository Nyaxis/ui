import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_monaco/flutter_monaco.dart';

/// opens a scratch luau file and connects the bundled luau-lsp to it; failures
/// are logged and leave a plain editor
Future<void> attachLuauLsp(MonacoController controller) async {
  final server = File(
    '${File(Platform.resolvedExecutable).parent.path}\\data\\flutter_assets'
    '\\assets\\luau-lsp\\luau-lsp.exe',
  );
  if (!server.existsSync()) {
    debugPrint('luau-lsp: unavailable (${server.path})');
    return;
  }
  try {
    final scratch = await controller.openDocument(
      text: '',
      language: MonacoLanguage.lua,
      // lowercase and drive-less: the bridge lowercases the uri in document
      // notifications but not in requests, so any other casing never matches
      uri: Uri.parse('file:///nyaxis/scratch.luau'),
    );
    await controller.activateDocument(scratch);
    final process = await LspServerProcess.start(server.path, [
      'lsp',
      '--definitions=@roblox=${server.parent.path}\\globalTypes.None.d.luau',
      '--docs=${server.parent.path}\\en-us.json',
      '--docs=${server.parent.path}\\luau-en-us.json',
    ]);
    final connection = await controller.connectLanguageServer(
      id: 'luau',
      transport: _withWordRanges(process.transport),
    );
    connection.stateChanges.listen((s) => debugPrint('luau-lsp: $s'));
    debugPrint('luau-lsp: connected, ${connection.state}');
  } catch (e) {
    debugPrint('luau-lsp: $e');
  }
}

/// luau-lsp sends most completions without a text edit, and monaco then
/// replaces nothing, so the typed prefix never filters the list. This adds an
/// edit covering the word before the cursor to each of them.
LspBridgedTransport _withWordRanges(LspBridgedTransport inner) {
  final texts = <String, String>{};
  final completions = <Object?, (String, int, int)>{};

  return LspBridgedTransport(
    fromServer: inner.fromServer.map((message) {
      final request = completions.remove(message['id']);
      final result = message['result'];
      if (request != null && result != null) {
        final items = result is List ? result : (result as Map)['items'];
        if (items is List) {
          _addWordEdits(items, texts[request.$1] ?? '', request);
        }
      }
      return message;
    }),
    toServer: (message) {
      final params = message['params'];
      if (params is Map) {
        final document = params['textDocument'];
        final uri = document is Map ? document['uri'] as String? : null;
        switch (message['method']) {
          case 'textDocument/didOpen':
            texts[uri!] = (document as Map)['text'] as String;
          case 'textDocument/didChange':
            for (final change in params['contentChanges'] as List) {
              texts[uri!] = _applyChange(texts[uri] ?? '', change as Map);
            }
          case 'textDocument/didClose':
            texts.remove(uri);
          case 'textDocument/completion':
            final position = params['position'] as Map;
            completions[message['id']] = (
              uri!,
              position['line'] as int,
              position['character'] as int,
            );
        }
      }
      inner.toServer(message);
    },
    onClose: inner.onClose,
  );
}

int _offset(String text, int line, int character) {
  var start = 0;
  for (var i = 0; i < line; i++) {
    final next = text.indexOf('\n', start);
    if (next < 0) {
      return text.length;
    }
    start = next + 1;
  }
  return (start + character).clamp(0, text.length);
}

String _applyChange(String text, Map change) {
  final range = change['range'];
  if (range is! Map) {
    return change['text'] as String;
  }
  final start = range['start'] as Map;
  final end = range['end'] as Map;
  return text.replaceRange(
    _offset(text, start['line'] as int, start['character'] as int),
    _offset(text, end['line'] as int, end['character'] as int),
    change['text'] as String,
  );
}

final _wordCharacter = RegExp(r'[A-Za-z0-9_]');

void _addWordEdits(List items, String text, (String, int, int) request) {
  final (_, line, character) = request;
  final cursor = _offset(text, line, character);
  var start = cursor;
  while (start > 0 && _wordCharacter.hasMatch(text[start - 1])) {
    start--;
  }
  final range = {
    'start': {'line': line, 'character': character - (cursor - start)},
    'end': {'line': line, 'character': character},
  };
  for (final item in items) {
    if (item is Map && item['textEdit'] == null) {
      item['textEdit'] = {
        'range': range,
        'newText': item['insertText'] ?? item['label'],
      };
    }
  }
}
