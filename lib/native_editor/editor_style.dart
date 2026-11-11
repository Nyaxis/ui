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
    this.scrollbarWidth = 15,
    this.scrollbarTrack = const Color(0xFF11111B),
    this.scrollbarTrackBorder = const Color(0x12CDD6F4),
    this.scrollbarThumb = const Color(0x80585B70),
    this.scrollbarThumbHover = const Color(0xFF6C7086),
    this.scrollbarThumbActive = const Color(0x23FBFBEB),
    this.scrollbarMarker = const Color(0xFF94E2D5),
    this.roundedSelection = true,
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

  /// the width of a scrollbar, and the colors of its track and its thumb
  final double scrollbarWidth;
  final Color scrollbarTrack;
  final Color scrollbarTrackBorder;
  final Color scrollbarThumb;
  final Color scrollbarThumbHover;
  final Color scrollbarThumbActive;

  /// the color of the marks in the track for the other places a selected text
  /// is
  final Color scrollbarMarker;

  /// whether the corners of a selection are rounded
  final bool roundedSelection;

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
      // a wavy underline is drawn under the text by the editor, as the
      // decoration of a text is too small a wave
      decoration: TextDecoration.combine([
        if (style.underline == true && style.wavy != true)
          TextDecoration.underline,
        if (style.strikethrough == true) TextDecoration.lineThrough,
      ]),
      decorationColor: style.underlineColor == null
          ? null
          : Color(style.underlineColor!),
    );
  }
}
