import 'package:flutter/foundation.dart';

import '../native_editor/diagnostic_hover.dart' show HoverSettings;
import '../native_editor/scrollbar_layout.dart'
    show ScrollbarSettings, ScrollbarVisibility;
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
    this.scrollbar = const ScrollbarSettings(show: ScrollbarVisibility.auto),
    this.mouseWheelZoom = false,
    this.unnecessaryCodeFade = defaultUnnecessaryCodeFade,
    this.hover = const HoverSettings(),
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
    final fade = json['unnecessaryCodeFade'];
    Duration delay(String key, Duration fallback) {
      final value = json[key];
      return value is num
          ? Duration(
              milliseconds: value
                  .round()
                  .clamp(0, maxHoverDelay.inMilliseconds)
                  .toInt(),
            )
          : fallback;
    }

    return EditorPrefs(
      hover: HoverSettings(
        enabled: flag('hoverPopoverEnabled', defaults.hover.enabled),
        delay: delay('hoverPopoverDelay', defaults.hover.delay),
        sticky: flag('hoverPopoverSticky', defaults.hover.sticky),
        hidingDelay: delay(
          'hoverPopoverHidingDelay',
          defaults.hover.hidingDelay,
        ),
      ),
      unnecessaryCodeFade: fade is num
          ? fade.toDouble().clamp(0.0, maxUnnecessaryCodeFade).toDouble()
          : defaults.unnecessaryCodeFade,
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
      scrollbar: json['scrollbar'] is Map
          ? ScrollbarSettings.fromJson(json['scrollbar'])
          // the setting that was only when to show them
          : ScrollbarSettings.fromJson({'show': json['scrollbars']}),
      mouseWheelZoom: flag('mouseWheelZoom', defaults.mouseWheelZoom),
    );
  }

  static const minFontSize = 8.0;
  static const maxFontSize = 40.0;
  static const minTabSize = 1;
  static const maxTabSize = 8;

  /// how much unused code is faded, and the most it can be
  static const defaultUnnecessaryCodeFade = 0.3;
  static const maxUnnecessaryCodeFade = 0.9;

  /// the longest that the pointer rests before a popover, or it stays
  static const maxHoverDelay = Duration(seconds: 2);

  /// null follows the theme's body size
  final double? fontSize;
  final int tabSize;
  final bool wordWrap;
  final bool lineNumbers;
  final bool fontLigatures;

  /// closes them as the language says, or never
  final bool autoClosingBrackets;

  /// when the editor shows its scrollbars, and what they mark
  final ScrollbarSettings scrollbar;

  /// whether the wheel with the control key down changes the font size of the
  /// editor
  final bool mouseWheelZoom;

  /// how much unused code is faded out, from 0 to [maxUnnecessaryCodeFade]
  final double unnecessaryCodeFade;

  /// when what the language server found is shown for the text that the
  /// pointer rests on
  final HoverSettings hover;

  EditorPrefs copyWith({
    HoverSettings? hover,
    int? tabSize,
    bool? wordWrap,
    bool? lineNumbers,
    bool? fontLigatures,
    bool? autoClosingBrackets,
    ScrollbarSettings? scrollbar,
    bool? mouseWheelZoom,
    double? unnecessaryCodeFade,
  }) {
    return EditorPrefs(
      hover: hover ?? this.hover,
      unnecessaryCodeFade: unnecessaryCodeFade ?? this.unnecessaryCodeFade,
      fontSize: fontSize,
      tabSize: tabSize ?? this.tabSize,
      wordWrap: wordWrap ?? this.wordWrap,
      lineNumbers: lineNumbers ?? this.lineNumbers,
      fontLigatures: fontLigatures ?? this.fontLigatures,
      autoClosingBrackets: autoClosingBrackets ?? this.autoClosingBrackets,
      scrollbar: scrollbar ?? this.scrollbar,
      mouseWheelZoom: mouseWheelZoom ?? this.mouseWheelZoom,
    );
  }

  /// [size] is kept within the limits, and null goes back to the theme's
  EditorPrefs withFontSize(double? size) {
    return EditorPrefs(
      hover: hover,
      unnecessaryCodeFade: unnecessaryCodeFade,
      fontSize: size?.clamp(minFontSize, maxFontSize).toDouble(),
      tabSize: tabSize,
      wordWrap: wordWrap,
      lineNumbers: lineNumbers,
      fontLigatures: fontLigatures,
      autoClosingBrackets: autoClosingBrackets,
      scrollbar: scrollbar,
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
    'scrollbar': scrollbar.toJson(),
    'mouseWheelZoom': mouseWheelZoom,
    'unnecessaryCodeFade': unnecessaryCodeFade,
    'hoverPopoverEnabled': hover.enabled,
    'hoverPopoverDelay': hover.delay.inMilliseconds,
    'hoverPopoverSticky': hover.sticky,
    'hoverPopoverHidingDelay': hover.hidingDelay.inMilliseconds,
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
      other.scrollbar == scrollbar &&
      other.mouseWheelZoom == mouseWheelZoom &&
      other.unnecessaryCodeFade == unnecessaryCodeFade &&
      other.hover == hover;

  @override
  int get hashCode => Object.hash(
    fontSize,
    tabSize,
    wordWrap,
    lineNumbers,
    fontLigatures,
    autoClosingBrackets,
    scrollbar,
    mouseWheelZoom,
    unnecessaryCodeFade,
    hover,
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
