import 'package:flutter/material.dart';

/// App theme parsed from the user's `%APPDATA%\Nyaxis\ui\theme.json`.
///
/// The constructor values are the fallbacks for missing/malformed JSON keys.
@immutable
class AppTheme {
  const AppTheme({
    this.cornerRadius = 0,
    this.borderWidth = 1,
    this.fontFamily = 'Fredoka',
    this.monospaceFontFamily = 'JetBrainsMono',
    this.fontSizeTitle = 22,
    this.fontSizeHeading = 16,
    this.fontSizeBody = 13,
    this.fontSizeCaption = 11,
    this.background = const Color(0xff1e1e2e),
    this.border = const Color(0xff45475a),
    this.textPrimary = const Color(0xffcdd6f4),
    this.textDim = const Color(0xffa6adc8),
    this.accent = const Color(0xffcba6f7),
  });

  final double cornerRadius;

  final double borderWidth;

  final String fontFamily;

  final String monospaceFontFamily;

  final double fontSizeTitle;
  final double fontSizeHeading;
  final double fontSizeBody;
  final double fontSizeCaption;

  final Color background;
  final Color border;
  final Color textPrimary;
  final Color textDim;
  final Color accent;

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
    double? borderWidth,
    String? fontFamily,
    String? monospaceFontFamily,
    double? fontSizeTitle,
    double? fontSizeHeading,
    double? fontSizeBody,
    double? fontSizeCaption,
    Color? background,
    Color? border,
    Color? textPrimary,
    Color? textDim,
    Color? accent,
  }) {
    return AppTheme(
      cornerRadius: cornerRadius ?? this.cornerRadius,
      borderWidth: borderWidth ?? this.borderWidth,
      fontFamily: fontFamily ?? this.fontFamily,
      monospaceFontFamily: monospaceFontFamily ?? this.monospaceFontFamily,
      fontSizeTitle: fontSizeTitle ?? this.fontSizeTitle,
      fontSizeHeading: fontSizeHeading ?? this.fontSizeHeading,
      fontSizeBody: fontSizeBody ?? this.fontSizeBody,
      fontSizeCaption: fontSizeCaption ?? this.fontSizeCaption,
      background: background ?? this.background,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textDim: textDim ?? this.textDim,
      accent: accent ?? this.accent,
    );
  }

  /// Parses `#RRGGBB` or `RRGGBB`; anything else falls back to [fallback].
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

  factory AppTheme.fromJson(Map<String, dynamic> json) {
    final sizes = json['fontSize'] is Map<String, dynamic>
        ? json['fontSize'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return AppTheme(
      cornerRadius:
          (json['cornerRadius'] as num?)?.toDouble() ?? _fallback.cornerRadius,
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
      background: _color(json['background'], _fallback.background),
      border: _color(json['border'], _fallback.border),
      textPrimary: _color(json['textPrimary'], _fallback.textPrimary),
      textDim: _color(json['textDim'], _fallback.textDim),
      accent: _color(json['accent'], _fallback.accent),
    );
  }
}
