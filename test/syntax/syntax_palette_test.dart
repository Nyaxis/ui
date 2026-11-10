import 'package:flutter_test/flutter_test.dart';

import 'package:ui/syntax/syntax_palette.dart';
import 'package:ui/theme/app_theme.dart';

void main() {
  const theme = AppTheme();

  group('font styles', () {
    test('comments are italic, and nothing else is bold or italic', () {
      final syntax = syntaxThemeFor(theme);
      expect(syntax.styleFor('comment')!.italic, isTrue);
      expect(syntax.styleFor('keyword')!.bold, isNull);
      expect(syntax.styleFor('keyword')!.italic, isNull);
    });

    test('the config says which names are bold, italic or underlined', () {
      final syntax = syntaxThemeFor(
        theme,
        fontStyles: {
          'keyword': 'bold',
          'variable.builtin': 'bold italic',
          'string': 'Italic, underline',
        },
      );
      final keyword = syntax.styleFor('keyword.function')!;
      expect(keyword.bold, isTrue);
      expect(keyword.italic, isFalse);
      expect(keyword.color, theme.keyword.toARGB32());
      final self = syntax.styleFor('variable.builtin')!;
      expect((self.bold, self.italic), (true, true));
      final string = syntax.styleFor('string')!;
      expect(
        (string.bold, string.italic, string.underline),
        (false, true, true),
      );
    });

    test('none takes a style away, and the color stays', () {
      final syntax = syntaxThemeFor(theme, fontStyles: {'comment': 'none'});
      final comment = syntax.styleFor('comment')!;
      expect(comment.italic, isFalse);
      expect(comment.color, theme.comment.toARGB32());
    });

    test('a name the theme has no color for gets the style alone', () {
      final syntax = syntaxThemeFor(theme, fontStyles: {'label': 'italic'});
      final label = syntax.styleFor('label')!;
      expect(label.italic, isTrue);
      expect(label.color, isNull);
    });

    test('only an object of words is read from the config', () {
      expect(fontStylesFromConfig(null), isEmpty);
      expect(fontStylesFromConfig('bold'), isEmpty);
      expect(fontStylesFromConfig({'keyword': 'bold', 'x': 1, 2: 'italic'}), {
        'keyword': 'bold',
      });
    });
  });
}
