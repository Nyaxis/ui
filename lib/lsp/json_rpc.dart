import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// what a server answers a request with when it fails
class JsonRpcException implements Exception {
  const JsonRpcException(this.code, this.message);

  final int code;
  final String message;

  /// the request was not answered because the connection ended
  static const closed = JsonRpcException(-32099, 'the connection is closed');

  /// the server has no such method
  static const methodNotFound = -32601;

  @override
  String toString() => 'JsonRpcException($code, $message)';
}

/// a message that has no answer
class JsonRpcNotification {
  const JsonRpcNotification(this.method, this.params);

  final String method;
  final Object? params;
}

/// JSON-RPC 2.0 as the language server protocol sends it: each message is a
/// JSON text after a `Content-Length` header, over a pair of byte streams
class JsonRpcConnection {
  JsonRpcConnection(Stream<List<int>> input, this._output) : _write = null {
    _subscription = input.listen(_onData, onDone: _onDone, onError: (_) {});
  }

  /// over a channel that carries each message whole, so that no header is
  /// needed: [input] has one message per event, and [write] sends one
  JsonRpcConnection.messages(Stream<String> input, void Function(String) write)
    : _output = null,
      _write = write {
    _subscription = input.listen(_onMessage, onDone: _onDone, onError: (_) {});
  }

  final StreamSink<List<int>>? _output;
  final void Function(String)? _write;
  late final StreamSubscription<Object?> _subscription;
  final _pending = <int, Completer<Object?>>{};
  final _notifications = StreamController<JsonRpcNotification>.broadcast();
  final _done = Completer<void>();
  int _nextId = 1;
  bool _closed = false;

  /// what the server asks for, such as its settings. null for a method that
  /// is not handled, which the server is told
  Future<Object?> Function(String method, Object? params)? onRequest;

  Stream<JsonRpcNotification> get notifications => _notifications.stream;

  /// completes when the server ends the connection
  Future<void> get done => _done.future;

  bool get isClosed => _closed;

  /// asks the server, and gives what it answers; an error is thrown as a
  /// [JsonRpcException]
  Future<Object?> request(String method, [Object? params]) {
    if (_closed) {
      return Future.error(JsonRpcException.closed);
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': ?params});
    return completer.future;
  }

  void notify(String method, [Object? params]) {
    if (_closed) {
      return;
    }
    _send({'jsonrpc': '2.0', 'method': method, 'params': ?params});
  }

  Future<void> close() async {
    if (!_closed) {
      _end();
    }
    await _subscription.cancel();
    try {
      await _output?.close();
    } on Object {
      // the other end went away first
    }
  }

  void _send(Map<String, Object?> message) {
    try {
      final write = _write;
      if (write != null) {
        write(jsonEncode(message));
        return;
      }
      final body = utf8.encode(jsonEncode(message));
      final header = ascii.encode('Content-Length: ${body.length}\r\n\r\n');
      _output!.add(header);
      _output.add(body);
    } on Object {
      _end();
    }
  }

  // the bytes that came and are not a whole message yet
  Uint8List _buffer = Uint8List(0);

  void _onData(List<int> data) {
    final joined = Uint8List(_buffer.length + data.length)
      ..setAll(0, _buffer)
      ..setAll(_buffer.length, data);
    var start = 0;
    while (true) {
      final headerEnd = _indexOfHeaderEnd(joined, start);
      if (headerEnd < 0) {
        break;
      }
      final header = ascii.decode(
        joined.sublist(start, headerEnd),
        allowInvalid: true,
      );
      final length = _contentLength(header);
      final bodyStart = headerEnd + 4;
      if (length == null) {
        // not a message: go past the header and look for the next one
        start = bodyStart;
        continue;
      }
      if (joined.length - bodyStart < length) {
        break;
      }
      final body = utf8.decode(
        joined.sublist(bodyStart, bodyStart + length),
        allowMalformed: true,
      );
      start = bodyStart + length;
      _onMessage(body);
    }
    _buffer = Uint8List.sublistView(joined, start);
  }

  static int _indexOfHeaderEnd(Uint8List bytes, int from) {
    for (var i = from; i + 3 < bytes.length; i++) {
      if (bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  static int? _contentLength(String header) {
    for (final line in header.split('\r\n')) {
      final colon = line.indexOf(':');
      if (colon > 0 &&
          line.substring(0, colon).toLowerCase() == 'content-length') {
        return int.tryParse(line.substring(colon + 1).trim());
      }
    }
    return null;
  }

  void _onMessage(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return;
    }
    if (decoded is! Map) {
      return;
    }
    final id = decoded['id'];
    final method = decoded['method'];
    if (method is String) {
      if (id == null) {
        _notifications.add(JsonRpcNotification(method, decoded['params']));
      } else {
        unawaited(_answer(id, method, decoded['params']));
      }
    } else if (id is int) {
      final completer = _pending.remove(id);
      if (completer == null) {
        return;
      }
      final error = decoded['error'];
      if (error is Map) {
        completer.completeError(
          JsonRpcException(
            (error['code'] as num?)?.toInt() ?? 0,
            '${error['message']}',
          ),
        );
      } else {
        completer.complete(decoded['result']);
      }
    }
  }

  Future<void> _answer(Object id, String method, Object? params) async {
    final handler = onRequest;
    if (handler == null) {
      _send({
        'jsonrpc': '2.0',
        'id': id,
        'error': {
          'code': JsonRpcException.methodNotFound,
          'message': 'not handled: $method',
        },
      });
      return;
    }
    try {
      final result = await handler(method, params);
      _send({'jsonrpc': '2.0', 'id': id, 'result': result});
    } on JsonRpcException catch (e) {
      _send({
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': e.code, 'message': e.message},
      });
    } on Object catch (e) {
      _send({
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': -32603, 'message': '$e'},
      });
    }
  }

  void _onDone() => _end();

  void _end() {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final completer in _pending.values) {
      completer.completeError(JsonRpcException.closed);
    }
    _pending.clear();
    if (!_notifications.isClosed) {
      unawaited(_notifications.close());
    }
    if (!_done.isCompleted) {
      _done.complete();
    }
  }
}
