import 'dart:math' as math;
import 'dart:ui';

/// which way a scrollbar goes
enum ScrollbarAxis { horizontal, vertical }

/// when the scrollbars are shown. auto shows them while there is something to
/// mark in them or a cursor is out of sight, and otherwise as the system says;
/// system does as the system says, which is to hide them a moment after the
/// text was last scrolled, and to bring them back for scrolling or for the
/// pointer at them, or to leave them shown
enum ScrollbarVisibility {
  auto,
  system,
  always,
  never;

  /// the one that [id] names, and [orElse] for another
  static ScrollbarVisibility fromId(
    String? id, {
    ScrollbarVisibility orElse = auto,
  }) {
    for (final value in values) {
      if (value.name == id) {
        return value;
      }
    }
    return orElse;
  }
}

/// which diagnostics have a mark in the track: the ones that are as bad as
/// this, or worse
enum ScrollbarDiagnostics {
  all,
  information,
  warning,
  error,
  none;

  /// the one that [id] names, `true` for all and `false` for none, and
  /// [orElse] for another
  static ScrollbarDiagnostics fromJson(
    Object? id, {
    ScrollbarDiagnostics orElse = all,
  }) {
    if (id is bool) {
      return id ? all : none;
    }
    for (final value in values) {
      if (value.name == id) {
        return value;
      }
    }
    return orElse;
  }

  /// whether a diagnostic that is [rank] bad is marked, where an error is 0, a
  /// warning 1, information 2 and a hint 3
  bool shows(int rank) => switch (this) {
    all => true,
    information => rank <= 2,
    warning => rank <= 1,
    error => rank == 0,
    none => false,
  };
}

/// what the scrollbars show and when: the settings of the scrollbar of an
/// editor
class ScrollbarSettings {
  const ScrollbarSettings({
    this.show = ScrollbarVisibility.always,
    this.cursors = true,
    this.searchResults = true,
    this.selectedText = true,
    this.selectedSymbol = true,
    this.diagnostics = ScrollbarDiagnostics.all,
    this.horizontal = true,
    this.vertical = true,
  });

  /// the settings that a `scrollbar` object of `config.json` says, and the
  /// default for what it does not say
  factory ScrollbarSettings.fromJson(Object? json) {
    const defaults = ScrollbarSettings(show: ScrollbarVisibility.auto);
    if (json is! Map) {
      return defaults;
    }
    bool flag(Object? value, bool fallback) => value is bool ? value : fallback;
    final axes = json['axes'] is Map ? json['axes'] as Map : const {};
    return ScrollbarSettings(
      show: ScrollbarVisibility.fromId(json['show'] as String?),
      cursors: flag(json['cursors'], defaults.cursors),
      searchResults: flag(json['searchResults'], defaults.searchResults),
      selectedText: flag(json['selectedText'], defaults.selectedText),
      selectedSymbol: flag(json['selectedSymbol'], defaults.selectedSymbol),
      diagnostics: ScrollbarDiagnostics.fromJson(json['diagnostics']),
      horizontal: flag(axes['horizontal'], defaults.horizontal),
      vertical: flag(axes['vertical'], defaults.vertical),
    );
  }

  /// when the scrollbars are shown
  final ScrollbarVisibility show;

  /// whether the cursors are marked in the track
  final bool cursors;

  /// whether the places that a search found are marked
  final bool searchResults;

  /// whether the other places that the selected text is are marked
  final bool selectedText;

  /// whether the other places that the selected symbol is are marked
  final bool selectedSymbol;

  /// which diagnostics are marked
  final ScrollbarDiagnostics diagnostics;

  /// when false, there is no scrollbar that goes along, whatever else is set
  final bool horizontal;

  /// when false, there is no scrollbar that goes down, whatever else is set
  final bool vertical;

  ScrollbarSettings copyWith({
    ScrollbarVisibility? show,
    bool? cursors,
    bool? searchResults,
    bool? selectedText,
    bool? selectedSymbol,
    ScrollbarDiagnostics? diagnostics,
    bool? horizontal,
    bool? vertical,
  }) => ScrollbarSettings(
    show: show ?? this.show,
    cursors: cursors ?? this.cursors,
    searchResults: searchResults ?? this.searchResults,
    selectedText: selectedText ?? this.selectedText,
    selectedSymbol: selectedSymbol ?? this.selectedSymbol,
    diagnostics: diagnostics ?? this.diagnostics,
    horizontal: horizontal ?? this.horizontal,
    vertical: vertical ?? this.vertical,
  );

  Map<String, Object> toJson() => {
    'show': show.name,
    'cursors': cursors,
    'searchResults': searchResults,
    'selectedText': selectedText,
    'selectedSymbol': selectedSymbol,
    'diagnostics': diagnostics.name,
    'axes': {'horizontal': horizontal, 'vertical': vertical},
  };

  @override
  bool operator ==(Object other) =>
      other is ScrollbarSettings &&
      other.show == show &&
      other.cursors == cursors &&
      other.searchResults == searchResults &&
      other.selectedText == selectedText &&
      other.selectedSymbol == selectedSymbol &&
      other.diagnostics == diagnostics &&
      other.horizontal == horizontal &&
      other.vertical == vertical;

  @override
  int get hashCode => Object.hash(
    show,
    cursors,
    searchResults,
    selectedText,
    selectedSymbol,
    diagnostics,
    horizontal,
    vertical,
  );
}

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
