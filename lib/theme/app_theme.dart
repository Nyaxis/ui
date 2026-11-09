import 'package:flutter/material.dart';

/// parsed from `%APPDATA%\Nyaxis\ui\theme.json`; the constructor defaults are
/// the fallbacks for missing or malformed keys
@immutable
class AppTheme {
  const AppTheme({
    this.cornerRadius = 8,
    this.roundingPower = 2.0,
    this.borderWidth = 2,
    this.fontFamily = 'Fredoka',
    this.monospaceFontFamily = 'JetBrainsMono',
    this.fontSizeTitle = 22,
    this.fontSizeHeading = 16,
    this.fontSizeBody = 13,
    this.fontSizeCaption = 11,
    this.background = const Color(0xff1e1e2e),
    this.titleBar = const Color(0xff11111b),
    this.surface = const Color(0xff181825),
    this.backgroundOpacity = 1.0,
    this.acrylic = false,
    this.border = const Color(0xff313244),
    this.textPrimary = const Color(0xffcdd6f4),
    this.textDim = const Color(0xffa6adc8),
    this.accent = const Color(0xffcba6f7),
    this.red = const Color(0xfff38ba8),
    this.lineNumber = const Color(0xff7f849c),
    this.selection = const Color(0xff9399b2),
    this.hover = const Color(0xff45475a),
    this.active = const Color(0xff585b70),
    this.comment = const Color(0xff9399b2),
    this.keyword = const Color(0xffcba6f7),
    this.string = const Color(0xffa6e3a1),
    this.number = const Color(0xfffab387),
    this.function = const Color(0xff89b4fa),
    this.type = const Color(0xfff9e2af),
    this.operator = const Color(0xff89dceb),
    this.property = const Color(0xffb4befe),
    this.special = const Color(0xfff5c2e7),
    this.punctuation = const Color(0xff9399b2),
  });

  final double cornerRadius;
  final double roundingPower;

  final double borderWidth;

  final String fontFamily;

  final String monospaceFontFamily;

  final double fontSizeTitle;
  final double fontSizeHeading;
  final double fontSizeBody;
  final double fontSizeCaption;

  final Color background;

  /// stays opaque when [backgroundOpacity] makes the window translucent
  final Color titleBar;

  /// what is raised above the window, such as menus
  final Color surface;

  /// applied to [background] when painted, so hex strings in the json stay
  /// alpha-free
  final double backgroundOpacity;

  Color get backgroundColor => background.withValues(alpha: backgroundOpacity);

  final bool acrylic;
  final Color border;
  final Color textPrimary;
  final Color textDim;
  final Color accent;

  /// destructive actions, such as hovering the close button
  final Color red;

  /// editor line numbers
  final Color lineNumber;

  /// selected text; painted translucent
  final Color selection;

  final Color hover;
  final Color active;

  /// the colors of code, which the defaults give as Catppuccin Mocha does in
  /// Zed: comments
  final Color comment;
  final Color keyword;
  final Color string;
  final Color number;

  /// calls and definitions, and the names a language has built in
  final Color function;
  final Color type;
  final Color operator;

  /// the keys of objects and the members of things
  final Color property;

  /// escapes in strings, and regular expressions
  final Color special;

  /// brackets, commas and the like
  final Color punctuation;

  TextStyle get titleStyle => TextStyle(
    fontFamily: fontFamily,
    fontSize: fontSizeTitle,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  TextStyle get headingStyle => TextStyle(
    fontFamily: fontFamily,
    fontSize: fontSizeHeading,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  TextStyle get bodyStyle => TextStyle(
    fontFamily: fontFamily,
    fontSize: fontSizeBody,
    fontWeight: FontWeight.w500,
    color: textPrimary,
  );

  TextStyle get captionStyle => TextStyle(
    fontFamily: fontFamily,
    fontSize: fontSizeCaption,
    fontWeight: FontWeight.w400,
    color: textDim,
  );

  TextStyle get monoStyle => TextStyle(
    fontFamily: monospaceFontFamily,
    fontSize: fontSizeBody,
    fontWeight: FontWeight.w500,
    color: textPrimary,
  );

  AppTheme copyWith({
    double? cornerRadius,
    double? roundingPower,
    double? borderWidth,
    String? fontFamily,
    String? monospaceFontFamily,
    double? fontSizeTitle,
    double? fontSizeHeading,
    double? fontSizeBody,
    double? fontSizeCaption,
    Color? background,
    Color? titleBar,
    Color? surface,
    double? backgroundOpacity,
    bool? acrylic,
    Color? border,
    Color? textPrimary,
    Color? textDim,
    Color? accent,
    Color? red,
    Color? lineNumber,
    Color? selection,
    Color? hover,
    Color? active,
    Color? comment,
    Color? keyword,
    Color? string,
    Color? number,
    Color? function,
    Color? type,
    Color? operator,
    Color? property,
    Color? special,
    Color? punctuation,
  }) {
    return AppTheme(
      cornerRadius: cornerRadius ?? this.cornerRadius,
      roundingPower: roundingPower ?? this.roundingPower,
      borderWidth: borderWidth ?? this.borderWidth,
      fontFamily: fontFamily ?? this.fontFamily,
      monospaceFontFamily: monospaceFontFamily ?? this.monospaceFontFamily,
      fontSizeTitle: fontSizeTitle ?? this.fontSizeTitle,
      fontSizeHeading: fontSizeHeading ?? this.fontSizeHeading,
      fontSizeBody: fontSizeBody ?? this.fontSizeBody,
      fontSizeCaption: fontSizeCaption ?? this.fontSizeCaption,
      background: background ?? this.background,
      titleBar: titleBar ?? this.titleBar,
      surface: surface ?? this.surface,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      acrylic: acrylic ?? this.acrylic,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textDim: textDim ?? this.textDim,
      accent: accent ?? this.accent,
      red: red ?? this.red,
      lineNumber: lineNumber ?? this.lineNumber,
      selection: selection ?? this.selection,
      hover: hover ?? this.hover,
      active: active ?? this.active,
      comment: comment ?? this.comment,
      keyword: keyword ?? this.keyword,
      string: string ?? this.string,
      number: number ?? this.number,
      function: function ?? this.function,
      type: type ?? this.type,
      operator: operator ?? this.operator,
      property: property ?? this.property,
      special: special ?? this.special,
      punctuation: punctuation ?? this.punctuation,
    );
  }

  /// accepts `#RRGGBB` or `RRGGBB`; anything else yields [fallback]
  static Color _color(Object? hex, Color fallback) {
    if (hex is! String) {
      return fallback;
    }
    var h = hex.trim().replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    final value = int.tryParse(h, radix: 16);
    return value == null ? fallback : Color(value);
  }

  static const _fallback = AppTheme();

  /// the colors come from [palette] when given, otherwise from [json] itself
  factory AppTheme.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? palette,
  }) {
    final colors = palette ?? json;
    final sizes = json['fontSize'] is Map<String, dynamic>
        ? json['fontSize'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return AppTheme(
      cornerRadius:
          (json['cornerRadius'] as num?)?.toDouble() ?? _fallback.cornerRadius,
      roundingPower:
          ((json['roundingPower'] as num?)?.toDouble() ??
                  _fallback.roundingPower)
              .clamp(1.0, 10.0),
      borderWidth:
          (json['borderWidth'] as num?)?.toDouble() ?? _fallback.borderWidth,
      fontFamily: json['fontFamily'] is String
          ? json['fontFamily'] as String
          : _fallback.fontFamily,
      monospaceFontFamily: json['monospaceFontFamily'] is String
          ? json['monospaceFontFamily'] as String
          : _fallback.monospaceFontFamily,
      fontSizeTitle:
          (sizes['title'] as num?)?.toDouble() ?? _fallback.fontSizeTitle,
      fontSizeHeading:
          (sizes['heading'] as num?)?.toDouble() ?? _fallback.fontSizeHeading,
      fontSizeBody:
          (sizes['body'] as num?)?.toDouble() ?? _fallback.fontSizeBody,
      fontSizeCaption:
          (sizes['caption'] as num?)?.toDouble() ?? _fallback.fontSizeCaption,
      acrylic: json['acrylic'] is bool
          ? json['acrylic'] as bool
          : _fallback.acrylic,
      backgroundOpacity:
          ((json['backgroundOpacity'] as num?)?.toDouble() ??
                  _fallback.backgroundOpacity)
              .clamp(0.0, 1.0)
              .toDouble(),
      background: _color(colors['background'], _fallback.background),
      titleBar: _color(colors['titleBar'], _fallback.titleBar),
      surface: _color(colors['surface'], _fallback.surface),
      border: _color(colors['border'], _fallback.border),
      textPrimary: _color(colors['textPrimary'], _fallback.textPrimary),
      textDim: _color(colors['textDim'], _fallback.textDim),
      accent: _color(colors['accent'], _fallback.accent),
      red: _color(colors['red'], _fallback.red),
      lineNumber: _color(colors['lineNumber'], _fallback.lineNumber),
      selection: _color(colors['selection'], _fallback.selection),
      hover: _color(colors['hover'], _fallback.hover),
      active: _color(colors['active'], _fallback.active),
      comment: _color(colors['comment'], _fallback.comment),
      keyword: _color(colors['keyword'], _fallback.keyword),
      string: _color(colors['string'], _fallback.string),
      number: _color(colors['number'], _fallback.number),
      function: _color(colors['function'], _fallback.function),
      type: _color(colors['type'], _fallback.type),
      operator: _color(colors['operator'], _fallback.operator),
      property: _color(colors['property'], _fallback.property),
      special: _color(colors['special'], _fallback.special),
      punctuation: _color(colors['punctuation'], _fallback.punctuation),
    );
  }
}
