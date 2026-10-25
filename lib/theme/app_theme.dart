import 'package:flutter/material.dart';

/// Backdrop blur used while [AppTheme.acrylic] is on. Names and defaults
/// follow Hyprland's `decoration:blur` section; [strength] is ours, the mix
/// between the sharp backdrop and the blurred one.
@immutable
class BlurSettings {
  const BlurSettings({
    this.size = 8,
    this.passes = 1,
    this.strength = 1.0,
    this.noise = 0.0117,
    this.contrast = 0.8916,
    this.brightness = 0.8172,
    this.vibrancy = 0.1696,
  });

  /// Sample offset per pass; the spread of each blur step.
  final double size;

  /// Down/up levels; each one halves the resolution and roughly doubles the
  /// radius, so effective radius is about `size * 2^passes`.
  final int passes;

  /// 0 keeps the sharp backdrop, 1 is fully blurred.
  final double strength;

  final double noise;
  final double contrast;
  final double brightness;
  final double vibrancy;

  BlurSettings copyWith({
    double? size,
    int? passes,
    double? strength,
    double? noise,
    double? contrast,
    double? brightness,
    double? vibrancy,
  }) {
    return BlurSettings(
      size: size ?? this.size,
      passes: passes ?? this.passes,
      strength: strength ?? this.strength,
      noise: noise ?? this.noise,
      contrast: contrast ?? this.contrast,
      brightness: brightness ?? this.brightness,
      vibrancy: vibrancy ?? this.vibrancy,
    );
  }

  static const _fallback = BlurSettings();

  factory BlurSettings.fromJson(Map<String, dynamic> json) {
    double number(String key, double fallback, double min, double max) =>
        ((json[key] as num?)?.toDouble() ?? fallback)
            .clamp(min, max)
            .toDouble();
    return BlurSettings(
      size: number('size', _fallback.size, 0, 64),
      passes: ((json['passes'] as num?)?.toInt() ?? _fallback.passes).clamp(
        0,
        8,
      ),
      strength: number('strength', _fallback.strength, 0, 1),
      noise: number('noise', _fallback.noise, 0, 1),
      contrast: number('contrast', _fallback.contrast, 0, 2),
      brightness: number('brightness', _fallback.brightness, 0, 2),
      vibrancy: number('vibrancy', _fallback.vibrancy, 0, 1),
    );
  }

  Map<String, Object> toJson() => {
    'size': size,
    'passes': passes,
    'strength': strength,
    'noise': noise,
    'contrast': contrast,
    'brightness': brightness,
    'vibrancy': vibrancy,
  };
}

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
    this.backgroundOpacity = 1.0,
    this.acrylic = false,
    this.blur = const BlurSettings(),
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

  /// How opaque the window background paints over the desktop, 0..1.
  /// Applied to [background] when it is painted; hex strings in the JSON
  /// stay alpha-free.
  final double backgroundOpacity;

  /// [background] with its opacity applied; the thing the shell paints.
  Color get backgroundColor => background.withValues(alpha: backgroundOpacity);

  final bool acrylic;
  final BlurSettings blur;
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
    double? backgroundOpacity,
    bool? acrylic,
    BlurSettings? blur,
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
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      acrylic: acrylic ?? this.acrylic,
      blur: blur ?? this.blur,
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
      acrylic: json['acrylic'] is bool
          ? json['acrylic'] as bool
          : _fallback.acrylic,
      blur: json['blur'] is Map<String, dynamic>
          ? BlurSettings.fromJson(json['blur'] as Map<String, dynamic>)
          : _fallback.blur,
      backgroundOpacity:
          ((json['backgroundOpacity'] as num?)?.toDouble() ??
                  _fallback.backgroundOpacity)
              .clamp(0.0, 1.0)
              .toDouble(),
      background: _color(json['background'], _fallback.background),
      border: _color(json['border'], _fallback.border),
      textPrimary: _color(json['textPrimary'], _fallback.textPrimary),
      textDim: _color(json['textDim'], _fallback.textDim),
      accent: _color(json['accent'], _fallback.accent),
    );
  }
}
