import 'dart:math' as math;

import 'package:characters/characters.dart';

import '../text_metrics.dart';
import 'invisibles.dart';
import 'line_breaker.dart';

/// how the rows that a wrapped line continues on are indented
class IndentAdjustment {
  /// the rows start at the first column
  const IndentAdjustment.noIndent() : _kind = 0, extra = 0;

  /// the rows start where the text of the line starts
  const IndentAdjustment.sameIndent() : _kind = 1, extra = 0;

  /// the rows start [extra] columns after where the text of the line starts
  const IndentAdjustment.extraColumns(this.extra) : _kind = 2;

  final int _kind;
  final int extra;

  @override
  bool operator ==(Object other) =>
      other is IndentAdjustment && other._kind == _kind && other.extra == extra;

  @override
  int get hashCode => Object.hash(_kind, extra);
}

/// a place where a line wraps: the row after it starts at [ix] of the line,
/// after [nextIndent] columns of indent
class Boundary {
  const Boundary(this.ix, this.nextIndent);

  final int ix;
  final int nextIndent;

  @override
  bool operator ==(Object other) =>
      other is Boundary && other.ix == ix && other.nextIndent == nextIndent;

  @override
  int get hashCode => Object.hash(ix, nextIndent);

  @override
  String toString() => 'Boundary($ix, indent $nextIndent)';
}

/// wraps lines of text to a width, by the widths that [metrics] gives the
/// characters
class LineWrapper {
  LineWrapper(this.metrics);

  /// the most a wrapped row is indented
  static const int maxIndent = 256;

  final TextMetrics metrics;
  final Map<int, double> _widths = {};

  double _widthOf(int rune) => _widths[rune] ??= metrics.advance(rune);

  /// where [line] wraps to fit in [wrapWidth]
  List<Boundary> wrapLine(
    String line,
    double wrapWidth, [
    IndentAdjustment indentAdjustment = const IndentAdjustment.sameIndent(),
  ]) => wrapFragments(fragmentsFor(line), wrapWidth, indentAdjustment);

  /// [line] in fragments, in which each character that looks like nothing and
  /// is shown as another has the width of that other
  List<LineFragment> fragmentsFor(String line) {
    var hasInvisible = false;
    for (var i = 0; i < line.length; i++) {
      final unit = line.codeUnitAt(i);
      if (unit < 0x20 ? isInvisible(unit) : unit >= 0x7F) {
        hasInvisible = true;
        break;
      }
    }
    if (!hasInvisible) {
      return [LineFragment.text(line)];
    }
    final fragments = <LineFragment>[];
    final graphemes = _GraphemeStarts(line);
    var runStart = 0;
    var i = 0;
    while (i < line.length) {
      var rune = line.codeUnitAt(i);
      var length = 1;
      if (rune >= 0xD800 &&
          rune <= 0xDBFF &&
          i + 1 < line.length &&
          line.codeUnitAt(i + 1) >= 0xDC00 &&
          line.codeUnitAt(i + 1) <= 0xDFFF) {
        rune =
            0x10000 +
            ((rune - 0xD800) << 10) +
            (line.codeUnitAt(i + 1) - 0xDC00);
        length = 2;
      }
      final shown = isInvisible(rune) ? replacement(rune) : null;
      if (shown != null &&
          graphemes.startsAt(i) &&
          graphemes.startsAt(i + length)) {
        if (runStart < i) {
          fragments.add(LineFragment.text(line.substring(runStart, i)));
        }
        fragments.add(LineFragment.element(_widthOf(shown), length));
        runStart = i + length;
      }
      i += length;
    }
    if (runStart < line.length || fragments.isEmpty) {
      fragments.add(LineFragment.text(line.substring(runStart)));
    }
    return fragments;
  }

  /// where a line made of [fragments] wraps to fit in [wrapWidth]
  List<Boundary> wrapFragments(
    List<LineFragment> fragments,
    double wrapWidth, [
    IndentAdjustment indentAdjustment = const IndentAdjustment.sameIndent(),
  ]) {
    final boundaries = <Boundary>[];
    var width = 0.0;
    int? firstNonWhitespaceIx;
    int? baseIndent;
    var lastCandidateIx = 0;
    var lastCandidateWidth = 0.0;
    var lastWrapIx = 0;
    var graphemeIndex = 0;
    var widthBeforeGrapheme = 0.0;
    final space = _widthOf(0x20);

    // the text that the places to break at are found in: what is not text
    // stands in it as letters, which keeps it with the words next to it
    final String text;
    if (fragments.length == 1 && fragments.single.text != null) {
      text = fragments.single.text!;
    } else {
      final buffer = StringBuffer();
      for (final fragment in fragments) {
        buffer.write(fragment.text ?? 'a' * fragment.length);
      }
      text = buffer.toString();
    }
    final graphemes = _GraphemeStarts(text);
    final breaks = LineBreaks.of(text);

    /// takes one character, or one thing that is not text, which starts at
    /// [at] of the line and is [itemWidth] wide
    void take(int at, int rune, double? elementWidth) {
      final isGraphemeBoundary = graphemes.startsAt(at);
      if (isGraphemeBoundary) {
        graphemeIndex = at;
        widthBeforeGrapheme = width;
      }
      if (at > 0 &&
          isGraphemeBoundary &&
          firstNonWhitespaceIx != null &&
          breaks.canBreakAt(at)) {
        lastCandidateIx = at;
        lastCandidateWidth = width;
      }
      final double itemWidth;
      if (elementWidth != null) {
        firstNonWhitespaceIx ??= at;
        itemWidth = elementWidth;
      } else {
        if (rune == 0x0A) {
          return;
        }
        if (rune != 0x20 && firstNonWhitespaceIx == null) {
          firstNonWhitespaceIx = at;
        }
        itemWidth = _widthOf(rune);
      }

      width += itemWidth;
      if (width > wrapWidth && graphemeIndex > lastWrapIx) {
        final wrapAtCandidate =
            lastCandidateIx > lastWrapIx &&
            width - lastCandidateWidth <= wrapWidth;
        final carriedWidth = wrapAtCandidate
            ? width - lastCandidateWidth
            : width - widthBeforeGrapheme;

        // the indent is that of the first character of the line that is not
        // a space, and is kept for every row the line wraps to. a line whose
        // spaces wrap before any other character has no indent to keep.
        final first = firstNonWhitespaceIx;
        if (baseIndent == null && first != null) {
          baseIndent = math.min(maxIndent, math.max(0, first - lastWrapIx));
        }

        final base = baseIndent;
        final int nextIndent;
        if (indentAdjustment == const IndentAdjustment.noIndent()) {
          nextIndent = 0;
        } else if (indentAdjustment == const IndentAdjustment.sameIndent()) {
          nextIndent = base ?? 0;
        } else if (base == null) {
          nextIndent = 0;
        } else {
          final candidate = base + indentAdjustment.extra;
          // room is left for what is carried over from the row before, and
          // for a wide character at the least, so that the row that is
          // continued on is not too wide at once
          final headroom = math.max(carriedWidth, space * 2);
          nextIndent = space * candidate + headroom > wrapWidth
              ? 0
              : math.min(maxIndent, candidate);
        }

        if (wrapAtCandidate) {
          lastWrapIx = lastCandidateIx;
          width -= lastCandidateWidth;
          widthBeforeGrapheme -= lastCandidateWidth;
        } else {
          // a character that is too wide by itself is kept whole
          lastWrapIx = graphemeIndex;
          width -= widthBeforeGrapheme;
          widthBeforeGrapheme = 0;
        }
        lastCandidateIx = 0;

        final indentWidth = space * nextIndent;
        width += indentWidth;
        widthBeforeGrapheme += indentWidth;
        boundaries.add(Boundary(lastWrapIx, nextIndent));
      }
    }

    var start = 0;
    for (final fragment in fragments) {
      final fragmentText = fragment.text;
      if (fragmentText == null) {
        take(start, 0x61, fragment.width);
        start += fragment.length;
        continue;
      }
      var ix = 0;
      while (ix < fragmentText.length) {
        var rune = fragmentText.codeUnitAt(ix);
        var length = 1;
        if (rune >= 0xD800 &&
            rune <= 0xDBFF &&
            ix + 1 < fragmentText.length &&
            fragmentText.codeUnitAt(ix + 1) >= 0xDC00 &&
            fragmentText.codeUnitAt(ix + 1) <= 0xDFFF) {
          rune =
              0x10000 +
              ((rune - 0xD800) << 10) +
              (fragmentText.codeUnitAt(ix + 1) - 0xDC00);
          length = 2;
        }
        take(start + ix, rune, null);
        ix += length;
      }
      start += fragmentText.length;
    }
    return boundaries;
  }
}

/// a part of a line to be wrapped: text, or something that is not text and
/// has a width of its own, such as what is shown in place of a fold
class LineFragment {
  const LineFragment.text(String this.text) : width = 0, _length = 0;

  /// something [width] wide that takes [length] code units of the line
  const LineFragment.element(this.width, int length)
    : text = null,
      _length = length;

  final String? text;
  final double width;
  final int _length;

  int get length => text?.length ?? _length;
}

/// says where the characters of a text start, a character being all that is
/// drawn as one: a letter with its accents, or the parts of an emoji
class _GraphemeStarts {
  _GraphemeStarts(String text)
    : _range = _simple(text) ? null : text.characters.iterator {
    final range = _range;
    if (range != null) {
      _next = range.moveNext() ? range.stringBeforeLength : _end;
    }
  }

  static const int _end = 0x7FFFFFFFFFFFFFFF;

  final CharacterRange? _range;
  int _next = 0;

  /// a text of only these has one character to a code unit
  static bool _simple(String text) {
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) >= 0x300) {
        return false;
      }
    }
    return true;
  }

  /// whether a character starts at [index]; asked with indexes in order
  bool startsAt(int index) {
    final range = _range;
    if (range == null) {
      return true;
    }
    while (_next < index) {
      _next = range.moveNext() ? range.stringBeforeLength : _end;
    }
    return _next == index;
  }
}
