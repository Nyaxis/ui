import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ui/lsp/json_rpc.dart';
import 'package:ui/lsp/lsp_client.dart';

/// a language server that is only a connection in the test, and a client that
/// talks to it over pipes in memory
class LspTestPair {
  LspTestPair._(this.client, this.server, this.received);

  final LspClient client;
  final JsonRpcConnection server;

  /// every notification that the client sent
  final List<JsonRpcNotification> received;

  static LspTestPair create({
    Map<String, Object?> capabilities = const {'textDocumentSync': 2},
  }) {
    final toServer = StreamController<List<int>>();
    final toClient = StreamController<List<int>>();
    final server = JsonRpcConnection(toServer.stream, toClient.sink);
    final received = <JsonRpcNotification>[];
    server.notifications.listen(received.add);
    server.onRequest = (method, params) async {
      if (method == 'initialize') {
        return {'capabilities': capabilities};
      }
      if (method == 'shutdown') {
        return null;
      }
      throw const JsonRpcException(JsonRpcException.methodNotFound, 'no');
    };
    final client = LspClient(JsonRpcConnection(toClient.stream, toServer.sink));
    return LspTestPair._(client, server, received);
  }

  /// lets the pipes carry what was written to them
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// the notifications of [method] that the client sent, so far
  List<Map<Object?, Object?>> sent(String method) => [
    for (final n in received)
      if (n.method == method) n.params! as Map<Object?, Object?>,
  ];

  Future<void> dispose() async {
    await client.connection.close();
    await server.close();
  }
}

Matcher isChange(
  int startLine,
  int startCharacter,
  int endLine,
  int endCharacter,
  String text,
) => equals({
  'range': {
    'start': {'line': startLine, 'character': startCharacter},
    'end': {'line': endLine, 'character': endCharacter},
  },
  'text': text,
});
