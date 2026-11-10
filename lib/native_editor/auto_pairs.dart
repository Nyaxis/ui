import '../editor_core/anchor.dart' show Anchor;

/// a pair of brackets or quotes that a language has, and what is done with it
class BracketPair {
  const BracketPair(
    this.start,
    this.end, {
    this.close = true,
    this.surround = true,
    this.newline = false,
    this.notIn = const [],
  });

  /// the kinds of text in which the pair is not used, `string` and `comment`
  final List<String> notIn;

  /// what opens it
  final String start;

  /// what closes it
  final String end;

  /// whether [end] is typed after [start] is
  final bool close;

  /// whether selected text is put between them when [start] is typed
  final bool surround;

  /// whether enter between them puts the cursor on a line of its own, with
  /// [end] on the one below
  final bool newline;
}

/// the pairs of Luau
const List<BracketPair> luauBrackets = [
  BracketPair('{', '}', newline: true),
  BracketPair('[', ']', newline: true),
  BracketPair('(', ')', newline: true),
  BracketPair('"', '"', notIn: ['comment', 'string']),
  BracketPair("'", "'", notIn: ['comment', 'string']),
  BracketPair('`', '`', notIn: ['comment', 'string']),
  // these only open a line up when the end is there already
  BracketPair(
    'then',
    'end',
    close: false,
    surround: false,
    newline: true,
    notIn: ['comment', 'string'],
  ),
  BracketPair(
    'do',
    'end',
    close: false,
    surround: false,
    newline: true,
    notIn: ['comment', 'string'],
  ),
  BracketPair(
    'function',
    'end',
    close: false,
    surround: false,
    newline: true,
    notIn: ['comment', 'string'],
  ),
  BracketPair(
    'repeat',
    'until',
    close: false,
    surround: false,
    newline: true,
    notIn: ['comment', 'string'],
  ),
];

/// the characters before which a closer is typed, besides white space and the
/// end of the text
const String autocloseBefore = ';:.,=}])>';

/// whether a closer is typed in front of the character [unit], which is -1 at
/// the end of the text
bool autocloseBeforeUnit(int unit) {
  if (unit < 0) {
    return true;
  }
  if (unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d) {
    return true;
  }
  return autocloseBefore.codeUnits.contains(unit);
}

/// letters, digits and the underscore
bool isWordUnit(int unit) =>
    (unit >= 0x30 && unit <= 0x39) ||
    (unit >= 0x41 && unit <= 0x5a) ||
    (unit >= 0x61 && unit <= 0x7a) ||
    unit == 0x5f ||
    unit > 0x7f;

/// the closer a pair was given when its opener was typed, which is typed over
/// instead of again as long as the cursor stays between the two. [start] and
/// [end] are where the opener ends, and they take in what is typed between.
class AutocloseRegion {
  AutocloseRegion(this.start, this.end, this.pair);

  final Anchor start;
  final Anchor end;
  final BracketPair pair;
}
