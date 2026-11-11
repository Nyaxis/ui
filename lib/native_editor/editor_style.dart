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
    this.popoverText = const TextStyle(
      fontSize: 13,
      height: 1.4,
      color: Color(0xFFCDD6F4),
    ),
    this.popoverSurface = const Color(0xFF181825),
    this.popoverRadius = 8,
    this.popoverMuted = const Color(0xFF9399B2),
    this.popoverSuccess = const Color(0xFFA6E3A1),
  });

  /// the color of a button in a popover, and of it once it has done its work
  final Color popoverMuted;
  final Color popoverSuccess;

  /// the text of what pops up over the editor, in the font of the interface
  final TextStyle popoverText;

  /// what a popup is on, which a color of how bad a diagnostic is lies over
  final Color popoverSurface;
  final double popoverRadius;

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
    // the color is taken first and then faded, so that the text keeps the
    // color of its syntax
    var color = style.color == null ? null : Color(style.color!);
    final fade = style.fadeOut;
    if (fade != null) {
      final base = color ?? textStyle.color ?? const Color(0xFF000000);
      color = base.withValues(alpha: base.a * (1 - fade.clamp(0.0, 1.0)));
    }
    return textStyle.copyWith(
      color: color,
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
