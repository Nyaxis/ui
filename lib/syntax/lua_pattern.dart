/// the regular expression that matches what a Lua pattern does, for the
/// patterns the highlight queries of the grammars use: anchors, sets, the
/// classes `%a %d %l %s %u %w %x %p`, escapes, groups and the quantifiers
/// `* + - ?`. it is not a full implementation: the balance `%b`, the frontier
/// `%f` and back references are not supported, and the query then never
/// matches.
RegExp? luaPatternToRegExp(String pattern) {
  final out = StringBuffer();
  var i = 0;

  String classOf(String c) {
    switch (c) {
      case 'a':
        return 'a-zA-Z';
      case 'A':
        return r'^a-zA-Z';
      case 'd':
        return r'0-9';
      case 'l':
        return 'a-z';
      case 'u':
        return 'A-Z';
      case 's':
        return r'\s';
      case 'w':
        return 'a-zA-Z0-9';
      case 'x':
        return 'a-fA-F0-9';
      case 'p':
        return r'!-/:-@\[-`{-~';
      default:
        return RegExp.escape(c);
    }
  }

  // a single character class such as `%s`, as an element outside a set
  String element(String c) {
    switch (c) {
      case 'a':
      case 'd':
      case 'l':
      case 'u':
      case 's':
      case 'w':
      case 'x':
      case 'p':
        return '[${classOf(c)}]';
      case 'A':
        return '[^a-zA-Z]';
      case 'D':
        return '[^0-9]';
      case 'S':
        return r'\S';
      case 'W':
        return '[^a-zA-Z0-9]';
      default:
        return RegExp.escape(c);
    }
  }

  while (i < pattern.length) {
    final c = pattern[i];
    switch (c) {
      case '^':
        out.write(i == 0 ? '^' : r'\^');
        i++;
      case r'$':
        out.write(i == pattern.length - 1 ? r'$' : r'\$');
        i++;
      case '.':
        out.write(r'[\s\S]');
        i++;
      case '(':
      case ')':
        out.write(c);
        i++;
      case '*':
      case '+':
      case '?':
        out.write(c);
        i++;
      case '-':
        out.write('*?');
        i++;
      case '%':
        if (i + 1 >= pattern.length) {
          return null;
        }
        final next = pattern[i + 1];
        if (next == 'b' || next == 'f' || RegExp('[0-9]').hasMatch(next)) {
          return null;
        }
        out.write(element(next));
        i += 2;
      case '[':
        final set = StringBuffer('[');
        i++;
        if (i < pattern.length && pattern[i] == '^') {
          set.write('^');
          i++;
        }
        var closed = false;
        var first = true;
        while (i < pattern.length) {
          final s = pattern[i];
          if (s == ']' && !first) {
            closed = true;
            i++;
            break;
          }
          first = false;
          if (s == '%' && i + 1 < pattern.length) {
            final next = pattern[i + 1];
            final cls = classOf(next);
            // a negated class cannot sit inside a set
            if (cls.startsWith('^')) {
              return null;
            }
            set.write(cls);
            i += 2;
          } else if (s == '-' &&
              i + 1 < pattern.length &&
              pattern[i + 1] != ']' &&
              set.length > 1) {
            set.write('-');
            i++;
          } else {
            set.write(s == '\\' || s == '[' || s == '^' ? '\\$s' : s);
            i++;
          }
        }
        if (!closed) {
          return null;
        }
        set.write(']');
        out.write(set);
      default:
        out.write(RegExp.escape(c));
        i++;
    }
  }
  try {
    return RegExp(out.toString());
  } on FormatException {
    return null;
  }
}
