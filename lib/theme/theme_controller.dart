import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;

import '../settings/config_file.dart';
import 'app_theme.dart';
import 'catppuccin.dart';
import 'theme_library.dart';

class ThemeController extends ValueNotifier<AppTheme> {
  ThemeController(
    super.value, {
    this.palette = defaultPaletteName,
    @visibleForTesting Directory? directory,
    @visibleForTesting ConfigFile? config,
    this.persist = true,
  }) : _directory = directory ?? _themeDirectory,
       // a controller that is given a folder is not the one of the window, so it
       // does not touch the window's config unless it is given one
       _config = config ?? (directory == null ? ConfigFile.user() : null);

  /// where the theme in use is remembered
  final ConfigFile? _config;

  /// the name of the palette the colors come from, which also picks the icon
  /// theme
  String palette;

  /// the folder the theme is saved to, null when there is none and changes
  /// last only until the window closes
  Directory? _directory;

  /// false when the theme could not be read, so changes are not saved over
  /// the files that were
  final bool persist;

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
      final file = File(
        '${dir.path}${Platform.pathSeparator}palettes${Platform.pathSeparator}${entry.key}.json',
      );
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
    final icons = Directory('${dir.path}${Platform.pathSeparator}icons');
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
      'inject',
      'execute',
    ]) {
      if (!existing.contains(name)) {
        await File('${icons.path}${Platform.pathSeparator}$name.svg')
            .writeAsString(
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
    final fonts = Directory('${dir.path}${Platform.pathSeparator}fonts');
    final existing = fonts
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last.split('.').first)
        .toSet();
    for (final entry in _bundledFonts.entries) {
      if (!existing.contains(entry.key)) {
        final data = await rootBundle.load(entry.value);
        await File('${fonts.path}${Platform.pathSeparator}${entry.key}.ttf')
            .writeAsBytes(
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
    final folder = dir == null
        ? null
        : Directory('${dir.path}${Platform.pathSeparator}fonts');
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
      _themeDirectory = dir;
      file = File('${dir.path}\\theme.json');
      final (theme, paletteName) = await _readTheme(dir, name);
      return ThemeController(theme, palette: paletteName);
    } catch (e) {
      debugPrint(
        'ThemeController.load: unreadable ${file?.path ?? root.path}, '
        'using defaults ($e)',
      );
      // what could not be read is not written over
      return ThemeController(const AppTheme(), persist: false);
    }
  }

  /// the theme in [dir], named [name], and the palette it uses; the folder
  /// is filled in with what a theme has, and the files are written back
  /// complete
  static Future<(AppTheme, String)> _readTheme(
    Directory dir,
    String name,
  ) async {
    final s = Platform.pathSeparator;
    await Directory('${dir.path}${s}icons').create(recursive: true);
    await Directory('${dir.path}${s}palettes').create(recursive: true);
    await Directory('${dir.path}${s}fonts').create(recursive: true);
    if (name == _defaultName) {
      await _seedPalettes(dir);
      await _seedIcons(dir);
      await _seedFonts(dir);
    }

    final file = File('${dir.path}${s}theme.json');
    final json = file.existsSync()
        ? jsonDecode(await file.readAsString()) as Map<String, dynamic>
        : <String, dynamic>{};
    // a theme from before palettes names none, and keeps its own colors
    final paletteName =
        _safeName(json['palette']) ??
        (json.containsKey('background') ? _defaultName : defaultPaletteName);

    // a theme from before palettes carries its colors itself, so they seed
    // the palette file
    final paletteFile = File('${dir.path}${s}palettes$s$paletteName.json');
    final palette = paletteFile.existsSync()
        ? jsonDecode(await paletteFile.readAsString()) as Map<String, dynamic>
        : null;

    final theme = AppTheme.fromJson(json, palette: palette);
    await file.writeAsString(_serialize(theme, paletteName), flush: true);
    await paletteFile.writeAsString(_serializePalette(theme), flush: true);
    return (theme, paletteName);
  }

  /// the name of the theme in use, which is the name of its folder
  String get themeName => _directory?.path.split(RegExp(r'[\\/]')).last ?? '';

  ThemeLibrary? get _library {
    final dir = _directory;
    return dir == null ? null : ThemeLibrary(dir.parent);
  }

  /// the themes, `default` first
  List<String> get themes => _library?.themes() ?? [themeName];

  /// the palettes of the theme in use
  List<String> get palettes {
    final names = _library?.palettes(themeName);
    return names == null || names.isEmpty ? [palette] : names;
  }

  /// the fonts the theme has, which are the files in its `fonts` folder
  List<String> get fonts {
    final dir = _directory;
    final folder = dir == null
        ? null
        : Directory('${dir.path}${Platform.pathSeparator}fonts');
    if (folder == null || !folder.existsSync()) {
      return const [];
    }
    final names = <String>[];
    for (final file in folder.listSync().whereType<File>()) {
      final name = file.path.split(RegExp(r'[\\/]')).last;
      final dot = name.lastIndexOf('.');
      if (dot > 0 &&
          _fontExtensions.contains(name.substring(dot + 1).toLowerCase())) {
        names.add(name.substring(0, dot));
      }
    }
    return names..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  /// the theme in use is kept for the next start, in `config.json`
  Future<void> _remember(String name) =>
      _config?.update((json) => json['theme'] = name) ?? Future.value();

  /// moves to the theme named [name]: its colors, fonts and icons replace the
  /// ones in use. a font a theme has under the name of one already loaded
  /// takes a restart to show; returns whether the theme was found and read
  Future<bool> switchTheme(String name) async {
    final current = _directory;
    if (current == null || _safeName(name) == null) {
      return false;
    }
    final dir = Directory(
      '${current.parent.path}${Platform.pathSeparator}$name',
    );
    if (!dir.existsSync()) {
      return false;
    }
    try {
      await _flushPalette();
      final (theme, paletteName) = await _readTheme(dir, name);
      await _registerFonts(dir);
      _themeDirectory = dir;
      _directory = dir;
      palette = paletteName;
      value = theme;
      await _remember(name);
      return true;
    } catch (e) {
      debugPrint('ThemeController: cannot switch to the theme $name ($e)');
      return false;
    }
  }

  /// the default theme comes with the app, so it is not renamed or removed
  bool get canChangeTheme => themeName != ThemeLibrary.defaultTheme;

  /// why [name] cannot be the name of a theme, null when it can; with
  /// [renaming] the theme in use may keep its own name
  String? validateThemeName(String name, {bool renaming = false}) {
    final library = _library;
    if (library == null) {
      return 'Themes cannot be saved on this computer';
    }
    return ThemeLibrary.checkName(
      name,
      library.themes(),
      renaming: renaming ? themeName : null,
    );
  }

  /// copies the theme in use as [name], and moves to the copy. returns why it
  /// could not, null when it did
  Future<String?> createTheme(String name) async {
    final library = _library;
    final error = validateThemeName(name);
    if (library == null || error != null) {
      return error ?? 'Themes cannot be saved on this computer';
    }
    final created = name.trim();
    try {
      await _flushPalette();
      await library.copyTheme(themeName, created);
    } on FileSystemException catch (e) {
      return 'The theme could not be created: ${e.message}';
    }
    return await switchTheme(created)
        ? null
        : 'The new theme could not be opened';
  }

  Future<String?> renameTheme(String name) async {
    final library = _library;
    final from = themeName;
    if (library == null || !canChangeTheme) {
      return 'The default theme cannot be renamed';
    }
    final error = validateThemeName(name, renaming: true);
    if (error != null) {
      return error;
    }
    final renamed = name.trim();
    if (renamed == from) {
      return null;
    }
    try {
      await _flushPalette();
      await library.renameTheme(from, renamed);
    } on FileSystemException catch (e) {
      return 'The theme could not be renamed: ${e.message}';
    }
    final dir = library.theme(renamed);
    _themeDirectory = dir;
    _directory = dir;
    await _remember(renamed);
    notifyListeners();
    return null;
  }

  /// removes the theme in use, after moving to the default one, or to another
  /// when there is none
  Future<String?> deleteTheme() async {
    final library = _library;
    final name = themeName;
    if (library == null || !canChangeTheme) {
      return 'The default theme cannot be removed';
    }
    final others = library.themes().where((t) => t != name).toList();
    final target = others.contains(ThemeLibrary.defaultTheme)
        ? ThemeLibrary.defaultTheme
        : others.firstOrNull;
    if (target == null || !await switchTheme(target)) {
      return 'There is no other theme to move to first';
    }
    try {
      await library.deleteTheme(name);
    } on FileSystemException catch (e) {
      return 'The theme could not be removed: ${e.message}';
    }
    notifyListeners();
    return null;
  }

  String? validatePaletteName(String name, {bool renaming = false}) {
    if (_library == null) {
      return 'Palettes cannot be saved on this computer';
    }
    return ThemeLibrary.checkName(
      name,
      palettes,
      renaming: renaming ? palette : null,
    );
  }

  /// a palette with the colors in use, named [name], which is moved to
  Future<String?> createPalette(String name) async {
    final library = _library;
    final error = validatePaletteName(name);
    if (library == null || error != null) {
      return error ?? 'Palettes cannot be saved on this computer';
    }
    final created = name.trim();
    try {
      await _flushPalette();
      await library.writePalette(themeName, created, _paletteJson(value));
    } on FileSystemException catch (e) {
      return 'The palette could not be created: ${e.message}';
    }
    palette = created;
    notifyListeners();
    await _save();
    return null;
  }

  Future<String?> renamePalette(String name) async {
    final library = _library;
    if (library == null) {
      return 'Palettes cannot be saved on this computer';
    }
    final error = validatePaletteName(name, renaming: true);
    if (error != null) {
      return error;
    }
    final renamed = name.trim();
    if (renamed == palette) {
      return null;
    }
    try {
      await _flushPalette();
      await library.renamePalette(themeName, palette, renamed);
    } on FileSystemException catch (e) {
      return 'The palette could not be renamed: ${e.message}';
    }
    palette = renamed;
    notifyListeners();
    await _save();
    return null;
  }

  /// removes the palette in use, after moving to another; a theme keeps at
  /// least one
  Future<String?> deletePalette() async {
    final library = _library;
    final name = palette;
    final others = palettes.where((p) => p != name).toList();
    if (library == null || others.isEmpty) {
      return 'A theme needs at least one palette';
    }
    await setPalette(others.first);
    if (palette == name) {
      return 'Another palette could not be used first';
    }
    try {
      await library.deletePalette(themeName, name);
    } on FileSystemException catch (e) {
      return 'The palette could not be removed: ${e.message}';
    }
    notifyListeners();
    return null;
  }

  /// takes the colors of the palette [name] and keeps the rest of the theme;
  /// a palette that is missing or unreadable changes nothing
  Future<void> setPalette(String name) async {
    final library = _library;
    if (library == null || _safeName(name) == null) {
      return;
    }
    await _flushPalette();
    final colors = await library.readPalette(themeName, name);
    if (colors == null) {
      debugPrint('ThemeController: cannot use the palette $name');
      return;
    }
    final themed = AppTheme.fromJson(const {}, palette: colors);
    palette = name;
    value = value.copyWith(
      background: themed.background,
      titleBar: themed.titleBar,
      surface: themed.surface,
      border: themed.border,
      textPrimary: themed.textPrimary,
      textDim: themed.textDim,
      accent: themed.accent,
      red: themed.red,
      lineNumber: themed.lineNumber,
      selection: themed.selection,
      hover: themed.hover,
      active: themed.active,
    );
    await _save();
  }

  /// the colors of a palette, by the key they have in its file and the name
  /// they are shown under
  static const paletteRoles = <(String, String)>[
    ('background', 'Background'),
    ('titleBar', 'Title bar'),
    ('surface', 'Surface'),
    ('border', 'Border'),
    ('textPrimary', 'Text'),
    ('textDim', 'Dim text'),
    ('accent', 'Accent'),
    ('red', 'Danger'),
    ('lineNumber', 'Line numbers'),
    ('selection', 'Selection'),
    ('hover', 'Hover'),
    ('active', 'Pressed'),
  ];

  Color colorOf(String role) => switch (role) {
    'background' => value.background,
    'titleBar' => value.titleBar,
    'surface' => value.surface,
    'border' => value.border,
    'textPrimary' => value.textPrimary,
    'textDim' => value.textDim,
    'accent' => value.accent,
    'red' => value.red,
    'lineNumber' => value.lineNumber,
    'selection' => value.selection,
    'hover' => value.hover,
    'active' => value.active,
    _ => throw ArgumentError.value(role, 'role'),
  };

  /// changes one color of the palette in use, which is saved as it is
  void setColor(String role, Color color) {
    final opaque = color.withValues(alpha: 1);
    value = switch (role) {
      'background' => value.copyWith(background: opaque),
      'titleBar' => value.copyWith(titleBar: opaque),
      'surface' => value.copyWith(surface: opaque),
      'border' => value.copyWith(border: opaque),
      'textPrimary' => value.copyWith(textPrimary: opaque),
      'textDim' => value.copyWith(textDim: opaque),
      'accent' => value.copyWith(accent: opaque),
      'red' => value.copyWith(red: opaque),
      'lineNumber' => value.copyWith(lineNumber: opaque),
      'selection' => value.copyWith(selection: opaque),
      'hover' => value.copyWith(hover: opaque),
      'active' => value.copyWith(active: opaque),
      _ => throw ArgumentError.value(role, 'role'),
    };
    // a drag through the picker changes it many times a second
    _paletteTimer?.cancel();
    _paletteTimer = Timer(_paletteDelay, () => unawaited(_savePalette()));
  }

  static const _paletteDelay = Duration(milliseconds: 250);
  Timer? _paletteTimer;

  /// writes a color that is waiting to be saved now, to the palette it was
  /// changed in, and waits for everything that is being written
  Future<void> _flushPalette() async {
    final timer = _paletteTimer;
    if (timer != null && timer.isActive) {
      timer.cancel();
      await _savePalette();
    }
    await _saves;
  }

  @override
  void dispose() {
    _paletteTimer?.cancel();
    super.dispose();
  }

  /// one write at a time, so a quick run of changes cannot leave a file with
  /// an older one
  Future<void> _enqueue(Future<void> Function() write) {
    return _saves = _saves.then((_) async {
      try {
        await write();
      } catch (e) {
        debugPrint('ThemeController: cannot save the theme ($e)');
      }
    });
  }

  var _saves = Future<void>.value();

  /// every change is written to the theme's `theme.json`, which keeps no
  /// other settings of the window
  Future<void> _save() {
    final dir = _directory;
    if (dir == null || !persist) {
      return Future.value();
    }
    final json = _serialize(value, palette);
    return _enqueue(
      () =>
          File('${dir.path}${Platform.pathSeparator}theme.json')
              .writeAsString(json, flush: true),
    );
  }

  /// the colors in use, written to the palette they came from
  Future<void> _savePalette() {
    final library = _library;
    if (library == null || !persist) {
      return Future.value();
    }
    final theme = themeName;
    final name = palette;
    final colors = _paletteJson(value);
    return _enqueue(() => library.writePalette(theme, name, colors));
  }

  void setCornerRadius(double radius) {
    value = value.copyWith(cornerRadius: radius);
    unawaited(_save());
  }

  void setBorderWidth(double width) {
    value = value.copyWith(borderWidth: width);
    unawaited(_save());
  }

  void setBackgroundOpacity(double opacity) {
    value = value.copyWith(backgroundOpacity: opacity.clamp(0.0, 1.0));
    unawaited(_save());
  }

  void setAcrylic(bool acrylic) {
    value = value.copyWith(acrylic: acrylic);
    unawaited(_save());
  }

  /// [family] is one of [fonts], which are loaded under their file names
  void setFontFamily(String family) {
    value = value.copyWith(fontFamily: family);
    unawaited(_save());
  }

  void setMonospaceFontFamily(String family) {
    value = value.copyWith(monospaceFontFamily: family);
    unawaited(_save());
  }

  static const minFontSize = 8.0;
  static const maxFontSize = 48.0;

  /// `title`, `heading`, `body` or `caption`
  void setFontSize(String role, double size) {
    final clamped = size.clamp(minFontSize, maxFontSize).toDouble();
    value = switch (role) {
      'title' => value.copyWith(fontSizeTitle: clamped),
      'heading' => value.copyWith(fontSizeHeading: clamped),
      'body' => value.copyWith(fontSizeBody: clamped),
      'caption' => value.copyWith(fontSizeCaption: clamped),
      _ => throw ArgumentError.value(role, 'role'),
    };
    unawaited(_save());
  }

  static Map<String, dynamic> _paletteJson(AppTheme t) => {
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
  };

  static String _serializePalette(AppTheme t) =>
      const JsonEncoder.withIndent('  ').convert(_paletteJson(t));

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
