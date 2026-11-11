import 'package:flutter/foundation.dart';

import '../native_editor/scrollbar_layout.dart' show ScrollbarVisibility;
import '../syntax/syntax_palette.dart' show fontStylesFromConfig;
import 'config_file.dart';

/// the editor's settings, under `"editor"` in `config.json`. what each one is
/// set to when the file does not say is what the editor had before they could
/// be changed, so nothing moves until one is
@immutable
class EditorPrefs {
  const EditorPrefs({
    this.fontSize,
    this.tabSize = 4,
    this.wordWrap = true,
    this.lineNumbers = true,
    this.fontLigatures = false,
    this.autoClosingBrackets = true,
    this.scrollbars = ScrollbarVisibility.auto,
    this.mouseWheelZoom = false,
  });

  /// unknown or malformed values fall back to their defaults
  factory EditorPrefs.fromJson(Object? json) {
    if (json is! Map) {
      return const EditorPrefs();
    }
    const defaults = EditorPrefs();
    bool flag(String key, bool fallback) {
      final value = json[key];
      return value is bool ? value : fallback;
    }

    final size = json['fontSize'];
    final tab = json['tabSize'];
    return EditorPrefs(
      fontSize: size is num
          ? size.toDouble().clamp(minFontSize, maxFontSize).toDouble()
          : null,
      tabSize: tab is int
          ? tab.clamp(minTabSize, maxTabSize).toInt()
          : defaults.tabSize,
      wordWrap: flag('wordWrap', defaults.wordWrap),
      lineNumbers: flag('lineNumbers', defaults.lineNumbers),
      fontLigatures: flag('fontLigatures', defaults.fontLigatures),
      autoClosingBrackets: flag(
        'autoClosingBrackets',
        defaults.autoClosingBrackets,
      ),
      scrollbars: ScrollbarVisibility.fromId(
        json['scrollbars'] as String?,
        orElse: defaults.scrollbars,
      ),
      mouseWheelZoom: flag('mouseWheelZoom', defaults.mouseWheelZoom),
    );
  }

  static const minFontSize = 8.0;
  static const maxFontSize = 40.0;
  static const minTabSize = 1;
  static const maxTabSize = 8;

  /// null follows the theme's body size
  final double? fontSize;
  final int tabSize;
  final bool wordWrap;
  final bool lineNumbers;
  final bool fontLigatures;

  /// closes them as the language says, or never
  final bool autoClosingBrackets;

  /// when the editor shows its scrollbars
  final ScrollbarVisibility scrollbars;

  /// whether the wheel with the control key down changes the font size of the
  /// editor
  final bool mouseWheelZoom;

  EditorPrefs copyWith({
    int? tabSize,
    bool? wordWrap,
    bool? lineNumbers,
    bool? fontLigatures,
    bool? autoClosingBrackets,
    ScrollbarVisibility? scrollbars,
    bool? mouseWheelZoom,
  }) {
    return EditorPrefs(
      fontSize: fontSize,
      tabSize: tabSize ?? this.tabSize,
      wordWrap: wordWrap ?? this.wordWrap,
      lineNumbers: lineNumbers ?? this.lineNumbers,
      fontLigatures: fontLigatures ?? this.fontLigatures,
      autoClosingBrackets: autoClosingBrackets ?? this.autoClosingBrackets,
      scrollbars: scrollbars ?? this.scrollbars,
      mouseWheelZoom: mouseWheelZoom ?? this.mouseWheelZoom,
    );
  }

  /// [size] is kept within the limits, and null goes back to the theme's
  EditorPrefs withFontSize(double? size) {
    return EditorPrefs(
      fontSize: size?.clamp(minFontSize, maxFontSize).toDouble(),
      tabSize: tabSize,
      wordWrap: wordWrap,
      lineNumbers: lineNumbers,
      fontLigatures: fontLigatures,
      autoClosingBrackets: autoClosingBrackets,
      scrollbars: scrollbars,
      mouseWheelZoom: mouseWheelZoom,
    );
  }

  Map<String, dynamic> toJson() => {
    'fontSize': ?fontSize,
    'tabSize': tabSize,
    'wordWrap': wordWrap,
    'lineNumbers': lineNumbers,
    'fontLigatures': fontLigatures,
    'autoClosingBrackets': autoClosingBrackets,
    'scrollbars': scrollbars.name,
    'mouseWheelZoom': mouseWheelZoom,
  };

  @override
  bool operator ==(Object other) =>
      other is EditorPrefs &&
      other.fontSize == fontSize &&
      other.tabSize == tabSize &&
      other.wordWrap == wordWrap &&
      other.lineNumbers == lineNumbers &&
      other.fontLigatures == fontLigatures &&
      other.autoClosingBrackets == autoClosingBrackets &&
      other.scrollbars == scrollbars &&
      other.mouseWheelZoom == mouseWheelZoom;

  @override
  int get hashCode => Object.hash(
    fontSize,
    tabSize,
    wordWrap,
    lineNumbers,
    fontLigatures,
    autoClosingBrackets,
    scrollbars,
    mouseWheelZoom,
  );
}

/// which names of the syntax are drawn bold or italic, by `syntaxStyles` in
/// `config.json`: the name of what the grammar finds, and the words that say
/// how it is drawn. saved whenever it changes
class SyntaxStyleSettings extends ValueNotifier<Map<String, String>> {
  SyntaxStyleSettings(this._config) : super(const {});

  final ConfigFile _config;

  Future<void> load() async {
    final json = await _config.read();
    if (json != null) {
      value = fontStylesFromConfig(json['syntaxStyles']);
    }
  }

  void change(Map<String, String> styles) {
    if (mapEquals(styles, value)) {
      return;
    }
    value = Map.unmodifiable(styles);
    _config.update((json) {
      if (styles.isEmpty) {
        json.remove('syntaxStyles');
      } else {
        json['syntaxStyles'] = styles;
      }
    });
  }
}

/// the current [EditorPrefs], saved to `config.json` whenever they change
class EditorSettings extends ValueNotifier<EditorPrefs> {
  EditorSettings(this._config) : super(const EditorPrefs());

  final ConfigFile _config;

  Future<void> load() async {
    final json = await _config.read();
    if (json != null) {
      value = EditorPrefs.fromJson(json['editor']);
    }
  }

  void change(EditorPrefs prefs) {
    if (prefs == value) {
      return;
    }
    value = prefs;
    _config.update((json) => json['editor'] = prefs.toJson());
  }
}
