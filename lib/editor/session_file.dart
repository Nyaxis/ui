import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'text_encoding.dart';

/// a tab with unsaved changes, as kept for the next start
class SavedTab {
  const SavedTab({
    required this.name,
    required this.file,
    required this.encoding,
    required this.text,
  });

  final String name;

  /// null for an untitled tab
  final String? file;
  final TextEncoding encoding;

  /// what the tab held, which the file on disk does not
  final String text;
}

/// the unsaved tabs, in a json file that is replaced whole
class SessionFile {
  SessionFile(this.file);

  final File file;

  /// empty when there is no file, or it cannot be read
  Future<List<SavedTab>> read() async {
    try {
      if (!file.existsSync()) {
        return [];
      }
      final json = jsonDecode(await file.readAsString()) as Map;
      return [
        for (final tab in json['tabs'] as List)
          SavedTab(
            name: tab['name'] as String,
            file: tab['file'] as String?,
            encoding:
                TextEncoding.values.asNameMap()[tab['encoding']] ??
                TextEncoding.values.first,
            text: tab['text'] as String,
          ),
      ];
    } catch (e) {
      debugPrint('SessionFile: unreadable ${file.path} ($e)');
      return [];
    }
  }

  /// written beside the file and renamed over it, so a crash in the middle
  /// leaves the old session instead of half of the new one
  Future<void> write(List<SavedTab> tabs) async {
    try {
      final temporary = File('${file.path}.tmp');
      await file.parent.create(recursive: true);
      await temporary.writeAsString(
        jsonEncode({
          'tabs': [
            for (final tab in tabs)
              {
                'name': tab.name,
                'file': tab.file,
                'encoding': tab.encoding.name,
                'text': tab.text,
              },
          ],
        }),
        flush: true,
      );
      await temporary.rename(file.path);
    } catch (e) {
      debugPrint('SessionFile: cannot write ${file.path} ($e)');
    }
  }
}
