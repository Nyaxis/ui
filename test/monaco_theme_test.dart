import 'dart:ui' show Color;

import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor/monaco_theme.dart';
import 'package:ui/theme/app_theme.dart';
import 'package:ui/theme/catppuccin.dart';
import 'package:ui/theme/theme_controller.dart';

void main() {
  const mocha = AppTheme();

  Map<String, MonacoThemeRule> rulesOf(MonacoThemeDefinition theme) => {
    for (final rule in theme.rules) rule.token: rule,
  };

  group('colors', () {
    test('a color is written as lowercase hex, with its alpha when asked', () {
      expect(hexOf(const Color(0xffABCDEF)), '#abcdef');
      expect(hexOf(const Color(0xff000001)), '#000001');
      expect(hexOf(const Color(0xff112233), 0.5), '#11223380');
      expect(hexOf(const Color(0xff112233), 0), '#11223300');
      expect(hexOf(const Color(0xff112233), 1), '#112233ff');
    });
  });

  group('the theme of the editor', () {
    final theme = monacoThemeFor(mocha, id: 'nyaxis');
    final rules = rulesOf(theme);

    test('it has the id it is given', () {
      expect(theme.id, 'nyaxis');
    });

    test('every token has one rule, so none overrides another by accident', () {
      expect(rules.length, theme.rules.length);
    });

    test(
      'rules give colors without the hash, which is how monaco has them',
      () {
        for (final rule in theme.rules) {
          expect(
            rule.foreground,
            matches(RegExp(r'^[0-9a-f]{6}$')),
            reason: rule.token,
          );
        }
      },
    );

    test('code is colored in the colors of Catppuccin Mocha', () {
      String? color(String token) => rules[token]?.foreground;
      expect(color('keyword'), 'cba6f7');
      expect(color('string'), 'a6e3a1');
      expect(color('number'), 'fab387');
      expect(color('function'), '89b4fa');
      expect(color('predefined'), '89b4fa');
      expect(color('type'), 'f9e2af');
      expect(color('operator'), '89dceb');
      expect(color('comment'), '9399b2');
      expect(color('delimiter'), '9399b2');
      expect(color('string.escape'), 'f5c2e7');
      expect(color('regexp'), 'f5c2e7');
      expect(color('string.key'), 'b4befe');
      expect(color('identifier'), 'cdd6f4');
      expect(color(''), 'cdd6f4');
    });

    test('comments are italic, and nothing else is', () {
      expect(rules['comment']!.fontStyle, 'italic');
      expect(
        theme.rules.where((r) => r.fontStyle != null).map((r) => r.token),
        ['comment'],
      );
    });

    test('invalid strings are told apart in the color of danger', () {
      expect(rules['string.invalid']!.foreground, 'f38ba8');
      expect(rules['string.escape.invalid']!.foreground, 'f38ba8');
    });

    test('a change to a palette color reaches the rule for it', () {
      final changed = monacoThemeFor(
        mocha.copyWith(keyword: const Color(0xff112233)),
        id: 'x',
      );
      expect(rulesOf(changed)['keyword']!.foreground, '112233');
      expect(rulesOf(changed)['string']!.foreground, 'a6e3a1');
    });

    test(
      'a dark palette is built on the dark theme, and a light one on the light',
      () {
        expect(theme.base, MonacoBaseTheme.vsDark);
        final latte = AppTheme.fromJson(
          const {},
          palette: catppuccinPalettes['Catppuccin Latte'],
        );
        expect(monacoThemeFor(latte, id: 'x').base, MonacoBaseTheme.vs);
      },
    );

    test('pairs of brackets take turns in the colors of the code', () {
      final colors = theme.colors;
      expect(colors['editorBracketHighlight.foreground1'], '#cba6f7');
      expect(colors['editorBracketHighlight.foreground2'], '#b4befe');
      expect(colors['editorBracketHighlight.foreground3'], '#89b4fa');
      expect(colors['editorBracketHighlight.foreground4'], '#a6e3a1');
      expect(colors['editorBracketHighlight.foreground5'], '#f9e2af');
      expect(colors['editorBracketHighlight.foreground6'], '#fab387');
      expect(
        colors['editorBracketHighlight.unexpectedBracket.foreground'],
        '#f38ba8',
      );
    });

    test(
      'the window shows through the editor and the scrollbar, and not black',
      () {
        final colors = theme.colors;
        expect(colors['editor.background'], '#00000000');
        expect(colors['editorGutter.background'], '#00000000');
        // monaco would otherwise paint the scrollbar's column black
        expect(colors['editorOverviewRuler.background'], '#00000000');
        expect(colors['scrollbar.background'], '#00000000');
      },
    );

    test(
      'the minimap is a panel of the surface color, in the window opacity',
      () {
        expect(theme.colors['minimap.background'], '#181825ff');
        final faded = monacoThemeFor(
          mocha.copyWith(backgroundOpacity: 0.5),
          id: 'x',
        );
        expect(faded.colors['minimap.background'], '#18182580');
      },
    );
  });

  group('the Catppuccin palettes', () {
    // the color each flavor gives each kind of code
    const codeColors = {
      'Catppuccin Latte': {
        'comment': '#7c7f93',
        'keyword': '#8839ef',
        'string': '#40a02b',
        'number': '#fe640b',
        'function': '#1e66f5',
        'type': '#df8e1d',
        'operator': '#04a5e5',
        'property': '#7287fd',
        'special': '#ea76cb',
        'punctuation': '#7c7f93',
      },
      'Catppuccin Frappé': {
        'comment': '#949cbb',
        'keyword': '#ca9ee6',
        'string': '#a6d189',
        'number': '#ef9f76',
        'function': '#8caaee',
        'type': '#e5c890',
        'operator': '#99d1db',
        'property': '#babbf1',
        'special': '#f4b8e4',
        'punctuation': '#949cbb',
      },
      'Catppuccin Macchiato': {
        'comment': '#939ab7',
        'keyword': '#c6a0f6',
        'string': '#a6da95',
        'number': '#f5a97f',
        'function': '#8aadf4',
        'type': '#eed49f',
        'operator': '#91d7e3',
        'property': '#b7bdf8',
        'special': '#f5bde6',
        'punctuation': '#939ab7',
      },
      'Catppuccin Mocha': {
        'comment': '#9399b2',
        'keyword': '#cba6f7',
        'string': '#a6e3a1',
        'number': '#fab387',
        'function': '#89b4fa',
        'type': '#f9e2af',
        'operator': '#89dceb',
        'property': '#b4befe',
        'special': '#f5c2e7',
        'punctuation': '#9399b2',
      },
    };

    test('there is one of each flavor', () {
      expect(catppuccinPalettes.keys.toSet(), codeColors.keys.toSet());
    });

    for (final flavor in codeColors.entries) {
      test('${flavor.key} colors code in its own colors', () {
        final palette = catppuccinPalettes[flavor.key]!;
        for (final entry in flavor.value.entries) {
          expect(
            palette[entry.key],
            entry.value,
            reason: '${flavor.key} ${entry.key}',
          );
        }
      });
    }

    // the colors each flavor gives muted text, the hover of an element that
    // has a background (the border color), the hover and pressed colors of
    // the borderless ones, the outline of focus, and what is disabled
    const interfaceColors = {
      'Catppuccin Latte': {
        'textDim': '#5c5f77',
        'border': '#ccd0da',
        'hover': '#bcc0cc',
        'active': '#acb0be',
        'focus': '#7287fd',
        'disabled': '#9ca0b0',
      },
      'Catppuccin Frappé': {
        'textDim': '#b5bfe2',
        'border': '#414559',
        'hover': '#51576d',
        'active': '#626880',
        'focus': '#babbf1',
        'disabled': '#737994',
      },
      'Catppuccin Macchiato': {
        'textDim': '#b8c0e0',
        'border': '#363a4f',
        'hover': '#494d64',
        'active': '#5b6078',
        'focus': '#b7bdf8',
        'disabled': '#6e738d',
      },
      'Catppuccin Mocha': {
        'textDim': '#bac2de',
        'border': '#313244',
        'hover': '#45475a',
        'active': '#585b70',
        'focus': '#b4befe',
        'disabled': '#6c7086',
      },
    };

    for (final flavor in interfaceColors.entries) {
      test('${flavor.key} has its own muted text, hover and focus colors', () {
        final palette = catppuccinPalettes[flavor.key]!;
        for (final entry in flavor.value.entries) {
          expect(
            palette[entry.key],
            entry.value,
            reason: '${flavor.key} ${entry.key}',
          );
        }
      });
    }

    test('each palette has a color for every role', () {
      for (final entry in catppuccinPalettes.entries) {
        for (final (role, _) in ThemeController.paletteRoles) {
          expect(
            entry.value.containsKey(role),
            isTrue,
            reason: '${entry.key} $role',
          );
        }
      }
    });

    test('the defaults of a theme are those of Mocha', () {
      final fromPalette = AppTheme.fromJson(
        const {},
        palette: catppuccinPalettes['Catppuccin Mocha'],
      );
      for (final (role, _) in ThemeController.paletteRoles) {
        expect(_roleOf(mocha, role), _roleOf(fromPalette, role), reason: role);
      }
    });
  });
}

Color _roleOf(AppTheme theme, String role) {
  final controller = ThemeController(theme);
  addTearDown(controller.dispose);
  return controller.colorOf(role);
}
