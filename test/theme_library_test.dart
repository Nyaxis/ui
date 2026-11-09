import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/theme/theme_library.dart';

void main() {
  group('names', () {
    String? check(
      String name, [
      Iterable<String> taken = const [],
      String? renaming,
    ]) => ThemeLibrary.checkName(name, taken, renaming: renaming);

    test('a plain name is fine, with spaces and accents', () {
      expect(check('Mine'), isNull);
      expect(check('  Catppuccin Frappé  '), isNull);
      expect(check('night-2 (dim)'), isNull);
    });

    test('an empty or blank name is refused', () {
      expect(check(''), isNotNull);
      expect(check('   '), isNotNull);
    });

    test('characters a file name cannot have are refused', () {
      for (final bad in [
        r'a\b',
        'a/b',
        'a:b',
        'a*b',
        'a?b',
        'a"b',
        'a<b',
        'a>b',
        'a|b',
        'a\nb',
      ]) {
        expect(check(bad), isNotNull, reason: bad);
      }
    });

    test('a name that starts or ends with a dot is refused', () {
      expect(check('.hidden'), isNotNull);
      expect(check('theme.'), isNotNull);
      expect(check('..'), isNotNull);
    });

    test('a name Windows keeps for itself is refused', () {
      expect(check('CON'), isNotNull);
      expect(check('nul'), isNotNull);
      expect(check('com1'), isNotNull);
      expect(check('LPT9'), isNotNull);
      expect(check('console'), isNull);
    });

    test('a name that is too long is refused', () {
      expect(check('a' * ThemeLibrary.maxNameLength), isNull);
      expect(check('a' * (ThemeLibrary.maxNameLength + 1)), isNotNull);
    });

    test('a name in use is refused whatever its case, except by its owner', () {
      expect(check('mine', ['Mine', 'Other']), isNotNull);
      expect(check('Mine', ['Mine'], 'Mine'), isNull);
      expect(check('MINE', ['Mine'], 'Mine'), isNull);
      expect(check('Other', ['Mine', 'Other'], 'Mine'), isNotNull);
    });
  });

  group('folders', () {
    late Directory root;
    late ThemeLibrary library;

    String sep(List<String> parts) => parts.join(Platform.pathSeparator);

    void file(List<String> parts, String content) {
      File(sep([root.path, ...parts]))
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    setUp(() {
      root = Directory.systemTemp.createTempSync('nyaxis-library');
      library = ThemeLibrary(root);
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('the themes are the folders, with default first', () {
      for (final name in ['zeta', 'default', 'Alpha', 'beta']) {
        Directory(sep([root.path, name])).createSync();
      }
      File(sep([root.path, 'notes.txt'])).writeAsStringSync('x');
      expect(library.themes(), ['default', 'Alpha', 'beta', 'zeta']);
    });

    test('there are no themes when there is no folder', () {
      expect(
        ThemeLibrary(Directory(sep([root.path, 'none']))).themes(),
        isEmpty,
      );
    });

    test('a copy has everything the theme has, at every depth', () async {
      file(['a', 'theme.json'], '{"x":1}');
      file(['a', 'palettes', 'Mocha.json'], '{}');
      file(['a', 'fonts', 'Mono.ttf'], 'font');
      file(['a', 'icons', 'deep', 'er', 'add.svg'], '<svg/>');

      await library.copyTheme('a', 'b');

      expect(
        File(sep([root.path, 'b', 'theme.json'])).readAsStringSync(),
        '{"x":1}',
      );
      expect(
        File(sep([root.path, 'b', 'palettes', 'Mocha.json'])).existsSync(),
        isTrue,
      );
      expect(
        File(sep([root.path, 'b', 'fonts', 'Mono.ttf'])).readAsStringSync(),
        'font',
      );
      expect(
        File(sep([root.path, 'b', 'icons', 'deep', 'er', 'add.svg']))
            .existsSync(),
        isTrue,
      );
      expect(File(sep([root.path, 'a', 'theme.json'])).existsSync(), isTrue);
    });

    test('a theme is renamed and removed with all it holds', () async {
      file(['a', 'palettes', 'Mocha.json'], '{}');

      await library.renameTheme('a', 'b');
      expect(Directory(sep([root.path, 'a'])).existsSync(), isFalse);
      expect(
        File(sep([root.path, 'b', 'palettes', 'Mocha.json'])).existsSync(),
        isTrue,
      );

      await library.deleteTheme('b');
      expect(Directory(sep([root.path, 'b'])).existsSync(), isFalse);
    });

    test('the palettes are the json files, by name', () {
      file(['a', 'palettes', 'Zed.json'], '{}');
      file(['a', 'palettes', 'apple.json'], '{}');
      file(['a', 'palettes', 'notes.txt'], 'x');
      expect(library.palettes('a'), ['apple', 'Zed']);
      expect(library.palettes('missing'), isEmpty);
    });

    test('a palette is written, read back, renamed and removed', () async {
      await library.writePalette('a', 'One', {'accent': '#112233'});
      expect(await library.readPalette('a', 'One'), {'accent': '#112233'});

      await library.renamePalette('a', 'One', 'Two');
      expect(await library.readPalette('a', 'One'), isNull);
      expect(await library.readPalette('a', 'Two'), {'accent': '#112233'});

      await library.deletePalette('a', 'Two');
      expect(library.palettes('a'), isEmpty);
    });

    test('a palette that is missing or broken reads as nothing', () async {
      file(['a', 'palettes', 'Broken.json'], '{ nope');
      file(['a', 'palettes', 'List.json'], '[1, 2]');
      expect(await library.readPalette('a', 'Nowhere'), isNull);
      expect(await library.readPalette('a', 'Broken'), isNull);
      expect(await library.readPalette('a', 'List'), isNull);
    });
  });
}
