import 'dart:math' as math;
import 'dart:ui';

/// which way a scrollbar goes
enum ScrollbarAxis { horizontal, vertical }

/// what the pointer is doing to the thumb of a scrollbar
enum ThumbState { idle, hovered, dragging }

/// where a scrollbar is: its track, and the thumb in it. positions along the
/// text are in units, which are rows for the vertical one and columns for the
/// horizontal one, so that [unitSize] is how far the thumb goes for each unit
/// that the text scrolls.
class ScrollbarLayout {
  const ScrollbarLayout({
    required this.axis,
    required this.track,
    required this.visibleStart,
    required this.visibleUnits,
    required this.unitSize,
    required this.thumb,
  });

  /// the thumb is never smaller than this
  static const minThumbSize = 25.0;

  /// the width of the line between the text and a vertical track
  static const borderWidth = 1.0;

  final ScrollbarAxis axis;

  /// the whole of the scrollbar, which the thumb moves in
  final Rect track;

  /// the unit at the start of what is shown, and how many units are shown
  final double visibleStart;
  final double visibleUnits;

  /// how far the thumb moves for one unit
  final double unitSize;

  /// null when everything is shown
  final Rect? thumb;

  /// the scrollbar of a [track] for a text that is [scrollRange] long, of
  /// which [viewportSize] is shown from [scrollPosition] units on. a unit is
  /// [glyph] long, and the thumb starts [contentOffset] into the track.
  factory ScrollbarLayout.compute({
    required ScrollbarAxis axis,
    required Rect track,
    required double viewportSize,
    required double scrollRange,
    required double glyph,
    required double scrollPosition,
    double contentOffset = 0,
  }) {
    final vertical = axis == ScrollbarAxis.vertical;
    // the track the thumb has to move in
    final trackLength = (vertical ? track.height : track.width) - contentOffset;

    final unitsPerPage = viewportSize / glyph;
    final visibleStart = scrollPosition;
    final totalUnits = scrollRange / glyph;

    final thumbPercentage = unitsPerPage / totalUnits;
    final thumbSize = math.min(
      math.max(trackLength * thumbPercentage, minThumbSize),
      trackLength,
    );

    final divisor = math.max(totalUnits - unitsPerPage, 0.0);
    final largerThanViewport = divisor > 0;
    final unitSize = largerThanViewport
        ? (trackLength - thumbSize) / divisor
        : glyph;

    Rect? thumb;
    if (largerThanViewport) {
      final start = contentOffset + visibleStart * unitSize;
      thumb = vertical
          ? Rect.fromLTWH(track.left, track.top + start, track.width, thumbSize)
          : Rect.fromLTWH(
              track.left + start,
              track.top,
              thumbSize,
              track.height,
            );
    }
    return ScrollbarLayout(
      axis: axis,
      track: track,
      visibleStart: visibleStart,
      visibleUnits: unitsPerPage,
      unitSize: unitSize,
      thumb: thumb,
    );
  }

  double _along(Offset position) =>
      axis == ScrollbarAxis.vertical ? position.dy : position.dx;

  bool thumbHovered(Offset position) =>
      thumb != null && thumb!.contains(position);

  /// the position, in units, of text that the thumb was dragged [delta] pixels
  /// from where it was, which is not less than none
  double draggedPosition(double delta) =>
      math.max(0, visibleStart + delta / unitSize);

  /// the position, in units, of text that the track was pressed at [position],
  /// outside of the thumb: what is shown goes to be around it
  double clickedPosition(Offset position) {
    final origin = axis == ScrollbarAxis.vertical ? track.top : track.left;
    final center = ((_along(position) - origin) / unitSize).round();
    final half = visibleUnits.floor() ~/ 2;
    return math.max(0, center - half).toDouble();
  }
}
