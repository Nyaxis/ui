import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// the C# backend, a child process spoken to in json lines over stdio; every
/// call does nothing while it is not running
class Backend {
  Backend._(this._process);

  final Process? _process;
  Future<void>? _shutdown;

  /// `NYAXIS_HOST` overrides the host's path, for running from the backend's
  /// build output
  static Future<Backend> start() async {
    final path =
        Platform.environment['NYAXIS_HOST'] ??
        '${File(Platform.resolvedExecutable).parent.path}\\host\\Nyaxis.Host.exe';
    if (!File(path).existsSync()) {
      debugPrint('backend: unavailable ($path)');
      return Backend._(null);
    }
    try {
      final process = await Process.start(path, const []);
      final backend = Backend._(process);
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(backend._onLine);
      process.stderr.transform(utf8.decoder).listen(debugPrint);
      return backend;
    } catch (e) {
      debugPrint('backend: $e');
      return Backend._(null);
    }
  }

  final _lsp = StreamController<String>.broadcast();

  /// what the language server sends, one json-rpc message to an event
  Stream<String> get lspMessages => _lsp.stream;

  void _onLine(String line) {
    try {
      final reply = jsonDecode(line);
      if (reply is Map && reply['evt'] == 'lsp' && reply['detail'] is String) {
        _lsp.add(reply['detail'] as String);
        return;
      }
    } on FormatException {
      // not a reply; it is logged like any other line
    }
    debugPrint('backend: $line');
  }

  void _send(Map<String, Object?> command) =>
      _process?.stdin.writeln(jsonEncode(command));

  /// starts the backend's language server, which it refuses until licensed
  void lspStart() => _send({'cmd': 'lsp_start'});

  /// one json-rpc message for the language server
  void lspSend(String message) => _send({'cmd': 'lsp', 'payload': message});

  void inject() => _send({'cmd': 'inject'});

  void execute(String script) => _send({'cmd': 'execute', 'script': script});

  /// the name of the script being edited, or null when there is none
  void presence(String? file) => _send({'cmd': 'presence', 'file': file});

  /// closes the backend's stdin so it can clear its discord presence and exit,
  /// killing it only if it has not exited after a second
  Future<void> shutdown() => _shutdown ??= _stop();

  Future<void> _stop() async {
    final process = _process;
    if (process == null) return;
    process.stdin.close().ignore();
    await process.exitCode.timeout(
      const Duration(seconds: 1),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
  }

  void dispose() {
    shutdown().ignore();
    _lsp.close().ignore();
  }
}
