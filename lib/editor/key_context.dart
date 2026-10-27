/// what is true of the app when a key is pressed, for the contexts of keymap
/// sections to be checked against
class KeyContext {
  const KeyContext(this.identifiers, [this.values = const {}]);

  /// names that are set, such as `Workspace`, or `Editor` while it has focus
  final Set<String> identifiers;

  /// keys with a value, which `key == value` compares
  final Map<String, String> values;
}

/// a context of a keymap section, in zed's syntax: `Editor`, `mode == full`,
/// `!Picker`, `a && b`, `a || b`, `a > b` and parentheses
///
/// shortcut: `a > b` is `a && b`, since the app has one level of contexts; check
/// the nesting when something opens inside the editor
class ContextExpression {
  ContextExpression._(this._matches);

  final bool Function(KeyContext) _matches;

  bool matches(KeyContext context) => _matches(context);

  /// throws a [FormatException] for a source that is not an expression
  static ContextExpression parse(String source) {
    final parser = _Parser(
      RegExp(r'&&|\|\||==|!=|[()!>]|[A-Za-z0-9_-]+')
          .allMatches(source)
          .map((m) => m[0]!)
          .toList(),
      source,
    );
    final expression = parser.or();
    if (!parser.done) {
      throw FormatException('unexpected "${parser.peek}"', source);
    }
    return ContextExpression._(expression);
  }
}

typedef _Matcher = bool Function(KeyContext);

/// `||` binds loosest, then `&&` and `>`, then `==` and `!=`, then `!`
class _Parser {
  _Parser(this._tokens, this._source);

  final List<String> _tokens;
  final String _source;
  var _at = 0;

  bool get done => _at == _tokens.length;

  String? get peek => done ? null : _tokens[_at];

  String _next() {
    if (done) {
      throw FormatException('the expression ends too early', _source);
    }
    return _tokens[_at++];
  }

  bool _accept(String token) {
    if (peek != token) {
      return false;
    }
    _at++;
    return true;
  }

  _Matcher or() {
    var left = and();
    while (_accept('||')) {
      final (a, b) = (left, and());
      left = (c) => a(c) || b(c);
    }
    return left;
  }

  _Matcher and() {
    var left = comparison();
    while (_accept('&&') || _accept('>')) {
      final (a, b) = (left, comparison());
      left = (c) => a(c) && b(c);
    }
    return left;
  }

  _Matcher comparison() {
    final left = unary();
    final equal = _accept('==');
    if (!equal && !_accept('!=')) {
      return left;
    }
    // only a name can be compared, and its value is the next token
    final key = _tokens[_at - 2];
    final value = _next();
    return (c) => (c.values[key] == value) == equal;
  }

  _Matcher unary() {
    if (_accept('!')) {
      final inner = unary();
      return (c) => !inner(c);
    }
    if (_accept('(')) {
      final inner = or();
      if (!_accept(')')) {
        throw FormatException('a parenthesis is not closed', _source);
      }
      return inner;
    }
    final name = _next();
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(name)) {
      throw FormatException('unexpected "$name"', _source);
    }
    return (c) => c.identifiers.contains(name);
  }
}
