import 'package:flutter/material.dart';

@immutable
class AppTheme {
  const AppTheme({
    this.cornerRadius = 0,
    this.borderWidth = 1,
    this.fontFamily = 'Fredoka',
    this.background = const Color(0x1E1E2EFF),
    this.border = const Color(0xCBA6F7FF),
    this.textPrimary = const Color(0xFFE8EAED),
    this.textDim = const Color(0xFF9AA0A6),
    this.accent = const Color(0xFF7C5CFF),
  });

  final double cornerRadius;

  final double borderWidth;
  final String fontFamily;
  final Color background;
  final Color border;
  final Color textPrimary;
  final Color textDim;
  final Color accent;

  AppTheme copyWith({
    double? cornerRadius,
    double? borderWidth,
    String? fontFamily,
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
    return AppTheme(
      cornerRadius: (json['cornerRadius'] as num?)?.toDouble() ?? _fallback.cornerRadius,
      borderWidth: (json['borderWidth'] as num?)?.toDouble() ?? _fallback.borderWidth,
      fontFamily: json['fontFamily'] is String ? json['fontFamily'] as String : _fallback.fontFamily,
      background: _color(json['background'], _fallback.background),
      border: _color(json['border'], _fallback.border),
      textPrimary: _color(json['textPrimary'], _fallback.textPrimary),
      textDim: _color(json['textDim'], _fallback.textDim),
      accent: _color(json['accent'], _fallback.accent),
    );
  }
}
