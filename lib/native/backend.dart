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
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => debugPrint('backend: $line'));
      process.stderr.transform(utf8.decoder).listen(debugPrint);
      return Backend._(process);
    } catch (e) {
      debugPrint('backend: $e');
      return Backend._(null);
    }
  }

  void _send(Map<String, Object?> command) =>
      _process?.stdin.writeln(jsonEncode(command));

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

  void dispose() => shutdown().ignore();
}
