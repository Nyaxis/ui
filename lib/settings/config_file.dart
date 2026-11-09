import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// `config.json` in `%APPDATA%\Nyaxis`, where the settings shared with the
/// rest of Nyaxis live. a write keeps everything it does not own, and a file
/// that cannot be read is never overwritten
class ConfigFile {
  ConfigFile(this.file);

  /// null when APPDATA is unavailable, in which case nothing is read or saved
  factory ConfigFile.user() {
    final appData = Platform.environment['APPDATA'];
    return ConfigFile(
      appData == null ? null : File('$appData\\Nyaxis\\config.json'),
    );
  }

  final File? file;

  /// writes go one after another, so two changes never read the same file
  var _queue = Future<void>.value();

  /// the parsed file, empty when it is missing, and null when it is unreadable
  Future<Map<String, dynamic>?> read() async {
    final file = this.file;
    if (file == null || !file.existsSync()) {
      return {};
    }
    try {
      final json = jsonDecode(await file.readAsString());
      return json is Map<String, dynamic> ? json : null;
    } catch (e) {
      debugPrint('ConfigFile: unreadable ${file.path} ($e)');
      return null;
    }
  }

  /// waits until the changes made so far are written
  Future<void> flush() => _queue;

  /// lets [change] edit the file's content, and writes it back
  Future<void> update(void Function(Map<String, dynamic> json) change) {
    return _queue = _queue.then((_) async {
      final file = this.file;
      final json = await read();
      if (file == null || json == null) {
        return;
      }
      change(json);
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(json),
          flush: true,
        );
      } catch (e) {
        debugPrint('ConfigFile: cannot save ${file.path} ($e)');
      }
    });
  }
}
