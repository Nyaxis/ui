import 'buffer.dart' show AnchorRange, BufferSnapshot;

/// how a piece of text is drawn, apart from the font: the colors are `0xAARRGGBB`
class HighlightStyle {
  const HighlightStyle({
    this.color,
    this.background,
    this.bold,
    this.italic,
    this.underline,
    this.underlineColor,
    this.wavy,
    this.strikethrough,
  });

  final int? color;
  final int? background;
  final bool? bold;
  final bool? italic;
  final bool? underline;

  /// the color of the underline, which is the color of the text when null
  final int? underlineColor;

  /// whether the underline is wavy, as Zed draws that of a diagnostic
  final bool? wavy;
  final bool? strikethrough;

  /// this style with everything that [other] sets taken from it
  HighlightStyle merge(HighlightStyle other) => HighlightStyle(
    color: other.color ?? color,
    background: other.background ?? background,
    bold: other.bold ?? bold,
    italic: other.italic ?? italic,
    underline: other.underline ?? underline,
    underlineColor: other.underlineColor ?? underlineColor,
    wavy: other.wavy ?? wavy,
    strikethrough: other.strikethrough ?? strikethrough,
  );

  @override
  bool operator ==(Object other) =>
      other is HighlightStyle &&
      other.color == color &&
      other.background == background &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.underlineColor == underlineColor &&
      other.wavy == wavy &&
      other.strikethrough == strikethrough;

  @override
  int get hashCode => Object.hash(
    color,
    background,
    bold,
    italic,
    underline,
    underlineColor,
    wavy,
    strikethrough,
  );

  @override
  String toString() =>
      'HighlightStyle(color: $color, background: $background, bold: $bold, '
      'italic: $italic, underline: $underline, '
      'underlineColor: $underlineColor, wavy: $wavy, '
      'strikethrough: $strikethrough)';
}

/// ranges of the buffer that are drawn in [style], such as the matches of a
/// search or the text that is selected in another view. the ranges are in the
/// order of where they start.
class TextHighlight {
  const TextHighlight(this.style, this.ranges);

  final HighlightStyle style;
  final List<AnchorRange> ranges;
}

/// a range of the buffer that a language server gave a style, such as a
/// function name. of tokens that cover the same text, the one with the
/// highest [precedence] is drawn.
class SemanticToken {
  const SemanticToken(this.range, this.style, this.precedence);

  final AnchorRange range;
  final HighlightStyle style;
  final int precedence;
}

/// a part of the text with the style of what it is in the syntax of the
/// language, as offsets of the text
class SyntaxSpan {
  const SyntaxSpan(this.start, this.end, this.style);

  final int start;
  final int end;
  final HighlightStyle style;

  @override
  String toString() => 'SyntaxSpan($start, $end, $style)';
}

/// where the syntax of the text says what is drawn how, for the parts of it
/// that are asked for; it is under all else that text is drawn with
abstract interface class SyntaxHighlights {
  /// the spans from [start] to [end] of the text of [buffer], in order and
  /// not over each other. it has none when it is not of that text
  List<SyntaxSpan> spans(BufferSnapshot buffer, int start, int end);
}

/// everything that text is drawn with besides its own look
class Highlights {
  const Highlights({
    this.textHighlights = const {},
    this.semanticTokens = const [],
    this.syntax,
  });

  static const none = Highlights();

  /// what the grammar of the language says, which is under everything else
  final SyntaxHighlights? syntax;

  /// by a key that says what made them; of those that cover the same text,
  /// the one with the higher key is on top, as the keys are ordered
  final Map<int, TextHighlight> textHighlights;

  /// in the order of where they start
  final List<SemanticToken> semanticTokens;

  bool get isEmpty =>
      textHighlights.isEmpty && semanticTokens.isEmpty && syntax == null;

  /// the same, with other syntax highlights
  Highlights withSyntax(SyntaxHighlights? syntax) => Highlights(
    textHighlights: textHighlights,
    semanticTokens: semanticTokens,
    syntax: syntax,
  );

  /// the same, with [highlight] under [key], or without what is under it when
  /// it is null
  Highlights withTextHighlight(int key, TextHighlight? highlight) {
    final highlights = Map.of(textHighlights);
    if (highlight == null) {
      highlights.remove(key);
    } else {
      highlights[key] = highlight;
    }
    return Highlights(
      textHighlights: highlights,
      semanticTokens: semanticTokens,
      syntax: syntax,
    );
  }
}

/// below the key of every other highlight
const int _syntaxKey = -(1 << 41);

class _Endpoint {
  _Endpoint(this.offset, this.key, this.style);

  final int offset;

  /// text highlights have the key they are given, and semantic tokens a key
  /// above all of those that grows with their precedence
  final int key;
  final HighlightStyle? style;
}

const int _semanticKeyBase = 1 << 40;

/// the text of [buffer] from [start] to [end], cut where a highlight starts
/// or ends, each piece with the style the highlights that are on it come to
Iterable<(String, HighlightStyle?)> highlightedBufferText(
  BufferSnapshot buffer,
  int start,
  int end,
  Iterable<String> pieces,
  Highlights highlights,
) sync* {
  if (highlights.isEmpty) {
    for (final piece in pieces) {
      yield (piece, null);
    }
    return;
  }
  final endpoints = _endpoints(buffer, start, end, highlights);
  var next = endpoints.length - 1;
  final active = <int, HighlightStyle>{};
  var offset = start;
  for (final piece in pieces) {
    var rest = piece;
    while (rest.isNotEmpty) {
      var nextEndpoint = 1 << 62;
      while (next >= 0) {
        final endpoint = endpoints[next];
        if (endpoint.offset <= offset) {
          final style = endpoint.style;
          if (style != null) {
            active[endpoint.key] = style;
          } else {
            active.remove(endpoint.key);
          }
          next--;
        } else {
          nextEndpoint = endpoint.offset;
          break;
        }
      }
      final split = rest.length < nextEndpoint - offset
          ? rest.length
          : nextEndpoint - offset;
      yield (rest.substring(0, split), _merged(active));
      offset += split;
      rest = rest.substring(split);
    }
  }
}

/// the highlights that are on a piece of text laid over each other, in the
/// order of their keys; of semantic tokens only the top one counts
HighlightStyle? _merged(Map<int, HighlightStyle> active) {
  if (active.isEmpty) {
    return null;
  }
  final keys = active.keys.toList()..sort();
  HighlightStyle? out;
  for (var i = 0; i < keys.length; i++) {
    final key = keys[i];
    if (key >= _semanticKeyBase &&
        i + 1 < keys.length &&
        keys[i + 1] >= _semanticKeyBase) {
      continue;
    }
    out = out == null ? active[key] : out.merge(active[key]!);
  }
  return out;
}

/// the starts and ends of the highlights that touch [start] to [end], the
/// last to be met first
List<_Endpoint> _endpoints(
  BufferSnapshot buffer,
  int start,
  int end,
  Highlights highlights,
) {
  final endpoints = <_Endpoint>[];
  final from = buffer.anchorAfter(start);
  final to = buffer.anchorAfter(end);

  /// the index of the first range that does not end before [from]
  int firstAtOrAfter(List<AnchorRange> ranges) {
    var low = 0;
    var high = ranges.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (buffer.compareAnchors(ranges[middle].end, from) < 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  void add(AnchorRange range, int key, HighlightStyle style) {
    final a = buffer.offsetForAnchor(range.start);
    final b = buffer.offsetForAnchor(range.end);
    if (a == b) {
      return;
    }
    endpoints.add(_Endpoint(a, key, style));
    endpoints.add(_Endpoint(b, key, null));
  }

  final syntax = highlights.syntax;
  if (syntax != null) {
    // the spans do not overlap, so they can share a key
    for (final span in syntax.spans(buffer, start, end)) {
      endpoints.add(_Endpoint(span.start, _syntaxKey, span.style));
      endpoints.add(_Endpoint(span.end, _syntaxKey, null));
    }
  }

  for (final MapEntry(:key, :value) in highlights.textHighlights.entries) {
    final ranges = value.ranges;
    for (var i = firstAtOrAfter(ranges); i < ranges.length; i++) {
      if (buffer.compareAnchors(ranges[i].start, to) > 0) {
        break;
      }
      add(ranges[i], key, value.style);
    }
  }
  final tokens = highlights.semanticTokens;
  var low = 0;
  var high = tokens.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (buffer.compareAnchors(tokens[middle].range.end, from) < 0) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  for (var i = low; i < tokens.length; i++) {
    if (buffer.compareAnchors(tokens[i].range.start, to) > 0) {
      break;
    }
    add(
      tokens[i].range,
      _semanticKeyBase + tokens[i].precedence,
      tokens[i].style,
    );
  }

  // the one that comes first is last; at the same place a style that ends
  // comes before one that starts
  endpoints.sort((a, b) {
    final byOffset = b.offset.compareTo(a.offset);
    if (byOffset != 0) {
      return byOffset;
    }
    final aEnds = a.style == null ? 1 : 0;
    final bEnds = b.style == null ? 1 : 0;
    final byEnds = aEnds.compareTo(bEnds);
    return byEnds != 0 ? byEnds : a.key.compareTo(b.key);
  });
  return endpoints;
}
