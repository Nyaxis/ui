import 'dart:ui' show Color;

import 'package:flutter_monaco/flutter_monaco.dart';

import '../theme/app_theme.dart';

/// `#rrggbb`, with an alpha suffix when [opacity] is given
String hexOf(Color color, [double? opacity]) {
  final rgb = (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  final alpha = opacity == null
      ? ''
      : (opacity * 255).round().toRadixString(16).padLeft(2, '0');
  return '#$rgb$alpha';
}

/// a color as the token rules of monaco have it, without the `#`
String _bare(Color color) =>
    (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');

/// what the editor looks like for [theme]: the colors of everything around
/// the code, and a rule for each kind of token, which is where the code gets
/// its colors. a rule names the start of a token's name, so `string` also
/// colors `string.escape` unless that has a rule of its own, which wins
MonacoThemeDefinition monacoThemeFor(AppTheme theme, {required String id}) {
  final dark = theme.background.computeLuminance() < 0.5;
  MonacoThemeRule rule(String token, Color color, {String? style}) =>
      MonacoThemeRule(token: token, foreground: _bare(color), fontStyle: style);

  return MonacoThemeDefinition(
    id: id,
    base: dark ? MonacoBaseTheme.vsDark : MonacoBaseTheme.vs,
    rules: [
      rule('', theme.textPrimary),
      rule('comment', theme.comment, style: 'italic'),
      rule('keyword', theme.keyword),
      rule('string', theme.string),
      rule('string.escape', theme.special),
      rule('string.invalid', theme.red),
      rule('string.escape.invalid', theme.red),
      // the keys of json, which monaco names as strings
      rule('string.key', theme.property),
      rule('number', theme.number),
      rule('constant', theme.number),
      rule('type', theme.type),
      rule('predefined', theme.function),
      rule('function', theme.function),
      rule('identifier', theme.textPrimary),
      rule('variable', theme.textPrimary),
      rule('variable.predefined', theme.red),
      rule('operator', theme.operator),
      rule('delimiter', theme.punctuation),
      rule('tag', theme.function),
      rule('attribute.name', theme.type),
      rule('attribute.value', theme.string),
      rule('regexp', theme.special),
      rule('key', theme.property),
    ],
    colors: {
      // the window paints the background, so its opacity applies
      'editor.background': '#00000000',
      'editor.foreground': hexOf(theme.textPrimary),
      'editorGutter.background': '#00000000',
      'editorLineNumber.foreground': hexOf(theme.lineNumber),
      'editorLineNumber.activeForeground': hexOf(theme.accent),
      'editorCursor.foreground': hexOf(theme.accent),
      'editor.selectionBackground': hexOf(theme.selection, dark ? 0.25 : 0.3),
      'editor.lineHighlightBackground': hexOf(theme.textPrimary, 0.07),
      // the focused line is outlined in this color
      'focusBorder': '#00000000',
      'editorIndentGuide.background1': hexOf(theme.border, 0.6),
      'editorWidget.background': hexOf(theme.titleBar),
      'editorWidget.border': hexOf(theme.border),
      // pairs of brackets in turn
      'editorBracketHighlight.foreground1': hexOf(theme.keyword),
      'editorBracketHighlight.foreground2': hexOf(theme.property),
      'editorBracketHighlight.foreground3': hexOf(theme.function),
      'editorBracketHighlight.foreground4': hexOf(theme.string),
      'editorBracketHighlight.foreground5': hexOf(theme.type),
      'editorBracketHighlight.foreground6': hexOf(theme.number),
      'editorBracketHighlight.unexpectedBracket.foreground': hexOf(theme.red),
      // monaco reads the editor's background without its transparency, so the
      // scrollbar's column, which takes that color, would be black
      'editorOverviewRuler.background': '#00000000',
      // the minimap is a panel of its own, so it does not blend into the
      // editor; the window's opacity applies, as it does to the editor
      'minimap.background': hexOf(theme.surface, theme.backgroundOpacity),
      'minimap.selectionHighlight': hexOf(theme.accent, 0.8),
      'minimap.findMatchHighlight': hexOf(theme.accent, 0.8),
      // the sliders are the text color, which stands out from the backgrounds
      // of any palette, and the minimap's is the stronger, so the two are told
      // apart where the scrollbar is drawn over it
      'minimapSlider.background': hexOf(theme.textPrimary, 0.14),
      'minimapSlider.hoverBackground': hexOf(theme.textPrimary, 0.22),
      'minimapSlider.activeBackground': hexOf(theme.textPrimary, 0.3),
      'scrollbar.background': '#00000000',
      'scrollbarSlider.background': hexOf(theme.textDim, 0.28),
      'scrollbarSlider.hoverBackground': hexOf(theme.textDim, 0.42),
      'scrollbarSlider.activeBackground': hexOf(theme.textDim, 0.56),
    },
  );
}
