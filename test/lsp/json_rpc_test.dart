import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ui/lsp/json_rpc.dart';

List<int> _frame(Map<String, Object?> message) {
  final body = utf8.encode(jsonEncode(message));
  return [...ascii.encode('Content-Length: ${body.length}\r\n\r\n'), ...body];
}

void main() {
  test('a request gets the result that the other side answers with', () async {
    final a = StreamController<List<int>>();
    final b = StreamController<List<int>>();
    final client = JsonRpcConnection(b.stream, a.sink);
    final server = JsonRpcConnection(a.stream, b.sink);
    server.onRequest = (method, params) async => {'echo': params, 'm': method};
    final result = await client.request('ask', {'x': 1});
    expect(result, {
      'echo': {'x': 1},
      'm': 'ask',
    });
    await client.close();
    await server.close();
  });

  test('an error answer is thrown with its code', () async {
    final a = StreamController<List<int>>();
    final b = StreamController<List<int>>();
    final client = JsonRpcConnection(b.stream, a.sink);
    final server = JsonRpcConnection(a.stream, b.sink);
    // no handler: the method is not found
    await expectLater(
      client.request('nothing'),
      throwsA(
        isA<JsonRpcException>().having(
          (e) => e.code,
          'code',
          JsonRpcException.methodNotFound,
        ),
      ),
    );
    await client.close();
    await server.close();
  });

  test('a message that comes in pieces, or many in one, is read whole', () async {
    final input = StreamController<List<int>>();
    final sink = StreamController<List<int>>();
    final connection = JsonRpcConnection(input.stream, sink.sink);
    // a sink with nobody listening never finishes closing
    sink.stream.listen((_) {});
    final methods = <String>[];
    connection.notifications.listen((n) => methods.add(n.method));
    final first = _frame({'jsonrpc': '2.0', 'method': 'one'});
    final second = _frame({'jsonrpc': '2.0', 'method': 'two'});
    final third = _frame({'jsonrpc': '2.0', 'method': 'três'});
    // the first in two cut pieces, the other two together
    input.add(first.sublist(0, 7));
    input.add(first.sublist(7, first.length - 3));
    input.add([...first.sublist(first.length - 3), ...second, ...third]);
    await Future<void>.delayed(Duration.zero);
    expect(methods, ['one', 'two', 'três']);
    await connection.close();
  });

  test('requests that are open fail when the connection ends', () async {
    final input = StreamController<List<int>>();
    final sink = StreamController<List<int>>();
    final connection = JsonRpcConnection(input.stream, sink.sink);
    final pending = connection.request('never');
    unawaited(input.close());
    await expectLater(
      pending,
      throwsA(isA<JsonRpcException>().having((e) => e.code, 'code', -32099)),
    );
    await connection.done;
    expect(connection.isClosed, isTrue);
  });
}
