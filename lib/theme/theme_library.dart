import 'dart:convert';
import 'dart:io';

/// the theme folders in a `themes` folder, and the palettes in each of them.
/// everything is files, so what the app does and what a user does by hand
/// agree
class ThemeLibrary {
  ThemeLibrary(this.root);

  /// the `themes` folder
  final Directory root;

  /// ships with the app, and is filled in again when it is missing
  static const defaultTheme = 'default';

  static const maxNameLength = 48;

  static final _forbidden = RegExp(r'[\\/:*?"<>|\x00-\x1f]');
  static final _reserved = RegExp(
    r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])$',
    caseSensitive: false,
  );

  static String _name(String path) => path.split(RegExp(r'[\\/]')).last;

  String _join(List<String> parts) => parts.join(Platform.pathSeparator);

  Directory theme(String name) => Directory(_join([root.path, name]));

  Directory _palettes(String theme) =>
      Directory(_join([root.path, theme, 'palettes']));

  File _palette(String theme, String name) =>
      File(_join([root.path, theme, 'palettes', '$name.json']));

  /// why [raw] cannot name something, null when it can. [taken] are the names
  /// in use, compared without regard to case, and [renaming] is the one that
  /// is being given a new name, which its own name does not clash with
  static String? checkName(
    String raw,
    Iterable<String> taken, {
    String? renaming,
  }) {
    final name = raw.trim();
    if (name.isEmpty) {
      return 'Enter a name';
    }
    if (name.length > maxNameLength) {
      return 'Use $maxNameLength characters or fewer';
    }
    if (_forbidden.hasMatch(name)) {
      return r'A name cannot contain \ / : * ? " < > |';
    }
    if (name.startsWith('.') || name.endsWith('.')) {
      return 'A name cannot start or end with a dot';
    }
    if (_reserved.hasMatch(name)) {
      return 'Windows keeps that name for itself';
    }
    final lower = name.toLowerCase();
    for (final other in taken) {
      if (other != renaming && other.toLowerCase() == lower) {
        return 'That name is already in use';
      }
    }
    return null;
  }

  /// the themes, with the default one first
  List<String> themes() {
    if (!root.existsSync()) {
      return const [];
    }
    final names = [
      for (final entry in root.listSync().whereType<Directory>())
        _name(entry.path),
    ];
    return names..sort((a, b) {
      if (a == defaultTheme || b == defaultTheme) {
        return a == defaultTheme ? -1 : 1;
      }
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
  }

  /// a copy of the theme [from], with its icons, fonts and palettes, named [to]
  Future<void> copyTheme(String from, String to) =>
      _copy(theme(from), theme(to));

  Future<void> renameTheme(String from, String to) async {
    await theme(from).rename(theme(to).path);
  }

  Future<void> deleteTheme(String name) async {
    await theme(name).delete(recursive: true);
  }

  Future<void> _copy(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final entry in from.list()) {
      final name = _name(entry.path);
      if (entry is Directory) {
        await _copy(entry, Directory(_join([to.path, name])));
      } else if (entry is File) {
        await entry.copy(_join([to.path, name]));
      }
    }
  }

  /// the palettes of [theme], by the name of their file
  List<String> palettes(String theme) {
    final folder = _palettes(theme);
    if (!folder.existsSync()) {
      return const [];
    }
    final names = [
      for (final file in folder.listSync().whereType<File>())
        if (file.path.toLowerCase().endsWith('.json'))
          _name(file.path).substring(0, _name(file.path).length - 5),
    ];
    return names..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Future<Map<String, dynamic>?> readPalette(String theme, String name) async {
    try {
      final json = jsonDecode(await _palette(theme, name).readAsString());
      return json is Map<String, dynamic> ? json : null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// the same, for the few small files that are read as a menu opens
  Map<String, dynamic>? readPaletteSync(String theme, String name) {
    try {
      final json = jsonDecode(_palette(theme, name).readAsStringSync());
      return json is Map<String, dynamic> ? json : null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// when the file of a palette was last written, null when there is none
  DateTime? paletteModified(String theme, String name) {
    try {
      return _palette(theme, name).statSync().modified;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> writePalette(
    String theme,
    String name,
    Map<String, dynamic> colors,
  ) async {
    final file = _palette(theme, name);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(colors),
      flush: true,
    );
  }

  Future<void> renamePalette(String theme, String from, String to) async {
    await _palette(theme, from).rename(_palette(theme, to).path);
  }

  Future<void> deletePalette(String theme, String name) async {
    await _palette(theme, name).delete();
  }
}
