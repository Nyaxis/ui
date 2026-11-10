import '../editor_core/highlight.dart';
import '../theme/app_theme.dart';
import 'syntax_tree.dart';

/// how the names that the queries give are drawn in the colors of [theme].
/// a name that is not here is drawn as the start of it that is, such as
/// `function.method.call` as `function`
SyntaxTheme syntaxThemeFor(AppTheme theme) {
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

  return SyntaxTheme({
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
}
