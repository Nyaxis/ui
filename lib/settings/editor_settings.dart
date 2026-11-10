import 'package:flutter/foundation.dart';
import 'package:flutter_monaco/flutter_monaco.dart';

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
    this.minimap = false,
    this.lineNumbers = true,
    this.renderWhitespace = RenderWhitespace.selection,
    this.fontLigatures = false,
    this.smoothScrolling = true,
    this.bracketPairColorization = true,
    this.autoClosingBrackets = true,
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
      minimap: flag('minimap', defaults.minimap),
      lineNumbers: flag('lineNumbers', defaults.lineNumbers),
      renderWhitespace: RenderWhitespace.fromId(
        json['renderWhitespace'] as String?,
        orElse: defaults.renderWhitespace,
      ),
      fontLigatures: flag('fontLigatures', defaults.fontLigatures),
      smoothScrolling: flag('smoothScrolling', defaults.smoothScrolling),
      bracketPairColorization: flag(
        'bracketPairColorization',
        defaults.bracketPairColorization,
      ),
      autoClosingBrackets: flag(
        'autoClosingBrackets',
        defaults.autoClosingBrackets,
      ),
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
  final bool minimap;
  final bool lineNumbers;
  final RenderWhitespace renderWhitespace;
  final bool fontLigatures;
  final bool smoothScrolling;
  final bool bracketPairColorization;

  /// closes them as the language says, or never
  final bool autoClosingBrackets;

  EditorPrefs copyWith({
    int? tabSize,
    bool? wordWrap,
    bool? minimap,
    bool? lineNumbers,
    RenderWhitespace? renderWhitespace,
    bool? fontLigatures,
    bool? smoothScrolling,
    bool? bracketPairColorization,
    bool? autoClosingBrackets,
  }) {
    return EditorPrefs(
      fontSize: fontSize,
      tabSize: tabSize ?? this.tabSize,
      wordWrap: wordWrap ?? this.wordWrap,
      minimap: minimap ?? this.minimap,
      lineNumbers: lineNumbers ?? this.lineNumbers,
      renderWhitespace: renderWhitespace ?? this.renderWhitespace,
      fontLigatures: fontLigatures ?? this.fontLigatures,
      smoothScrolling: smoothScrolling ?? this.smoothScrolling,
      bracketPairColorization:
          bracketPairColorization ?? this.bracketPairColorization,
      autoClosingBrackets: autoClosingBrackets ?? this.autoClosingBrackets,
    );
  }

  /// [size] is kept within the limits, and null goes back to the theme's
  EditorPrefs withFontSize(double? size) {
    return EditorPrefs(
      fontSize: size?.clamp(minFontSize, maxFontSize).toDouble(),
      tabSize: tabSize,
      wordWrap: wordWrap,
      minimap: minimap,
      lineNumbers: lineNumbers,
      renderWhitespace: renderWhitespace,
      fontLigatures: fontLigatures,
      smoothScrolling: smoothScrolling,
      bracketPairColorization: bracketPairColorization,
      autoClosingBrackets: autoClosingBrackets,
    );
  }

  Map<String, dynamic> toJson() => {
    'fontSize': ?fontSize,
    'tabSize': tabSize,
    'wordWrap': wordWrap,
    'minimap': minimap,
    'lineNumbers': lineNumbers,
    'renderWhitespace': renderWhitespace.id,
    'fontLigatures': fontLigatures,
    'smoothScrolling': smoothScrolling,
    'bracketPairColorization': bracketPairColorization,
    'autoClosingBrackets': autoClosingBrackets,
  };

  /// what the editor is told, with [themeFontSize] when no size is set
  EditorOptions toOptions(double themeFontSize) {
    return EditorOptions(
      fontSize: fontSize ?? themeFontSize,
      tabSize: tabSize,
      wordWrap: wordWrap ? MonacoWordWrap.on : MonacoWordWrap.off,
      minimap: MonacoMinimapOptions(enabled: minimap),
      lineNumbers: lineNumbers ? MonacoLineNumbers.on : MonacoLineNumbers.off,
      renderWhitespace: renderWhitespace,
      fontLigatures: fontLigatures,
      smoothScrolling: smoothScrolling,
      bracketPairColorization: bracketPairColorization,
      autoClosingBrackets: autoClosingBrackets
          ? AutoClosingBehavior.languageDefined
          : AutoClosingBehavior.never,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EditorPrefs &&
      other.fontSize == fontSize &&
      other.tabSize == tabSize &&
      other.wordWrap == wordWrap &&
      other.minimap == minimap &&
      other.lineNumbers == lineNumbers &&
      other.renderWhitespace == renderWhitespace &&
      other.fontLigatures == fontLigatures &&
      other.smoothScrolling == smoothScrolling &&
      other.bracketPairColorization == bracketPairColorization &&
      other.autoClosingBrackets == autoClosingBrackets;

  @override
  int get hashCode => Object.hash(
    fontSize,
    tabSize,
    wordWrap,
    minimap,
    lineNumbers,
    renderWhitespace,
    fontLigatures,
    smoothScrolling,
    bracketPairColorization,
    autoClosingBrackets,
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
