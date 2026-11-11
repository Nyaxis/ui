import '../editor_core/highlight.dart';
import '../theme/app_theme.dart';
import 'syntax_tree.dart';

/// how the names that the queries give are drawn in the colors of [theme].
/// a name that is not here is drawn as the start of it that is, such as
/// `function.method.call` as `function`. [fontStyles] say which names are
/// bold, italic or underlined, in the words `bold`, `italic`, `underline`, or
/// `none` for a name that is none of them, as `config.json` has them under
/// `syntaxStyles`.
SyntaxTheme syntaxThemeFor(
  AppTheme theme, {
  Map<String, String> fontStyles = const {},
}) {
  HighlightStyle color(int value, {bool italic = false}) =>
      HighlightStyle(color: value, italic: italic ? true : null);
  final comment = theme.comment.toARGB32();
  final keyword = theme.keyword.toARGB32();
  final string = theme.string.toARGB32();
  final number = theme.number.toARGB32();
  final function = theme.function.toARGB32();
  final type = theme.type.toARGB32();
  final operator = theme.operator.toARGB32();
  final property = theme.property.toARGB32();
  final special = theme.special.toARGB32();
  final punctuation = theme.punctuation.toARGB32();
  final builtin = theme.red.toARGB32();

  final base = SyntaxTheme({
    'comment': color(comment, italic: true),
    'keyword': color(keyword),
    'string': color(string),
    'string.escape': color(special),
    'string.regexp': color(special),
    'string.special': color(special),
    'number': color(number),
    'boolean': color(number),
    'constant': color(number),
    'type': color(type),
    'constructor': color(type),
    'attribute': color(type),
    'module': color(type),
    'function': color(function),
    'variable.builtin': color(builtin),
    'variable.parameter': color(builtin),
    'variable.member': color(property),
    'property': color(property),
    'operator': color(operator),
    'punctuation': color(punctuation),
  });
  return fontStyles.isEmpty ? base : _withFontStyles(base, fontStyles);
}

/// [theme] with what [fontStyles] say about the names, which keeps the colors
SyntaxTheme _withFontStyles(SyntaxTheme theme, Map<String, String> fontStyles) {
  final styles = Map.of(theme.styles);
  for (final MapEntry(key: name, value: spec) in fontStyles.entries) {
    final words = spec.toLowerCase().split(RegExp(r'[\s,]+')).toSet();
    // what is said replaces how the name was drawn, apart from its color
    final base = theme.styleFor(name) ?? const HighlightStyle();
    styles[name] = HighlightStyle(
      color: base.color,
      background: base.background,
      bold: words.contains('bold'),
      italic: words.contains('italic'),
      underline: words.contains('underline'),
      strikethrough: base.strikethrough,
    );
  }
  return SyntaxTheme(styles);
}

/// the font styles of `syntaxStyles` in `config.json`: an object of names and
/// the words that say how they are drawn, and nothing for any other thing
Map<String, String> fontStylesFromConfig(Object? json) {
  if (json is! Map) {
    return const {};
  }
  return {
    for (final MapEntry(:key, :value) in json.entries)
      if (key is String && value is String) key: value,
  };
}
