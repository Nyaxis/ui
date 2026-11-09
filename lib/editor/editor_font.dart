import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// the editor is a web page, which cannot use the fonts that flutter has
/// registered, so a font that comes with the app or the theme is put in the
/// page itself
class EditorFont {
  static const _bundled = {
    'JetBrainsMono': 'assets/fonts/JetBrainsMono-VariableFont.ttf',
  };

  /// names that can be written into css and script without escaping
  static final _safeFamily = RegExp(r'^[A-Za-z0-9 _-]{1,64}$');

  static bool isSafe(String family) => _safeFamily.hasMatch(family);

  /// the `@font-face` rule for [family], taken from the font file of that name
  /// in [themeFonts], or from the app when it is a font it comes with; null
  /// for a font that is not found, which the page may still have installed
  static Future<String?> css(
    String family, {
    Directory? themeFonts,
    Future<Uint8List> Function(String asset)? bundled,
  }) async {
    if (!isSafe(family)) {
      return null;
    }
    Uint8List? bytes;
    var extension = 'ttf';
    if (themeFonts != null) {
      for (final candidate in const ['ttf', 'otf']) {
        final file = File('${themeFonts.path}\\$family.$candidate');
        if (file.existsSync()) {
          bytes = await file.readAsBytes();
          extension = candidate;
          break;
        }
      }
    }
    if (bytes == null && _bundled.containsKey(family)) {
      bytes = await (bundled ?? _loadAsset)(_bundled[family]!);
    }
    if (bytes == null) {
      return null;
    }
    final format = extension == 'otf' ? 'opentype' : 'truetype';
    return "@font-face { font-family: '$family'; "
        'src: url(data:font/$extension;base64,${base64Encode(bytes)}) '
        "format('$format'); font-weight: 100 900; }";
  }

  static Future<Uint8List> _loadAsset(String asset) async {
    final data = await rootBundle.load(asset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  /// measures the editor's text again once [family] has loaded, since it was
  /// measured with the font it fell back to
  static String remeasureScript(String family) =>
      "document.fonts.load(\"13px '$family'\").then(() => "
      'window.monaco && monaco.editor.remeasureFonts());';
}
