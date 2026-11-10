import 'package:flutter/painting.dart';

import '../editor_core/highlight.dart';

/// how the editor looks
class EditorStyle {
  const EditorStyle({
    this.textStyle = const TextStyle(
      fontFamily: 'JetBrainsMono',
      fontFamilyFallback: ['Consolas', 'Menlo', 'monospace'],
      fontSize: 13,
      height: 1.5,
      color: Color(0xFFCDD6F4),
    ),
    this.background = const Color(0xFF1E1E2E),
    this.selection = const Color(0x55585B70),
    this.cursor = const Color(0xFFF5E0DC),
    this.currentLine = const Color(0x14FFFFFF),
    this.gutterText = const Color(0xFF6C7086),
    this.currentGutterText = const Color(0xFFCDD6F4),
    this.invisible = const Color(0xFF6C7086),
    this.gutterPadding = 12,
    this.textPadding = 8,
    this.cursorWidth = 2,
  });

  /// the font of the text, whose width is the width of a column
  final TextStyle textStyle;
  final Color background;
  final Color selection;
  final Color cursor;
  final Color currentLine;
  final Color gutterText;
  final Color currentGutterText;

  /// the color of the symbols shown for characters that look like nothing
  final Color invisible;
  final double gutterPadding;
  final double textPadding;
  final double cursorWidth;

  /// [style] as it is to be drawn on top of the text style
  TextStyle apply(HighlightStyle? style) {
    if (style == null) {
      return textStyle;
    }
    return textStyle.copyWith(
      color: style.color == null ? null : Color(style.color!),
      backgroundColor: style.background == null
          ? null
          : Color(style.background!),
      fontWeight: style.bold == true ? FontWeight.w700 : null,
      fontStyle: style.italic == true ? FontStyle.italic : null,
      decoration: TextDecoration.combine([
        if (style.underline == true) TextDecoration.underline,
        if (style.strikethrough == true) TextDecoration.lineThrough,
      ]),
    );
  }
}
