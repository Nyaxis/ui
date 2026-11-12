import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart' show FocusNode;

import '../editor_core/buffer.dart';
import '../editor_core/display_map.dart';
import '../editor_core/patch.dart' show Bias;
import '../editor_core/point.dart';
import '../editor_core/rope.dart' show Rope;
import '../editor_core/selections_collection.dart';
import '../editor_core/text_metrics.dart';
import '../syntax/syntax_layer.dart';
import 'auto_pairs.dart';
import 'block_completion.dart';
import 'system_scrollbars.dart';

/// how bad something that a language server found is
enum DetailSeverity { error, warning, information, hint }

/// what the language server said about a place: the message, and where it
/// comes from, which is shown when the pointer rests on it
class DiagnosticDetail {
  const DiagnosticDetail({
    required this.range,
    required this.level,
    required this.message,
    this.source,
    this.code,
    this.codeHref,
  });

  final AnchorRange range;
  final DetailSeverity level;
  final String message;
  final String? source;
  final String? code;

  /// the page that explains the code
  final String? codeHref;
}

/// what the language server said about the symbol at a place: the text, in
/// markdown, and the range of the symbol, which is shown as lit when the
/// pointer rests on it
class HoverInfo {
  const HoverInfo({required this.range, required this.markdown});

  final AnchorRange range;
  final String markdown;
}

/// asks for what is said of the place at an offset of the text, which is null
/// when nothing is
typedef HoverProvider = Future<HoverInfo?> Function(int offset);

/// where the language server found something wrong, by how bad it is
class DiagnosticRanges {
  const DiagnosticRanges({
    this.errors = const [],
    this.warnings = const [],
    this.information = const [],
    this.hints = const [],
    this.unnecessary = const [],
    this.details = const [],
  });

  /// what was said about each, for the ones that are shown on hover
  final List<DiagnosticDetail> details;

  final List<AnchorRange> errors;
  final List<AnchorRange> warnings;
  final List<AnchorRange> information;
  final List<AnchorRange> hints;

  /// the code that the server says is not needed, which is drawn faded; it
  /// is also in the list of how bad it is, which is where its underline is
  final List<AnchorRange> unnecessary;
}

/// the colors that diagnostics are underlined in, `0xAARRGGBB`
class DiagnosticColors {
  const DiagnosticColors({
    this.error = 0xFFF38BA8,
    this.warning = 0xFFF9E2AF,
    this.information = 0xFF94E2D5,
    this.hint = 0xFF585B70,
  });

  final int error;
  final int warning;
  final int information;
  final int hint;

  @override
  bool operator ==(Object other) =>
      other is DiagnosticColors &&
      other.error == error &&
      other.warning == warning &&
      other.information == information &&
      other.hint == hint;

  @override
  int get hashCode => Object.hash(error, warning, information, hint);
}

/// an editor's text and everything that is done to it: the buffer, how it is
/// laid out on the screen, the selections, and where the view is scrolled to
class EditorController extends ChangeNotifier {
  EditorController({
    String text = '',
    int tabSize = 4,
    TextMetrics metrics = const CellMetrics(),
  }) : buffer = TextBuffer(text) {
    display = DisplayMap(buffer, tabSize: tabSize, metrics: metrics)
      ..addListener(_changed);
    selections = SelectionsCollection(buffer);
    buffer.addListener(_onBufferChange);
    showScrollbars();
  }

  /// whether the system wants scrollbars that are not used to go away, which
  /// is whether they are hidden a moment after being shown
  @visibleForTesting
  static bool systemAutoHide = systemAutoHidesScrollbars();

  /// whether the system hides scrollbars that are not used
  static bool get systemHidesScrollbars => systemAutoHide;

  static const _scrollbarsShownFor = Duration(seconds: 1);

  bool _scrollbarsShown = false;
  bool _disposed = false;
  Timer? _hideScrollbars;

  /// whether the scrollbars are shown at the moment: they are when the editor
  /// is made, and for a moment when the text scrolls or the pointer is at one
  /// of them. it is the editor's, so that a tab that is left and comes back
  /// has what it had
  bool get scrollbarsShown => _scrollbarsShown;

  @visibleForTesting
  set scrollbarsShown(bool value) {
    _hideScrollbars?.cancel();
    if (value != _scrollbarsShown) {
      _scrollbarsShown = value;
      notifyListeners();
    }
  }

  /// whether a thumb of a scrollbar is held, which the view says, as the
  /// scrollbars do not go while it is
  bool Function()? scrollbarHeld;

  /// shows the scrollbars, and hides them a moment later when the system hides
  /// scrollbars that are not used
  void showScrollbars() {
    if (_disposed) {
      return;
    }
    if (!_scrollbarsShown) {
      _scrollbarsShown = true;
      notifyListeners();
    }
    _hideScrollbars?.cancel();
    if (!systemAutoHide) {
      _hideScrollbars = null;
      return;
    }
    _hideScrollbars = Timer(_scrollbarsShownFor, () {
      if (_disposed) {
        return;
      }
      if (scrollbarHeld?.call() ?? false) {
        showScrollbars();
      } else {
        _scrollbarsShown = false;
        notifyListeners();
      }
    });
  }

  final TextBuffer buffer;
  late final DisplayMap display;
  late final SelectionsCollection selections;

  Highlights _highlights = Highlights.none;

  /// how scrolled the view is, in logical pixels
  double scrollX = 0;
  double scrollY = 0;

  /// whether the next layout is to scroll so that the cursor can be seen
  bool revealCursorRequested = false;

  /// whether the editor is focused, which the cursor is shown by
  bool hasFocus = false;

  /// whether the cursor is on the screen in its blinking
  bool cursorVisible = true;

  int _revision = 0;

  /// grows every time anything that is drawn changed
  int get revision => _revision;

  Highlights get highlights => _highlights;

  set highlights(Highlights value) {
    _highlights = value;
    _changed();
  }

  SyntaxLayer? _syntax;

  /// what the text is drawn by, from the grammar of the language
  SyntaxLayer? get syntax => _syntax;

  /// draws the text by [layer], or plain when it is null. the controller
  /// owns the layer from now on, and the one it had
  void setSyntax(SyntaxLayer? layer) {
    if (identical(layer, _syntax)) {
      return;
    }
    _syntax?.dispose();
    _syntax = layer;
    highlights = _highlights.withSyntax(layer);
  }

  /// draws everything again, which is for when what it is drawn with changed
  void redraw() => _changed();

  DisplaySnapshot get snapshot => display.snapshot;

  String get text => buffer.text.toString();

  void _changed() {
    _revision++;
    notifyListeners();
  }

  void _onBufferChange(BufferChange change) => _changed();

  /// the layout is to wrap at [columns] columns, or not at all
  void setWrapColumns(int? columns) {
    final width = columns?.toDouble();
    if (width == display.wrapWidth) {
      return;
    }
    display.setWrapWidth(width);
    // not told to the listeners: this is called while the view is laid out
    _revision++;
  }

  void setTabSize(int tabSize) {
    if (tabSize == display.tabSize) {
      return;
    }
    display.setTabSize(tabSize);
    _changed();
  }

  void setScroll({double? x, double? y}) {
    final newX = x ?? scrollX;
    final newY = y ?? scrollY;
    if (newX == scrollX && newY == scrollY) {
      return;
    }
    scrollX = newX;
    scrollY = newY;
    notifyListeners();
  }

  void requestRevealCursor() {
    revealCursorRequested = true;
    notifyListeners();
  }

  void setFocus(bool focused) {
    if (hasFocus == focused) {
      return;
    }
    hasFocus = focused;
    cursorVisible = true;
    notifyListeners();
  }

  void setCursorVisible(bool visible) {
    if (cursorVisible == visible) {
      return;
    }
    cursorVisible = visible;
    notifyListeners();
  }

  // editing

  /// replaces every selection with [text], and leaves a cursor after each
  void replaceSelections(String text) {
    final current = selections.all;
    if (current.isEmpty) {
      return;
    }
    final normalized = normalizeLineEndings(text);
    buffer.beginTransaction(selections.anchors);
    buffer.edit([
      for (final s in current) Replacement(s.start, s.end, normalized),
    ]);
    var delta = 0;
    final cursors = <Selection>[];
    for (final s in current) {
      final at = s.start + delta + normalized.length;
      cursors.add(selections.make(at, at));
      delta += normalized.length - (s.end - s.start);
    }
    selections.select(cursors);
    buffer.endTransaction(selections.anchors);
    requestRevealCursor();
  }

  /// whether brackets and quotes are typed in pairs: the closer comes with
  /// the opener when what follows allows it, selected text is put between
  /// them, the closer that came is typed over, and the pair is removed with
  /// one backspace while nothing has been typed in it
  bool autoClose = false;

  /// the closers that were typed with their openers, and are not left yet
  final List<AutocloseRegion> _autocloseRegions = [];

  /// the pairs of the language, which are looked at when a character is typed
  List<BracketPair> brackets = luauBrackets;

  @override
  void notifyListeners() {
    _dropAutocloseRegions();
    _refreshOccurrences(notify: false);
    _refreshMatchingBrackets();
    super.notifyListeners();
  }

  // the pair of brackets, or of the words of a block, that the cursor is in

  /// whether the pair that the cursor is in is lit
  bool highlightMatchingBrackets = true;

  /// how the two ends of the pair are drawn behind the text: `0xAARRGGBB`
  int get bracketBackground => _bracketBackground;

  int _bracketBackground = 0x4B44FFAA;

  set bracketBackground(int value) {
    if (value == _bracketBackground) {
      return;
    }
    _bracketBackground = value;
    final lit = _highlights.textHighlights[_bracketsKey]?.ranges;
    if (lit != null && lit.isNotEmpty) {
      _setBrackets(lit);
      _changed();
    }
  }

  /// the highlights of the pair go under this key
  static const int _bracketsKey = 8;

  /// where the pair was looked for last: in which text, and at which place
  Rope? _bracketsIn;
  int? _bracketsAt;

  /// the two ends of the pair that is lit, which are ranges of the text
  List<AnchorRange> get matchingBrackets =>
      _highlights.textHighlights[_bracketsKey]?.ranges ?? const [];

  void _setBrackets(List<AnchorRange> ranges) {
    _highlights = _highlights.withTextHighlight(
      _bracketsKey,
      ranges.isEmpty
          ? null
          : TextHighlight(
              HighlightStyle(background: _bracketBackground),
              ranges,
            ),
    );
    // the rows that were laid out have the old highlights in them
    _revision++;
  }

  /// lights the smallest pair that the cursor is in or at an edge of, which is
  /// not done while something is selected, as the pair is of the cursor
  void _refreshMatchingBrackets() {
    final layer = _syntax;
    final newest = selections.newest;
    if (!highlightMatchingBrackets || layer == null || !newest.isEmpty) {
      _bracketsIn = null;
      _bracketsAt = null;
      if (matchingBrackets.isNotEmpty) {
        _setBrackets(const []);
      }
      return;
    }
    final snapshot = buffer.snapshot;
    final head = newest.head;
    if (identical(snapshot.text, _bracketsIn) && head == _bracketsAt) {
      return;
    }
    if (!layer.isOf(snapshot)) {
      // the layer is told of an edit after this is, and is looked at again
      // when it has been
      scheduleMicrotask(() {
        if (!_disposed && identical(layer, _syntax)) {
          final before = matchingBrackets;
          _refreshMatchingBrackets();
          if (!identical(before, matchingBrackets)) {
            _changed();
          }
        }
      });
      return;
    }
    _bracketsIn = snapshot.text;
    _bracketsAt = head;
    final pair = layer.enclosingBrackets(snapshot, head, head);
    final lit = matchingBrackets;
    if (pair == null) {
      if (lit.isNotEmpty) {
        _setBrackets(const []);
      }
      return;
    }
    AnchorRange range(int start, int end) => AnchorRange(
      buffer.anchorAt(start, Bias.right),
      buffer.anchorAt(end, Bias.left),
    );
    _setBrackets([
      range(pair.openStart, pair.openEnd),
      range(pair.closeStart, pair.closeEnd),
    ]);
  }

  // the other places in the text where the selected text is

  /// whether those are highlighted
  bool highlightSelectedText = true;

  /// how they are drawn behind the text: `0xAARRGGBB`
  int get occurrenceBackground => _occurrenceBackground;

  int _occurrenceBackground = 0x17CBA6F7;

  set occurrenceBackground(int value) {
    if (value == _occurrenceBackground) {
      return;
    }
    _occurrenceBackground = value;
    final ranges = occurrences;
    if (ranges.isNotEmpty) {
      _setOccurrences(ranges);
      _changed();
    }
  }

  /// the highlights go under this key, which no other highlight has
  static const int _occurrencesKey = 1;

  /// the diagnostics go under these keys, from the least to the most severe, so
  /// that the worse one is on top where they cover the same text
  static const int _hintsKey = 2;
  static const int _informationKey = 3;
  static const int _warningsKey = 4;
  static const int _errorsKey = 5;

  /// the fade of unused code has a key of its own, as it is not a color
  static const int _unnecessaryKey = 6;

  /// the symbol that the pointer rests on, while what is said of it is shown
  static const int _hoverKey = 7;

  /// asks what the language server says of the symbol at an offset
  HoverProvider? hoverProvider;

  /// how the symbol under a popover is drawn behind the text: `0xAARRGGBB`
  int hoverBackground = 0x4D44475A;

  /// the range of the symbol that is lit, or null
  AnchorRange? get hoverRange =>
      _highlights.textHighlights[_hoverKey]?.ranges.firstOrNull;

  /// lights the symbol in [range], or puts the light out for null
  void setHoverRange(AnchorRange? range) {
    // a view that is closed after its editor has nothing to put out
    if (_disposed) {
      return;
    }
    _highlights = _highlights.withTextHighlight(
      _hoverKey,
      range == null
          ? null
          : TextHighlight(HighlightStyle(background: hoverBackground), [range]),
    );
    _changed();
  }

  /// the most that unused code can be faded
  static const double maxUnnecessaryCodeFade = 0.9;

  double _unnecessaryCodeFade = 0.3;

  /// how much unused code is faded, from 0 to [maxUnnecessaryCodeFade]
  double get unnecessaryCodeFade => _unnecessaryCodeFade;

  set unnecessaryCodeFade(double value) {
    final fade = value.clamp(0.0, maxUnnecessaryCodeFade);
    if (fade == _unnecessaryCodeFade) {
      return;
    }
    _unnecessaryCodeFade = fade;
    _applyDiagnostics();
  }

  /// what the language server found wrong, by how bad it is
  var _diagnostics = const DiagnosticRanges();

  /// what the language server found wrong, where
  DiagnosticRanges get diagnosticRanges => _diagnostics;

  /// what the server said about the place at [offset]: of those that have it
  /// between their ends, the one with the shortest range, as the most specific
  DiagnosticDetail? diagnosticAt(int offset) {
    final snapshot = buffer.snapshot;
    DiagnosticDetail? best;
    var bestLength = 0;
    for (final detail in _diagnostics.details) {
      final start = snapshot.offsetForAnchor(detail.range.start);
      final end = snapshot.offsetForAnchor(detail.range.end);
      if (offset < start || offset > end) {
        continue;
      }
      if (best == null || end - start < bestLength) {
        best = detail;
        bestLength = end - start;
      }
    }
    return best;
  }

  /// whether it found anything at all
  bool get hasDiagnostics =>
      _diagnostics.errors.isNotEmpty ||
      _diagnostics.warnings.isNotEmpty ||
      _diagnostics.information.isNotEmpty ||
      _diagnostics.hints.isNotEmpty;

  DiagnosticColors _diagnosticColors = const DiagnosticColors();

  DiagnosticColors get diagnosticColors => _diagnosticColors;

  set diagnosticColors(DiagnosticColors value) {
    if (value == _diagnosticColors) {
      return;
    }
    _diagnosticColors = value;
    _applyDiagnostics();
  }

  /// underlines the places that a language server found wrong: a wavy line of
  /// one pixel in the color of how bad it is
  void setDiagnostics(DiagnosticRanges diagnostics) {
    _diagnostics = diagnostics;
    _applyDiagnostics();
  }

  void _applyDiagnostics() {
    TextHighlight? underline(List<AnchorRange> ranges, int color) =>
        ranges.isEmpty
        ? null
        : TextHighlight(
            HighlightStyle(underline: true, underlineColor: color, wavy: true),
            ranges,
          );
    final colors = _diagnosticColors;
    _highlights = _highlights
        .withTextHighlight(
          _hintsKey,
          underline(_diagnostics.hints, colors.hint),
        )
        .withTextHighlight(
          _informationKey,
          underline(_diagnostics.information, colors.information),
        )
        .withTextHighlight(
          _warningsKey,
          underline(_diagnostics.warnings, colors.warning),
        )
        .withTextHighlight(
          _errorsKey,
          underline(_diagnostics.errors, colors.error),
        )
        .withTextHighlight(
          _unnecessaryKey,
          _diagnostics.unnecessary.isEmpty
              ? null
              : TextHighlight(
                  HighlightStyle(fadeOut: _unnecessaryCodeFade),
                  _diagnostics.unnecessary,
                ),
        );
    _changed();
  }

  /// a text that is longer is searched a moment after the selection is made,
  /// and not at once
  static const int _quickSearchLength = 100000;

  /// the places the selected text is, other than where it is selected
  List<AnchorRange> get occurrences =>
      _highlights.textHighlights[_occurrencesKey]?.ranges ?? const [];

  /// what the occurrences are of, and the text they were found in
  String? _occurrencesOf;
  Rope? _occurrencesIn;
  (int, int)? _occurrencesAt;
  Timer? _occurrenceSearch;

  void _setOccurrences(List<AnchorRange> ranges) {
    _highlights = _highlights.withTextHighlight(
      _occurrencesKey,
      ranges.isEmpty
          ? null
          : TextHighlight(
              HighlightStyle(background: _occurrenceBackground),
              ranges,
            ),
    );
    // the rows that were laid out have the old highlights in them, which they
    // keep when the cursor moves, as nothing else tells the view that they
    // changed
    _revision++;
  }

  /// looks for the selected text when it is one that is looked for: one
  /// selection, of something that is not blank, in one row
  void _refreshOccurrences({required bool notify}) {
    final all = selections.all;
    String? query;
    (int, int)? at;
    if (highlightSelectedText && all.length == 1) {
      final s = all.first;
      final text = buffer.text;
      if (!s.isEmpty && text.rowAt(s.start) == text.rowAt(s.end)) {
        final selected = text.substring(s.start, s.end);
        if (selected.trim().isNotEmpty) {
          query = selected;
          at = (s.start, s.end);
        }
      }
    }
    if (query == null || at == null) {
      _occurrenceSearch?.cancel();
      _occurrencesOf = null;
      _occurrencesIn = null;
      _occurrencesAt = null;
      if (occurrences.isNotEmpty) {
        _setOccurrences(const []);
        if (notify) {
          _changed();
        }
      }
      return;
    }
    final text = buffer.text;
    if (_occurrencesOf == query &&
        _occurrencesAt == at &&
        identical(_occurrencesIn, text)) {
      return;
    }
    _occurrencesOf = query;
    _occurrencesAt = at;
    _occurrencesIn = text;
    _occurrenceSearch?.cancel();
    if (text.length <= _quickSearchLength) {
      _findOccurrences(query, at, text, notify: notify);
    } else {
      _occurrenceSearch = Timer(const Duration(milliseconds: 100), () {
        _findOccurrences(query!, at!, text, notify: true);
      });
    }
  }

  void _findOccurrences(
    String query,
    (int, int) at,
    Rope text, {
    required bool notify,
  }) {
    // the text is another one by now
    if (!identical(buffer.text, text)) {
      return;
    }
    final snapshot = buffer.snapshot;
    final found = text.toString();
    final ranges = <AnchorRange>[];
    var from = 0;
    while (true) {
      final index = found.indexOf(query, from);
      if (index < 0) {
        break;
      }
      from = index + query.length;
      // the selection itself is not one of them
      if (index != at.$1) {
        ranges.add(snapshot.anchorRangeInside(index, index + query.length));
      }
    }
    _setOccurrences(ranges);
    if (notify) {
      _changed();
    }
  }

  /// forgets the regions that no selection touches any more, or that the
  /// text took away
  void _dropAutocloseRegions() {
    if (_autocloseRegions.isEmpty) {
      return;
    }
    final snapshot = buffer.snapshot;
    final all = selections.all;
    _autocloseRegions.removeWhere((region) {
      if (!snapshot.isValid(region.start) || !snapshot.isValid(region.end)) {
        return true;
      }
      final start = snapshot.offsetForAnchor(region.start);
      final end = snapshot.offsetForAnchor(region.end);
      return !all.any((s) => s.end >= start && s.start <= end);
    });
  }

  /// the closest region that [s] is in
  AutocloseRegion? _regionAround(Selection s) {
    final snapshot = buffer.snapshot;
    AutocloseRegion? found;
    var foundSize = 1 << 62;
    for (final region in _autocloseRegions) {
      final start = snapshot.offsetForAnchor(region.start);
      final end = snapshot.offsetForAnchor(region.end);
      if (s.end >= start && s.start <= end && end - start < foundSize) {
        found = region;
        foundSize = end - start;
      }
    }
    return found;
  }

  /// the opener and the closer of the pair that the cursor [s] is at the start
  /// of, when it is the region of a closer that came with its opener
  (int, int)? _autocloseRangeAt(Selection s) {
    final region = _regionAround(s);
    if (region == null) {
      return null;
    }
    final snapshot = buffer.snapshot;
    final start = snapshot.offsetForAnchor(region.start);
    final end = snapshot.offsetForAnchor(region.end);
    final opener = region.pair.start;
    final closer = region.pair.end;
    if (s.start != start || start < opener.length) {
      return null;
    }
    final rope = buffer.text;
    if (end + closer.length > rope.length ||
        rope.substring(start - opener.length, start) != opener ||
        rope.substring(end, end + closer.length) != closer) {
      return null;
    }
    return (start - opener.length, end + closer.length);
  }

  /// types [text], which is a character that was pressed. with [autoClose] a
  /// bracket or quote brings its closer when the text around allows it, wraps
  /// what is selected, and the closer that it brought is passed over instead
  /// of typed again.
  void typeText(String text) {
    final current = selections.all;
    if (!autoClose || current.isEmpty || text.length != 1) {
      replaceSelections(text);
      return;
    }
    _dropAutocloseRegions();
    // the pair that the text opens, and else the one that it closes
    BracketPair? openedPair;
    BracketPair? closed;
    for (final pair in brackets) {
      if (!pair.close && !pair.surround) {
        continue;
      }
      if (pair.start == text) {
        openedPair = pair;
        break;
      }
      if (pair.end == text) {
        closed ??= pair;
      }
    }
    final pair = openedPair ?? closed;
    if (pair == null) {
      replaceSelections(text);
      return;
    }

    final rope = buffer.text;
    final snapshot = buffer.snapshot;
    final edits = <Replacement>[];
    // each cursor as it will be, and where a region starts when it is to have one
    final cursors = <(int, int)>[];
    final newRegions = <(int, BracketPair)>[];
    var delta = 0;
    for (final s in current) {
      final next = s.end < rope.length ? rope.codeUnitAt(s.end) : -1;
      final previous = s.start > 0 ? rope.codeUnitAt(s.start - 1) : -1;
      // a pair that is not used in a string or a comment is not opened there,
      // but its closer is still typed over
      var opened = openedPair;
      if (opened != null && opened.notIn.isNotEmpty) {
        final scope = _syntax?.scopeAt(snapshot, s.reversed ? s.start : s.end);
        if (scope != null &&
            ((scope.comment && opened.notIn.contains('comment')) ||
                (scope.string && opened.notIn.contains('string')))) {
          opened = null;
        }
      }
      if (s.isEmpty) {
        if (opened != null) {
          final row = rope.rowAt(s.start);
          final lineStart = rope.lineStart(row);
          // a quote after a word is not the start of a string
          final precedingAllows =
              s.start == lineStart ||
              opened.start != opened.end ||
              !isWordUnit(previous);
          // an odd number of the quote before it means it ends a string
          final closing =
              opened.start == opened.end &&
              opened.start.length == 1 &&
              opened.start
                  .allMatches(rope.substring(lineStart, s.start))
                  .length
                  .isOdd;
          if (opened.close &&
              autocloseBeforeUnit(next) &&
              precedingAllows &&
              !closing) {
            edits.add(Replacement(s.start, s.start, '$text${opened.end}'));
            cursors.add((s.start + delta + 1, s.start + delta + 1));
            newRegions.add((s.start + delta + 1, opened));
            delta += 1 + opened.end.length;
            continue;
          }
        }
        final region = _regionAround(s);
        if (region != null &&
            text == region.pair.end &&
            s.start == snapshot.offsetForAnchor(region.end) &&
            next == text.codeUnitAt(0)) {
          // the closer that came with the opener, typed over
          cursors.add((s.start + delta + 1, s.start + delta + 1));
          continue;
        }
      } else if (opened != null &&
          opened.surround &&
          opened.start.length == 1) {
        // what is selected stays selected, between the pair
        edits.add(
          Replacement(
            s.start,
            s.end,
            '$text${rope.substring(s.start, s.end)}${opened.end}',
          ),
        );
        cursors.add((s.start + delta + 1, s.end + delta + 1));
        delta += 1 + opened.end.length;
        continue;
      }
      edits.add(Replacement(s.start, s.end, text));
      cursors.add((s.start + delta + 1, s.start + delta + 1));
      delta += 1 - (s.end - s.start);
    }
    if (edits.isEmpty) {
      selections.select([for (final (a, b) in cursors) selections.make(a, b)]);
      requestRevealCursor();
      return;
    }
    buffer.beginTransaction(selections.anchors);
    buffer.edit(edits);
    selections.select([for (final (a, b) in cursors) selections.make(a, b)]);
    buffer.endTransaction(selections.anchors);
    final after = buffer.snapshot;
    for (final (position, newPair) in newRegions) {
      _autocloseRegions.add(
        AutocloseRegion(
          after.anchorBefore(position),
          after.anchorAfter(position),
          newPair,
        ),
      );
    }
    requestRevealCursor();
  }

  /// deletes each selection, or when it is a cursor the character before it
  void backspace() => _delete(forward: false);

  /// deletes each selection, or when it is a cursor the character after it
  void deleteForward() => _delete(forward: true);

  void _delete({required bool forward}) {
    final current = selections.all;
    final ranges = <(int, int)>[];
    for (final s in current) {
      if (!s.isEmpty) {
        ranges.add((s.start, s.end));
      } else if (forward) {
        final to = _next(s.start);
        if (to > s.start) {
          ranges.add((s.start, to));
        }
      } else if (autoClose && _autocloseRangeAt(s) != null) {
        // at the start of the closer that came with an opener, backspace takes
        // the pair
        ranges.add(_autocloseRangeAt(s)!);
      } else {
        final from = _previous(s.start);
        if (from < s.start) {
          ranges.add((from, s.start));
        }
      }
    }
    if (ranges.isEmpty) {
      return;
    }
    buffer.beginTransaction(selections.anchors);
    buffer.edit([for (final (a, b) in ranges) Replacement(a, b, '')]);
    selections.select([
      for (final s in selections.all) selections.make(s.head, s.head),
    ]);
    buffer.endTransaction(selections.anchors);
    requestRevealCursor();
  }

  void undo() {
    final transaction = buffer.undo();
    if (transaction?.selectionsBefore != null) {
      selections.selectAnchors(transaction!.selectionsBefore!);
    }
    requestRevealCursor();
  }

  void redo() {
    final transaction = buffer.redo();
    if (transaction?.selectionsAfter != null) {
      selections.selectAnchors(transaction!.selectionsAfter!);
    }
    requestRevealCursor();
  }

  // moving

  int _previous(int offset) =>
      offset <= 0 ? 0 : buffer.text.clipOffset(offset - 1, Bias.left);

  int _next(int offset) => offset >= buffer.length
      ? buffer.length
      : buffer.text.clipOffset(offset + 1, Bias.right);

  /// moves the head of every selection one character, a selection being
  /// made smaller to a cursor at the edge it moves toward when it is not
  /// [extend]ed
  void moveHorizontally({required bool forward, bool extend = false}) {
    selections.select([
      for (final s in selections.all)
        if (extend)
          s.withHead(forward ? _next(s.head) : _previous(s.head))
        else if (!s.isEmpty)
          selections.make(forward ? s.end : s.start, forward ? s.end : s.start)
        else
          selections.make(
            forward ? _next(s.head) : _previous(s.head),
            forward ? _next(s.head) : _previous(s.head),
          ),
    ]);
    requestRevealCursor();
  }

  /// moves the head of every selection to the same column of the row above
  /// or below, as far as it has one, remembering the column it came from
  void moveVertically({required bool down, bool extend = false}) =>
      moveByRows(down ? 1 : -1, extend: extend);

  /// moves to the start of the row, or with [toEnd] to its end
  void moveToRowEdge({required bool toEnd, bool extend = false}) {
    final shown = snapshot;
    selections.select([
      for (final s in selections.all)
        () {
          final head = shown.offsetToDisplayPoint(s.head);
          final column = toEnd ? shown.lineLen(head.row) : 0;
          final offset = shown.displayPointToOffset(
            shown.clipPoint(
              Point(head.row, column),
              toEnd ? Bias.left : Bias.right,
            ),
          );
          return extend ? s.withHead(offset) : s.collapseTo(offset);
        }(),
    ]);
    requestRevealCursor();
  }

  void selectAll() {
    selections.selectRanges([(0, buffer.length)]);
    requestRevealCursor();
  }

  /// how many rows are in view, which the page keys move by
  int viewportRows = 20;

  /// puts the selected text on the clipboard; with nothing selected, the
  /// whole line of each cursor
  Future<void> copy() async {
    final text = _textToCopy();
    if (text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  /// copies, and then deletes what was copied
  Future<void> cut() async {
    final text = _textToCopy();
    if (text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    final source = buffer.text;
    final ranges = <(int, int)>[];
    for (final s in selections.all) {
      if (!s.isEmpty) {
        ranges.add((s.start, s.end));
      } else {
        final row = source.rowAt(s.head);
        ranges.add((
          source.lineStart(row),
          math.min(source.length, source.lineEnd(row) + 1),
        ));
      }
    }
    _deleteRanges(ranges);
  }

  /// puts the text of the clipboard in the place of the selections; when it
  /// has as many lines as there are cursors, each gets one
  Future<void> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      return;
    }
    final lines = normalizeLineEndings(text).split('\n');
    final current = selections.all;
    if (current.length > 1 && lines.length == current.length) {
      buffer.beginTransaction(selections.anchors);
      buffer.edit([
        for (var i = 0; i < current.length; i++)
          Replacement(current[i].start, current[i].end, lines[i]),
      ]);
      var delta = 0;
      final cursors = <Selection>[];
      for (var i = 0; i < current.length; i++) {
        final at = current[i].start + delta + lines[i].length;
        cursors.add(selections.make(at, at));
        delta += lines[i].length - (current[i].end - current[i].start);
      }
      selections.select(cursors);
      buffer.endTransaction(selections.anchors);
      requestRevealCursor();
      return;
    }
    replaceSelections(text);
  }

  String _textToCopy() {
    final text = buffer.text;
    return selections.all
        .map(
          (s) => s.isEmpty
              ? '${text.lineText(text.rowAt(s.head))}\n'
              : text.substring(s.start, s.end),
        )
        .join('\n');
  }

  /// the text that is selected, the selections one under another
  String selectedText() => selections.all
      .where((s) => !s.isEmpty)
      .map((s) => buffer.text.substring(s.start, s.end))
      .join('\n');

  // more editing

  /// whether Tab puts in a tab character, and not the spaces to the next stop
  bool useTabs = false;

  /// the focus of the view that shows this text, which is kept here so that
  /// whatever opens the editor can give it the focus back
  final FocusNode focusNode = FocusNode(debugLabel: 'editor');

  void focus() => focusNode.requestFocus();

  /// puts the cursor at [line] and [column], which are counted from 1, as
  /// far as the text has them
  void goToLineColumn(int line, [int column = 1]) {
    final text = buffer.text;
    final row = (line - 1).clamp(0, text.lineCount - 1);
    final at = text.pointToOffset(Point(row, math.max(0, column - 1)));
    selections.selectRanges([(at, at)]);
    requestRevealCursor();
  }

  /// indents the text with [spaces] or tabs, [size] wide. the indentation it
  /// has keeps its levels, each as wide as the tab size was, and a remainder
  /// that is not a whole level stays as spaces
  void setIndentation({required bool spaces, required int size}) {
    final old = display.tabSize;
    final text = buffer.text;
    final edits = <Replacement>[];
    for (var row = 0; row < text.lineCount; row++) {
      final start = text.lineStart(row);
      final end = text.lineEnd(row);
      var lead = start;
      while (lead < end && _isSpace(text.codeUnitAt(lead))) {
        lead++;
      }
      if (lead == start) {
        continue;
      }
      var columns = 0;
      for (var i = start; i < lead; i++) {
        columns += text.codeUnitAt(i) == 0x09 ? old - columns % old : 1;
      }
      final levels = columns ~/ old;
      final replacement =
          (spaces ? ' ' * (levels * size) : '\t' * levels) +
          ' ' * (columns % old);
      if (replacement != text.substring(start, lead)) {
        edits.add(Replacement(start, lead, replacement));
      }
    }
    useTabs = !spaces;
    setTabSize(size);
    if (edits.isNotEmpty) {
      buffer.finalizeLastTransaction();
      buffer.edit(edits);
      buffer.finalizeLastTransaction();
    }
    notifyListeners();
  }

  static bool _isSpace(int unit) => unit == 0x20 || unit == 0x09;

  static bool _isWordUnit(int unit) =>
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A) ||
      unit == 0x5F ||
      unit > 0x7F;

  int _classOf(int unit) => _isWordUnit(unit) ? 0 : 2;

  /// the offset that a word further on is at: past the spaces after [offset],
  /// and then past the word or the run of signs that comes next; the end of a
  /// line is a stop of its own
  int nextWordBoundary(int offset) {
    final text = buffer.text;
    var at = offset;
    if (at >= text.length) {
      return text.length;
    }
    if (text.codeUnitAt(at) == 0x0A) {
      return at + 1;
    }
    while (at < text.length && _isSpace(text.codeUnitAt(at))) {
      at++;
    }
    if (at >= text.length || text.codeUnitAt(at) == 0x0A) {
      return at;
    }
    final kind = _classOf(text.codeUnitAt(at));
    while (at < text.length &&
        text.codeUnitAt(at) != 0x0A &&
        !_isSpace(text.codeUnitAt(at)) &&
        _classOf(text.codeUnitAt(at)) == kind) {
      at++;
    }
    return text.clipOffset(at, Bias.right);
  }

  /// the offset that a word before [offset] starts at
  int previousWordBoundary(int offset) {
    final text = buffer.text;
    var at = offset;
    if (at <= 0) {
      return 0;
    }
    if (text.codeUnitAt(at - 1) == 0x0A) {
      return at - 1;
    }
    while (at > 0 && _isSpace(text.codeUnitAt(at - 1))) {
      at--;
    }
    if (at <= 0 || text.codeUnitAt(at - 1) == 0x0A) {
      return at;
    }
    final kind = _classOf(text.codeUnitAt(at - 1));
    while (at > 0 &&
        text.codeUnitAt(at - 1) != 0x0A &&
        !_isSpace(text.codeUnitAt(at - 1)) &&
        _classOf(text.codeUnitAt(at - 1)) == kind) {
      at--;
    }
    return text.clipOffset(at, Bias.left);
  }

  void moveByWord({required bool forward, bool extend = false}) {
    selections.select([
      for (final s in selections.all)
        () {
          final target = forward
              ? nextWordBoundary(s.head)
              : previousWordBoundary(s.head);
          if (extend) {
            return s.withHead(target);
          }
          if (!s.isEmpty) {
            final edge = forward ? s.end : s.start;
            return selections.make(edge, edge);
          }
          return selections.make(target, target);
        }(),
    ]);
    requestRevealCursor();
  }

  void deleteWord({required bool forward}) {
    final ranges = <(int, int)>[];
    for (final s in selections.all) {
      if (!s.isEmpty) {
        ranges.add((s.start, s.end));
      } else {
        final other = forward
            ? nextWordBoundary(s.head)
            : previousWordBoundary(s.head);
        if (other != s.head) {
          ranges.add((math.min(other, s.head), math.max(other, s.head)));
        }
      }
    }
    _deleteRanges(ranges);
  }

  void _deleteRanges(List<(int, int)> ranges) {
    if (ranges.isEmpty) {
      return;
    }
    buffer.beginTransaction(selections.anchors);
    buffer.edit([for (final (a, b) in ranges) Replacement(a, b, '')]);
    selections.select([
      for (final s in selections.all) selections.make(s.head, s.head),
    ]);
    buffer.endTransaction(selections.anchors);
    requestRevealCursor();
  }

  /// deletes from the cursors to the end of their lines
  void deleteToLineEnd() {
    final ranges = <(int, int)>[];
    for (final s in selections.all) {
      final end = buffer.text.lineEnd(buffer.text.rowAt(s.head));
      if (!s.isEmpty) {
        ranges.add((s.start, s.end));
      } else if (end > s.head) {
        ranges.add((s.head, end));
      } else if (end < buffer.length) {
        ranges.add((end, end + 1));
      }
    }
    _deleteRanges(ranges);
  }

  /// whether enter at the end of a line that opens a block of Luau indents
  /// the next line, and puts in what the block is missing: `then`, `do` and
  /// its `end`
  bool completeBlocks = false;

  /// what the line the cursor at [offset] is at the end of asks for, or null
  BlockCompletion? _completionAt(int offset, int row, int lineStart) {
    final text = buffer.text;
    final lineEnd = text.lineEnd(row);
    // only at the end of a line, not in the middle of it
    if (text.substring(offset, lineEnd).trim().isNotEmpty) {
      return null;
    }
    String? nextLine;
    for (var next = row + 1; next <= text.rowAt(text.length); next++) {
      final candidate = text.lineText(next);
      if (candidate.trim().isNotEmpty) {
        nextLine = candidate;
        break;
      }
    }
    return completeBlock(text.substring(lineStart, offset), nextLine: nextLine);
  }

  /// whether [start] to [end], with the blanks around it, is between the two
  /// brackets of a pair that wants a line of its own for what goes between
  bool _betweenBrackets(int start, int end) {
    final text = buffer.text;
    var before = start;
    while (before > 0 && _isSpace(text.codeUnitAt(before - 1))) {
      before--;
    }
    var after = end;
    while (after < text.length && _isSpace(text.codeUnitAt(after))) {
      after++;
    }
    for (final pair in brackets) {
      if (!pair.newline) {
        continue;
      }
      final opener = pair.start.trimRight();
      final closer = pair.end.trimLeft();
      if (before >= opener.length &&
          after + closer.length <= text.length &&
          text.substring(before - opener.length, before) == opener &&
          text.substring(after, after + closer.length) == closer) {
        return true;
      }
    }
    return false;
  }

  /// puts in a new line, with the indent of the line it is made in
  void insertNewline() {
    final current = selections.all;
    if (current.isEmpty) {
      return;
    }
    final text = buffer.text;
    final inserted = <String>[];
    // where the cursor is in each of them
    final cursorAt = <int>[];
    final unit = useTabs ? '\t' : ' ' * display.tabSize;
    for (final s in current) {
      final row = text.rowAt(s.start);
      final lineStart = text.lineStart(row);
      var indentEnd = lineStart;
      while (indentEnd < s.start && _isSpace(text.codeUnitAt(indentEnd))) {
        indentEnd++;
      }
      final indent = text.substring(lineStart, indentEnd);
      // between the brackets of a pair, which go on a line of their own
      if (autoClose && _betweenBrackets(s.start, s.end)) {
        inserted.add('\n$indent$unit\n$indent');
        cursorAt.add(1 + indent.length + unit.length);
        continue;
      }
      final completion = completeBlocks && s.isEmpty
          ? _completionAt(s.start, row, lineStart)
          : null;
      if (completion == null) {
        inserted.add('\n$indent');
        cursorAt.add(inserted.last.length);
        continue;
      }
      var suffix = completion.suffix;
      // no second space when the line ends with one
      if (s.start > lineStart && _isSpace(text.codeUnitAt(s.start - 1))) {
        suffix = suffix.trimLeft();
      }
      final body = '\n$indent$unit';
      cursorAt.add(suffix.length + body.length);
      inserted.add(
        '$suffix$body${completion.closer == null ? '' : '\n$indent${completion.closer}'}',
      );
    }
    buffer.beginTransaction(selections.anchors);
    buffer.edit([
      for (var i = 0; i < current.length; i++)
        Replacement(current[i].start, current[i].end, inserted[i]),
    ]);
    var delta = 0;
    final cursors = <Selection>[];
    for (var i = 0; i < current.length; i++) {
      final at = current[i].start + delta + cursorAt[i];
      cursors.add(selections.make(at, at));
      delta += inserted[i].length - (current[i].end - current[i].start);
    }
    selections.select(cursors);
    buffer.endTransaction(selections.anchors);
    requestRevealCursor();
  }

  /// Tab: puts in the spaces to the next stop, or a tab character; when
  /// lines are selected they are indented instead
  void insertTab() {
    final current = selections.all;
    final text = buffer.text;
    if (current.any(
      (s) => !s.isEmpty && text.rowAt(s.start) != text.rowAt(s.end),
    )) {
      indentLines();
      return;
    }
    final size = display.tabSize;
    final inserted = <String>[];
    for (final s in current) {
      if (useTabs) {
        inserted.add('\t');
      } else {
        final column = s.start - text.lineStart(text.rowAt(s.start));
        inserted.add(' ' * (size - column % size));
      }
    }
    buffer.beginTransaction(selections.anchors);
    buffer.edit([
      for (var i = 0; i < current.length; i++)
        Replacement(current[i].start, current[i].end, inserted[i]),
    ]);
    var delta = 0;
    final cursors = <Selection>[];
    for (var i = 0; i < current.length; i++) {
      final at = current[i].start + delta + inserted[i].length;
      cursors.add(selections.make(at, at));
      delta += inserted[i].length - (current[i].end - current[i].start);
    }
    selections.select(cursors);
    buffer.endTransaction(selections.anchors);
    requestRevealCursor();
  }

  /// indents every line the selections touch, or with [outdent] takes one
  /// level of indent off each
  void indentLines({bool outdent = false}) {
    final text = buffer.text;
    final rows = <int>{};
    for (final s in selections.all) {
      final first = text.rowAt(s.start);
      var last = text.rowAt(s.end);
      // a selection that ends at the start of a line does not touch it
      if (last > first && s.end == text.lineStart(last)) {
        last--;
      }
      for (var row = first; row <= last; row++) {
        rows.add(row);
      }
    }
    final size = display.tabSize;
    final edits = <Replacement>[];
    for (final row in rows.toList()..sort()) {
      final start = text.lineStart(row);
      if (!outdent) {
        if (text.lineLength(row) > 0) {
          edits.add(Replacement.insert(start, useTabs ? '\t' : ' ' * size));
        }
        continue;
      }
      if (text.lineLength(row) > 0 && text.codeUnitAt(start) == 0x09) {
        edits.add(Replacement(start, start + 1, ''));
        continue;
      }
      var end = start;
      while (end < start + size &&
          end < text.length &&
          text.codeUnitAt(end) == 0x20) {
        end++;
      }
      if (end > start) {
        edits.add(Replacement(start, end, ''));
      }
    }
    if (edits.isEmpty) {
      return;
    }
    buffer.beginTransaction(selections.anchors);
    buffer.edit(edits);
    buffer.endTransaction(selections.anchors);
    requestRevealCursor();
  }

  /// moves like [moveVertically] by [rows] rows
  void moveByRows(int rows, {bool extend = false}) {
    final shown = snapshot;
    final next = <Selection>[];
    for (final s in selections.all) {
      final head = shown.offsetToDisplayPoint(s.head);
      final goal = s.goal is HorizontalPosition
          ? (s.goal as HorizontalPosition).x.round()
          : head.column;
      final row = head.row + rows;
      final int target;
      if (row < 0) {
        target = 0;
      } else if (row >= shown.rowCount) {
        target = buffer.length;
      } else {
        final point = shown.clipPoint(
          Point(row, math.min(goal, shown.lineLen(row))),
          rows > 0 ? Bias.right : Bias.left,
        );
        target = shown.displayPointToOffset(point);
      }
      final goalValue = HorizontalPosition(goal.toDouble());
      next.add(
        extend
            ? s.withHead(target, goalValue)
            : s.collapseTo(target, goalValue),
      );
    }
    selections.select(next);
    requestRevealCursor();
  }

  /// moves to the start of the text, or with [toEnd] to its end
  void moveToDocumentEdge({required bool toEnd, bool extend = false}) {
    final target = toEnd ? buffer.length : 0;
    selections.select([
      for (final s in selections.all)
        extend ? s.withHead(target) : s.collapseTo(target),
    ]);
    requestRevealCursor();
  }

  /// a click: puts the only cursor at [offset]; with [extend] the selection
  /// is made to reach it, and with [add] one more cursor is put there
  void clickAt(int offset, {bool extend = false, bool add = false}) {
    if (add) {
      selections.addCursor(offset);
    } else if (extend) {
      final newest = selections.newest;
      selections.select([newest.withHead(offset)]);
    } else {
      selections.selectRanges([(offset, offset)]);
    }
    notifyListeners();
  }

  /// a drag: the head of the newest selection follows the pointer
  void dragTo(int offset) {
    final newest = selections.newest;
    final others = selections.all.where((s) => s.id != newest.id);
    selections.select([...others, newest.withHead(offset)]);
    requestRevealCursor();
  }

  /// the range of the word at [offset], or of the spaces or signs there
  (int, int) wordRangeAt(int offset) {
    final text = buffer.text;
    if (text.isEmpty) {
      return (0, 0);
    }
    final at = math.min(offset, text.length);
    // the character after the offset, or the one before at the end of a line
    final index = at < text.length && text.codeUnitAt(at) != 0x0A
        ? at
        : math.max(0, at - 1);
    final unit = text.codeUnitAt(index);
    if (unit == 0x0A) {
      return (at, at);
    }
    int kindOf(int u) => _isSpace(u) ? 1 : _classOf(u);
    final kind = kindOf(unit);
    var start = index;
    while (start > 0 &&
        text.codeUnitAt(start - 1) != 0x0A &&
        kindOf(text.codeUnitAt(start - 1)) == kind) {
      start--;
    }
    var end = index + 1;
    while (end < text.length &&
        text.codeUnitAt(end) != 0x0A &&
        kindOf(text.codeUnitAt(end)) == kind) {
      end++;
    }
    return (
      text.clipOffset(start, Bias.left),
      text.clipOffset(end, Bias.right),
    );
  }

  /// selects the word at [offset]
  void selectWordAt(int offset, {bool add = false}) {
    final (start, end) = wordRangeAt(offset);
    final made = selections.make(start, end);
    selections.select(add ? [...selections.all, made] : [made]);
    notifyListeners();
  }

  /// selects the whole line at [offset], with its line ending
  void selectLineAt(int offset, {bool add = false}) {
    final text = buffer.text;
    final row = text.rowAt(offset);
    final start = text.lineStart(row);
    final end = math.min(text.length, text.lineEnd(row) + 1);
    final made = selections.make(start, end);
    selections.select(add ? [...selections.all, made] : [made]);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _hideScrollbars?.cancel();
    buffer.removeListener(_onBufferChange);
    _occurrenceSearch?.cancel();
    _syntax?.dispose();
    _syntax = null;
    display.dispose();
    focusNode.dispose();
    super.dispose();
  }
}
