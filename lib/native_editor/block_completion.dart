/// what to do when enter is pressed at the end of a line that opens a block of
/// Luau, such as `if x then` or `function f()`
class BlockCompletion {
  const BlockCompletion({this.suffix = '', this.closer});

  /// what is typed at the end of the line first, such as ` then`
  final String suffix;

  /// what goes on a line of its own below the new one, such as `end`; null
  /// when the block is closed already
  final String? closer;

  @override
  String toString() => 'BlockCompletion(suffix: "$suffix", closer: $closer)';
}

int _width(String line) {
  var width = 0;
  for (var i = 0; i < line.length; i++) {
    final c = line.codeUnitAt(i);
    if (c == 0x20) {
      width++;
    } else if (c == 0x09) {
      width += 4;
    } else {
      break;
    }
  }
  return width;
}

int _count(String text, String char) => char.allMatches(text).length;

/// whether a keyword can be typed after the line without changing what it
/// says, which it cannot when the line goes on in the next one
bool _safeToAppend(String trimmed) {
  if (_count(trimmed, '(') != _count(trimmed, ')') ||
      _count(trimmed, '{') != _count(trimmed, '}') ||
      _count(trimmed, '[') != _count(trimmed, ']')) {
    return false;
  }
  return !RegExp(r'(\band|\bor|\bnot|[-+*/%^=<>~,(.{\[:])$').hasMatch(trimmed);
}

/// what [line], which is a line of text up to where enter is pressed, asks
/// for, or null when it does not open a block. [nextLine] is the first line
/// below it that is not blank, which says whether the block has its end
/// already.
BlockCompletion? completeBlock(String line, {String? nextLine}) {
  // a comment may be about anything, and a line with one is left alone
  if (line.contains('--')) {
    return null;
  }
  final trimmed = line.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  var suffix = '';
  String? closer;
  var opens = false;

  final conditional = RegExp(r'^(if|elseif)\b').hasMatch(trimmed);
  final loop = RegExp(r'^(for|while)\b').hasMatch(trimmed);
  if (conditional || loop) {
    final keyword = conditional ? 'then' : 'do';
    final has = RegExp('\\b$keyword\\b').hasMatch(trimmed);
    if (has) {
      // `if x then return end` is a whole statement
      if (!trimmed.endsWith(keyword)) {
        return null;
      }
    } else if (_safeToAppend(trimmed)) {
      suffix = ' $keyword';
    } else {
      return null;
    }
    opens = true;
    // elseif belongs to an if that has its end
    closer = trimmed.startsWith('elseif') ? null : 'end';
  } else if (trimmed == 'do') {
    opens = true;
    closer = 'end';
  } else if (trimmed == 'else' || trimmed == 'repeat') {
    opens = true;
  } else if (RegExp(r'^(local\s+)?function\b').hasMatch(trimmed)) {
    if (!RegExp(r'\)\s*(:\s*[\w.?<>,|\s]+)?$').hasMatch(trimmed)) {
      return null;
    }
    opens = true;
    closer = 'end';
  } else if (RegExp(r'\bfunction\s*\([^()]*\)\s*(:\s*[\w.?]+)?$')
      .hasMatch(trimmed)) {
    // a function that is an argument: its call is closed after its end
    opens = true;
    final open = _count(trimmed, '(') - _count(trimmed, ')');
    closer = 'end${')' * (open > 0 ? open : 0)}';
  }
  if (!opens) {
    return null;
  }

  if (closer != null && nextLine != null) {
    final next = nextLine.trim();
    final nextWidth = _width(nextLine);
    final here = _width(line);
    final closedAlready =
        nextWidth > here ||
        (nextWidth == here &&
            RegExp(r'^(end|else|elseif|until)\b').hasMatch(next));
    if (closedAlready) {
      closer = null;
    }
  }
  return BlockCompletion(suffix: suffix, closer: closer);
}
