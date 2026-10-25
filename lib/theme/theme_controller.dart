import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import 'app_theme.dart';

class ThemeController extends ValueNotifier<AppTheme> {
  ThemeController(super.value);

  /// null when APPDATA is unavailable; defaults are used then.
  static File? get _configFile {
    final appData = Platform.environment['APPDATA'];
    if (appData == null) {
      return null;
    }
    return File('$appData\\Nyaxis\\ui\\theme.json');
  }

  static Future<ThemeController> load() async {
    final file = _configFile;
    if (file == null) {
      return ThemeController(const AppTheme());
    }

    try {
      if (!file.existsSync()) {
        await file.parent.create(recursive: true);
        await file.writeAsString(_serialize(const AppTheme()), flush: true);
        return ThemeController(const AppTheme());
      }
      final theme = AppTheme.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
      return ThemeController(theme);
    } catch (e) {
      debugPrint(
        'ThemeController.load: unreadable ${file.path}, using defaults ($e)',
      );
      return ThemeController(const AppTheme());
    }
  }

  void setCornerRadius(double radius) =>
      value = value.copyWith(cornerRadius: radius);

  static String _serialize(AppTheme t) {
    return const JsonEncoder.withIndent('  ').convert({
      'cornerRadius': _num(t.cornerRadius),
      'borderWidth': _num(t.borderWidth),
      'fontFamily': t.fontFamily,
      'monospaceFontFamily': t.monospaceFontFamily,
      'fontSize': {
        'title': _num(t.fontSizeTitle),
        'heading': _num(t.fontSizeHeading),
        'body': _num(t.fontSizeBody),
        'caption': _num(t.fontSizeCaption),
      },
      'background': _hex(t.background),
      'border': _hex(t.border),
      'textPrimary': _hex(t.textPrimary),
      'textDim': _hex(t.textDim),
      'accent': _hex(t.accent),
    });
  }

  static Object _num(double v) => v % 1 == 0 ? v.toInt() : v;

  static String _hex(Color c) {
    return '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }
}
