import 'dart:convert';

import 'package:flutter/services.dart';

/// a Zed icon theme: which icon a file extension gets, and where its svg is
class FileIconTheme {
  FileIconTheme._(this._suffixes, this._paths, this._fallback);

  static const _folder = 'assets/file_icons';

  /// the icon theme named [name] in the bundled `catppuccin-icons.json`, null
  /// when it has none
  static Future<FileIconTheme?> load(String name) async {
    try {
      final json = jsonDecode(
        await rootBundle.loadString('$_folder/catppuccin-icons.json'),
      ) as Map<String, dynamic>;
      for (final theme in json['themes'] as List) {
        if (theme is! Map<String, dynamic> || theme['name'] != name) {
          continue;
        }
        final folder = theme['directory_icons']['collapsed'] as String;
        return FileIconTheme._(
          (theme['file_suffixes'] as Map).cast<String, String>(),
          {
            for (final entry in (theme['file_icons'] as Map).entries)
              entry.key as String: entry.value['path'] as String,
          },
          // the theme names no plain file icon, but keeps it beside the folder
          folder.replaceFirst('_folder.svg', '_file.svg'),
        );
      }
    } catch (e) {
      // the picker works without icons
    }
    return null;
  }

  final Map<String, String> _suffixes;
  final Map<String, String> _paths;
  final String _fallback;

  /// the asset of the icon for files ending in [extension], without the dot;
  /// an extension the theme has no icon for gets its plain file icon
  String assetFor(String extension) {
    final path = _paths[_suffixes[extension]] ?? _fallback;
    return '$_folder/${path.substring(2)}';
  }
}
