import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import 'app_theme.dart';

class ThemeController extends ValueNotifier<AppTheme> {
  ThemeController(super.value);

  static const _defaultName = 'default';

  /// null when APPDATA is unavailable, in which case defaults are used
  static Directory? get _root {
    final appData = Platform.environment['APPDATA'];
    return appData == null ? null : Directory('$appData\\Nyaxis\\ui');
  }

  static Directory? _themeDirectory;

  /// the active theme's folder: theme.json and an icons folder live in it, so
  /// the whole folder can be shared as one theme
  static Directory? get directory => _themeDirectory;

  /// names are used in paths, so anything that could escape its folder is
  /// rejected
  static String? _safeName(Object? name) {
    if (name is String &&
        name.isNotEmpty &&
        !name.contains(RegExp(r'[\\/:]')) &&
        name != '..') {
      return name;
    }
    return null;
  }

  /// the active theme is named by `config.json` in the root
  static Future<String> _activeName(Directory root) async {
    final config = File('${root.path}\\config.json');
    try {
      if (config.existsSync()) {
        final json = jsonDecode(await config.readAsString());
        final name = _safeName(
          json is Map<String, dynamic> ? json['theme'] : null,
        );
        if (name != null) {
          return name;
        }
      }
    } catch (e) {
      debugPrint('ThemeController: unreadable ${config.path} ($e)');
    }
    await config.writeAsString(
      const JsonEncoder.withIndent('  ').convert({'theme': _defaultName}),
      flush: true,
    );
    return _defaultName;
  }

  /// moves the single-file theme from before theme folders into the default one
  static Future<void> _migrateLegacy(Directory root, Directory dir) async {
    final legacy = File('${root.path}\\theme.json');
    final target = File('${dir.path}\\theme.json');
    if (legacy.existsSync() && !target.existsSync()) {
      await dir.create(recursive: true);
      await legacy.rename(target.path);
    }
  }

  static Future<ThemeController> load() async {
    final root = _root;
    if (root == null) {
      return ThemeController(const AppTheme());
    }

    File? file;
    try {
      await root.create(recursive: true);
      final name = await _activeName(root);
      final dir = Directory('${root.path}\\themes\\$name');
      await _migrateLegacy(root, dir);
      await Directory('${dir.path}\\icons').create(recursive: true);
      await Directory('${dir.path}\\palettes').create(recursive: true);
      _themeDirectory = dir;

      file = File('${dir.path}\\theme.json');
      final json = file.existsSync()
          ? jsonDecode(await file.readAsString()) as Map<String, dynamic>
          : <String, dynamic>{};
      final paletteName = _safeName(json['palette']) ?? _defaultName;

      // a theme from before palettes carries its colors itself, so they seed
      // the palette file
      final paletteFile = File('${dir.path}\\palettes\\$paletteName.json');
      final palette = paletteFile.existsSync()
          ? jsonDecode(await paletteFile.readAsString()) as Map<String, dynamic>
          : null;

      final theme = AppTheme.fromJson(json, palette: palette);
      await file.writeAsString(_serialize(theme, paletteName), flush: true);
      await paletteFile.writeAsString(_serializePalette(theme), flush: true);
      return ThemeController(theme);
    } catch (e) {
      debugPrint(
        'ThemeController.load: unreadable ${file?.path ?? root.path}, '
        'using defaults ($e)',
      );
      return ThemeController(const AppTheme());
    }
  }

  void setCornerRadius(double radius) =>
      value = value.copyWith(cornerRadius: radius);

  static String _serializePalette(AppTheme t) {
    return const JsonEncoder.withIndent('  ').convert({
      'background': _hex(t.background),
      'border': _hex(t.border),
      'textPrimary': _hex(t.textPrimary),
      'textDim': _hex(t.textDim),
      'accent': _hex(t.accent),
    });
  }

  static String _serialize(AppTheme t, String paletteName) {
    return const JsonEncoder.withIndent('  ').convert({
      'palette': paletteName,
      'cornerRadius': _num(t.cornerRadius),
      'roundingPower': _num(t.roundingPower),
      'borderWidth': _num(t.borderWidth),
      'fontFamily': t.fontFamily,
      'monospaceFontFamily': t.monospaceFontFamily,
      'fontSize': {
        'title': _num(t.fontSizeTitle),
        'heading': _num(t.fontSizeHeading),
        'body': _num(t.fontSizeBody),
        'caption': _num(t.fontSizeCaption),
      },
      'backgroundOpacity': _num(t.backgroundOpacity),
      'acrylic': t.acrylic,
      'icons': {'size': _num(t.iconSize)},
    });
  }

  static Object _num(double v) => v % 1 == 0 ? v.toInt() : v;

  static String _hex(Color c) {
    return '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }
}
