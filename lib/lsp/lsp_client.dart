import 'dart:async';
import 'dart:io';

import 'json_rpc.dart';

/// how bad a diagnostic is, as the protocol numbers it
enum DiagnosticSeverity {
  error,
  warning,
  information,
  hint;

  static DiagnosticSeverity fromNumber(Object? number) => switch (number) {
    1 => error,
    2 => warning,
    3 => information,
    4 => hint,
    // a server that does not say means an error
    _ => error,
  };
}

/// a place in a text, as the protocol has it: a row, and a column in UTF-16
/// code units, which is how Dart indexes a string too
class LspPosition {
  const LspPosition(this.line, this.character);

  final int line;
  final int character;

  Map<String, int> toJson() => {'line': line, 'character': character};

  @override
  bool operator ==(Object other) =>
      other is LspPosition &&
      other.line == line &&
      other.character == character;

  @override
  int get hashCode => Object.hash(line, character);

  @override
  String toString() => '$line:$character';
}

class LspRange {
  const LspRange(this.start, this.end);

  final LspPosition start;
  final LspPosition end;

  Map<String, Object> toJson() => {
    'start': start.toJson(),
    'end': end.toJson(),
  };

  static LspRange? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final start = _position(json['start']);
    final end = _position(json['end']);
    return start == null || end == null ? null : LspRange(start, end);
  }

  static LspPosition? _position(Object? json) {
    if (json is! Map) {
      return null;
    }
    final line = json['line'];
    final character = json['character'];
    return line is int && character is int
        ? LspPosition(line, character)
        : null;
  }

  @override
  bool operator ==(Object other) =>
      other is LspRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '$start-$end';
}

class LspDiagnostic {
  const LspDiagnostic({
    required this.range,
    required this.severity,
    required this.message,
    this.source,
    this.code,
    this.codeHref,
    this.unnecessary = false,
  });

  final LspRange range;
  final DiagnosticSeverity severity;
  final String message;
  final String? source;
  final String? code;

  /// where the server says the code is explained
  final String? codeHref;

  /// whether the server tagged it as code that is not needed, such as a local
  /// that is never used
  final bool unnecessary;

  /// the number of the tag for unnecessary code in the protocol
  static const unnecessaryTag = 1;

  static LspDiagnostic? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final range = LspRange.fromJson(json['range']);
    final message = json['message'];
    if (range == null || message is! String) {
      return null;
    }
    return LspDiagnostic(
      range: range,
      severity: DiagnosticSeverity.fromNumber(json['severity']),
      message: message,
      source: json['source'] as String?,
      code: json['code']?.toString(),
      codeHref: switch (json['codeDescription']) {
        {'href': final String href} => href,
        _ => null,
      },
      unnecessary: switch (json['tags']) {
        final List tags => tags.contains(unnecessaryTag),
        _ => false,
      },
    );
  }
}

/// the diagnostics that the server has for a document, all of them: a new list
/// replaces what it sent before
class PublishedDiagnostics {
  const PublishedDiagnostics(this.uri, this.diagnostics, this.version);

  final String uri;
  final List<LspDiagnostic> diagnostics;
  final int? version;
}

/// how the server wants to be told about changes to the text
enum TextSync { none, full, incremental }

/// a client of a language server: it starts the conversation, tells the server
/// about the documents that are open, and says what the server sends back
class LspClient {
  LspClient(this.connection, {this._process}) {
    connection.onRequest = _onRequest;
    _subscription = connection.notifications.listen(_onNotification);
  }

  /// starts [executable] and talks to it over its standard input and output
  static Future<LspClient> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
    // what the server writes to its error output is its log, which has to be
    // read or it can stop the server when the pipe is full
    unawaited(process.stderr.drain<void>());
    return LspClient(
      JsonRpcConnection(process.stdout, process.stdin),
      process: process,
    );
  }

  final JsonRpcConnection connection;
  final Process? _process;
  late final StreamSubscription<JsonRpcNotification> _subscription;
  final _diagnostics = StreamController<PublishedDiagnostics>.broadcast();

  Map<String, Object?> _serverCapabilities = const {};
  bool _initialized = false;

  Stream<PublishedDiagnostics> get diagnostics => _diagnostics.stream;

  bool get isInitialized => _initialized;

  Map<String, Object?> get serverCapabilities => _serverCapabilities;

  /// how the server takes changes to the text
  TextSync get textSync {
    final sync = _serverCapabilities['textDocumentSync'];
    final kind = sync is Map ? sync['change'] : sync;
    return switch (kind) {
      1 => TextSync.full,
      2 => TextSync.incremental,
      _ => TextSync.none,
    };
  }

  /// the first thing that is said: what the client can do, and the answer of
  /// what the server can
  Future<void> initialize({
    String? rootUri,
    Object? initializationOptions,
  }) async {
    final result = await connection.request('initialize', {
      'processId': pid,
      'clientInfo': {'name': 'Nyaxis'},
      'rootUri': rootUri,
      'capabilities': _clientCapabilities,
      'initializationOptions': ?initializationOptions,
    });
    if (result is Map && result['capabilities'] is Map) {
      _serverCapabilities = Map<String, Object?>.from(
        result['capabilities'] as Map,
      );
    }
    connection.notify('initialized', <String, Object?>{});
    _initialized = true;
  }

  static const _clientCapabilities = <String, Object?>{
    'textDocument': {
      'synchronization': {
        'dynamicRegistration': false,
        'willSave': false,
        'didSave': false,
      },
      'publishDiagnostics': {
        'relatedInformation': false,
        'versionSupport': true,
        // unnecessary and deprecated
        'tagSupport': {
          'valueSet': [1, 2],
        },
      },
    },
    'workspace': {'configuration': true, 'workspaceFolders': false},
  };

  void didOpen(String uri, String languageId, int version, String text) {
    connection.notify('textDocument/didOpen', {
      'textDocument': {
        'uri': uri,
        'languageId': languageId,
        'version': version,
        'text': text,
      },
    });
  }

  /// [changes] are applied one after the other, each to the text that the one
  /// before made, as the protocol has it
  void didChange(String uri, int version, List<Map<String, Object?>> changes) {
    connection.notify('textDocument/didChange', {
      'textDocument': {'uri': uri, 'version': version},
      'contentChanges': changes,
    });
  }

  void didClose(String uri) {
    connection.notify('textDocument/didClose', {
      'textDocument': {'uri': uri},
    });
  }

  Future<Object?> _onRequest(String method, Object? params) async {
    switch (method) {
      case 'workspace/configuration':
        // the server asks for settings for each item, and gets none
        final items = params is Map ? params['items'] : null;
        return [for (final _ in items is List ? items : const []) null];
      case 'client/registerCapability':
      case 'client/unregisterCapability':
      case 'window/workDoneProgress/create':
        return null;
    }
    throw const JsonRpcException(
      JsonRpcException.methodNotFound,
      'not handled',
    );
  }

  void _onNotification(JsonRpcNotification notification) {
    if (notification.method != 'textDocument/publishDiagnostics') {
      return;
    }
    final params = notification.params;
    if (params is! Map || params['uri'] is! String) {
      return;
    }
    final list = params['diagnostics'];
    _diagnostics.add(
      PublishedDiagnostics(params['uri'] as String, [
        if (list is List)
          for (final item in list) ?LspDiagnostic.fromJson(item),
      ], params['version'] as int?),
    );
  }

  /// ends the conversation, and the server with it
  Future<void> shutdown() async {
    if (_initialized && !connection.isClosed) {
      try {
        await connection
            .request('shutdown')
            .timeout(const Duration(seconds: 2));
        connection.notify('exit');
      } on Object {
        // it is going away either way
      }
    }
    await _subscription.cancel();
    await connection.close();
    await _diagnostics.close();
    _process?.kill();
  }
}
