import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;

import 'app_theme.dart';
import 'catppuccin.dart';

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

  /// the active theme is named by `config.json` in the folder above the root,
  /// where config shared with the rest of Nyaxis lives
  static Future<String> _activeName(Directory root) async {
    final config = File('${root.parent.path}\\config.json');
    final misplaced = File('${root.path}\\config.json');
    if (misplaced.existsSync() && !config.existsSync()) {
      await misplaced.rename(config.path);
    }
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

  /// the default theme ships every Catppuccin flavor; missing files and
  /// missing keys are filled in, so edited values are kept
  static Future<void> _seedPalettes(Directory dir) async {
    for (final entry in catppuccinPalettes.entries) {
      final file = File('${dir.path}\\palettes\\${entry.key}.json');
      var colors = <String, dynamic>{};
      try {
        if (file.existsSync()) {
          colors =
              jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        }
      } catch (e) {
        debugPrint('ThemeController: unreadable ${file.path} ($e)');
        continue;
      }
      final missing = entry.value.keys.where((k) => !colors.containsKey(k));
      if (missing.isNotEmpty || !file.existsSync()) {
        for (final key in missing) {
          colors[key] = entry.value[key];
        }
        await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(colors),
          flush: true,
        );
      }
    }
  }

  /// the default theme ships the bundled icons as files, so they can be seen
  /// and replaced; one is skipped when the folder already has any file by its
  /// name
  static Future<void> _seedIcons(Directory dir) async {
    final icons = Directory('${dir.path}\\icons');
    final existing = icons
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last.split('.').first)
        .toSet();
    for (final name in const [
      'minimize',
      'maximize',
      'restore',
      'close',
      'sidebar-closed',
      'sidebar-open',
      'add',
      'checkmark',
    ]) {
      if (!existing.contains(name)) {
        await File('${icons.path}\\$name.svg').writeAsString(
          await rootBundle.loadString('assets/icons/$name/$name-16.svg'),
          flush: true,
        );
      }
    }
  }

  static const _bundledFonts = {
    'Fredoka': 'assets/fonts/Fredoka-VariableFont.ttf',
    'JetBrainsMono': 'assets/fonts/JetBrainsMono-VariableFont.ttf',
  };

  static const _fontExtensions = ['ttf', 'otf'];

  /// the default theme ships the bundled fonts as files, named after their
  /// family, so they can be seen and replaced
  static Future<void> _seedFonts(Directory dir) async {
    final fonts = Directory('${dir.path}\\fonts');
    final existing = fonts
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last.split('.').first)
        .toSet();
    for (final entry in _bundledFonts.entries) {
      if (!existing.contains(entry.key)) {
        final data = await rootBundle.load(entry.value);
        await File('${fonts.path}\\${entry.key}.ttf').writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
    }
  }

  /// every font file in the theme's `fonts` folder is registered under its
  /// file name; a bundled family the theme doesn't provide is loaded from the
  /// app, so the defaults always resolve
  static Future<void> _registerFonts(Directory? dir) async {
    final loaded = <String>{};
    final folder = dir == null ? null : Directory('${dir.path}\\fonts');
    if (folder != null && folder.existsSync()) {
      for (final file in folder.listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last;
        final dot = name.lastIndexOf('.');
        if (dot <= 0 ||
            !_fontExtensions.contains(name.substring(dot + 1).toLowerCase())) {
          continue;
        }
        final family = name.substring(0, dot);
        try {
          final bytes = await file.readAsBytes();
          final loader = FontLoader(family)
            ..addFont(Future.value(ByteData.sublistView(bytes)));
          await loader.load();
          loaded.add(family);
        } catch (e) {
          debugPrint('ThemeController: unreadable font ${file.path} ($e)');
        }
      }
    }
    for (final entry in _bundledFonts.entries) {
      if (!loaded.contains(entry.key)) {
        final loader = FontLoader(entry.key)
          ..addFont(rootBundle.load(entry.value));
        await loader.load();
      }
    }
  }

  static Future<ThemeController> load() async {
    final controller = await _loadTheme();
    await _registerFonts(_themeDirectory);
    return controller;
  }

  static Future<ThemeController> _loadTheme() async {
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
      await Directory('${dir.path}\\fonts').create(recursive: true);
      if (name == _defaultName) {
        await _seedPalettes(dir);
        await _seedIcons(dir);
        await _seedFonts(dir);
      }
      _themeDirectory = dir;

      file = File('${dir.path}\\theme.json');
      final json = file.existsSync()
          ? jsonDecode(await file.readAsString()) as Map<String, dynamic>
          : <String, dynamic>{};
      // a theme from before palettes names none, and keeps its own colors
      final paletteName =
          _safeName(json['palette']) ??
          (json.containsKey('background') ? _defaultName : defaultPaletteName);

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
      'titleBar': _hex(t.titleBar),
      'surface': _hex(t.surface),
      'border': _hex(t.border),
      'textPrimary': _hex(t.textPrimary),
      'textDim': _hex(t.textDim),
      'accent': _hex(t.accent),
      'red': _hex(t.red),
      'lineNumber': _hex(t.lineNumber),
      'selection': _hex(t.selection),
      'hover': _hex(t.hover),
      'active': _hex(t.active),
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
    });
  }

  static Object _num(double v) => v % 1 == 0 ? v.toInt() : v;

  static String _hex(Color c) {
    return '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }
}
