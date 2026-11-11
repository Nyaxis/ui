import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/settings/config_file.dart';
import 'package:ui/theme/app_theme.dart';
import 'package:ui/theme/theme_controller.dart';

import 'temp_dir.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory themes;
  late File configFile;
  late ThemeController controller;

  String sep(List<String> parts) => parts.join(Platform.pathSeparator);

  File inTheme(String theme, List<String> parts) =>
      File(sep([themes.path, theme, ...parts]));

  void writeTheme(String name, {String palette = 'Dark', int radius = 8}) {
    inTheme(name, ['theme.json'])
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({'palette': palette, 'cornerRadius': radius}),
      );
    for (final entry in {'Dark': '#101010', 'Light': '#f0f0f0'}.entries) {
      inTheme(name, ['palettes', '${entry.key}.json'])
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({'background': entry.value, 'accent': '#ff0000'}),
        );
    }
    inTheme(name, ['fonts', 'Mono.ttf'])
      ..createSync(recursive: true)
      ..writeAsStringSync('font');
  }

  Map<String, dynamic> json(File file) =>
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 400));

  ThemeController open(String name) => ThemeController(
    // what loading the theme gives: the colors of its Dark palette
    const AppTheme().copyWith(
      background: const Color(0xff101010),
      accent: const Color(0xffff0000),
      cornerRadius: name == 'mine' ? 12 : 8,
    ),
    palette: 'Dark',
    directory: Directory(sep([themes.path, name])),
    config: ConfigFile(configFile),
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('nyaxis-manage');
    themes = Directory(sep([root.path, 'themes']))..createSync();
    configFile = File(sep([root.path, 'config.json']));
    writeTheme('default');
    writeTheme('mine', radius: 12);
    controller = open('mine');
  });

  tearDown(() async {
    controller.dispose();
    await settle();
    await deleteTemp(root);
  });

  group('themes', () {
    test('a new theme is a copy of the one in use, and is moved to', () async {
      expect(await controller.createTheme('Copy'), isNull);

      expect(controller.themeName, 'Copy');
      expect(controller.themes, ['default', 'Copy', 'mine']);
      expect(inTheme('Copy', ['fonts', 'Mono.ttf']).existsSync(), isTrue);
      expect(inTheme('Copy', ['palettes', 'Light.json']).existsSync(), isTrue);
      expect(controller.value.cornerRadius, 12);
      expect(json(configFile)['theme'], 'Copy');
    });

    test('a name that is in use or does not work makes no theme', () async {
      expect(await controller.createTheme('MINE'), isNotNull);
      expect(await controller.createTheme('Default'), isNotNull);
      expect(await controller.createTheme('a/b'), isNotNull);
      expect(await controller.createTheme('  '), isNotNull);
      expect(controller.themes, ['default', 'mine']);
      expect(controller.themeName, 'mine');
    });

    test(
      'the theme in use is renamed, and is remembered under its new name',
      () async {
        expect(await controller.renameTheme('Renamed'), isNull);

        expect(controller.themeName, 'Renamed');
        expect(controller.themes, ['default', 'Renamed']);
        expect(inTheme('mine', ['theme.json']).existsSync(), isFalse);
        expect(json(configFile)['theme'], 'Renamed');

        // it still saves into its folder
        controller.setCornerRadius(3);
        await settle();
        expect(json(inTheme('Renamed', ['theme.json']))['cornerRadius'], 3);
      },
    );

    test(
      'a theme can be renamed to the same name with other letters',
      () async {
        expect(await controller.renameTheme('Mine'), isNull);
        expect(controller.themeName, 'Mine');
      },
    );

    test(
      'a rename to a name in use, and keeping a name, change nothing',
      () async {
        expect(await controller.renameTheme('default'), isNotNull);
        expect(await controller.renameTheme('mine'), isNull);
        expect(controller.themeName, 'mine');
        expect(controller.themes, ['default', 'mine']);
      },
    );

    test('the default theme is not renamed or removed', () async {
      final base = open('default');
      expect(base.canChangeTheme, isFalse);
      expect(await base.renameTheme('Other'), isNotNull);
      expect(await base.deleteTheme(), isNotNull);
      expect(base.themes, ['default', 'mine']);
      base.dispose();
    });

    test('removing the theme in use moves to the default one first', () async {
      expect(controller.canChangeTheme, isTrue);
      expect(await controller.deleteTheme(), isNull);

      expect(controller.themeName, 'default');
      expect(controller.themes, ['default']);
      expect(Directory(sep([themes.path, 'mine'])).existsSync(), isFalse);
      expect(json(configFile)['theme'], 'default');
    });

    test('without a default theme it moves to another that is there', () async {
      writeTheme('other');
      Directory(sep([themes.path, 'default'])).deleteSync(recursive: true);

      expect(await controller.deleteTheme(), isNull);
      expect(controller.themeName, 'other');
    });

    test('the last theme cannot be removed', () async {
      Directory(sep([themes.path, 'default'])).deleteSync(recursive: true);
      expect(await controller.deleteTheme(), isNotNull);
      expect(controller.themes, ['mine']);
    });
  });

  group('palettes', () {
    test('a new palette keeps the colors in use, and is moved to', () async {
      expect(await controller.createPalette('Mine'), isNull);

      expect(controller.palette, 'Mine');
      expect(controller.palettes, ['Dark', 'Light', 'Mine']);
      final saved = json(inTheme('mine', ['palettes', 'Mine.json']));
      expect(saved['accent'], '#ff0000');
      await settle();
      expect(json(inTheme('mine', ['theme.json']))['palette'], 'Mine');
    });

    test('a name in use or that does not work makes no palette', () async {
      expect(await controller.createPalette('dark'), isNotNull);
      expect(await controller.createPalette(''), isNotNull);
      expect(await controller.createPalette('a:b'), isNotNull);
      expect(controller.palettes, ['Dark', 'Light']);
    });

    test('the palette in use is renamed and still the one in use', () async {
      expect(await controller.renamePalette('Night'), isNull);

      expect(controller.palette, 'Night');
      expect(controller.palettes, ['Light', 'Night']);
      await settle();
      expect(json(inTheme('mine', ['theme.json']))['palette'], 'Night');
    });

    test('a palette is not renamed to another one\'s name', () async {
      expect(await controller.renamePalette('light'), isNotNull);
      expect(controller.palette, 'Dark');
    });

    test('removing the palette in use moves to another first', () async {
      expect(await controller.deletePalette(), isNull);

      expect(controller.palette, 'Light');
      expect(controller.palettes, ['Light']);
      expect(controller.value.background, const Color(0xfff0f0f0));
    });

    test('the last palette cannot be removed', () async {
      expect(await controller.deletePalette(), isNull);
      expect(await controller.deletePalette(), isNotNull);
      expect(controller.palettes, ['Light']);
    });

    test('the palettes are the files, nothing is added to them', () {
      expect(controller.palettes, ['Dark', 'Light']);
    });
  });

  group('colors', () {
    test('a color changes the theme and is saved to its palette', () async {
      controller.setColor('accent', const Color(0xff112233));

      expect(controller.colorOf('accent'), const Color(0xff112233));
      expect(controller.value.accent, const Color(0xff112233));
      await settle();
      expect(
        json(inTheme('mine', ['palettes', 'Dark.json']))['accent'],
        '#112233',
      );
    });

    test('a quick run of changes is written once, with the last', () async {
      for (var i = 0; i < 20; i++) {
        controller.setColor('hover', Color(0xff000000 | (i * 0x0a0a0a)));
      }
      await settle();
      expect(
        json(inTheme('mine', ['palettes', 'Dark.json']))['hover'],
        '#${(19 * 0x0a0a0a).toRadixString(16).padLeft(6, '0')}',
      );
    });

    test('a change goes to the palette it was made in, even when it is left at once', () async {
      controller.setColor('accent', const Color(0xff112233));
      await controller.setPalette('Light');

      expect(
        json(inTheme('mine', ['palettes', 'Dark.json']))['accent'],
        '#112233',
      );
      expect(
        json(inTheme('mine', ['palettes', 'Light.json']))['accent'],
        '#ff0000',
      );
      expect(controller.palette, 'Light');
    });

    test('a color has no transparency', () {
      controller.setColor('background', const Color(0x80112233));
      expect(controller.value.background.a, 1.0);
    });

    test('every role of a palette can be read and changed', () {
      for (final (role, _) in ThemeController.paletteRoles) {
        controller.setColor(role, const Color(0xff0a0b0c));
        expect(controller.colorOf(role), const Color(0xff0a0b0c), reason: role);
      }
      expect(ThemeController.interfaceRoles, hasLength(14));
      expect(ThemeController.codeRoles, hasLength(14));
      expect(ThemeController.paletteRoles, [
        ...ThemeController.interfaceRoles,
        ...ThemeController.codeRoles,
      ]);
    });

    test('a role that does not exist is refused', () {
      expect(() => controller.colorOf('nope'), throwsArgumentError);
      expect(
        () => controller.setColor('nope', const Color(0xff000000)),
        throwsArgumentError,
      );
    });
  });

  group('palette previews', () {
    test('the palette in use gives the colors it has now', () {
      controller.setColor('accent', const Color(0xff112233));
      final colors = controller.paletteColors('Dark')!;

      expect(colors, hasLength(ThemeController.paletteRoles.length));
      final accent = ThemeController.paletteRoles.indexWhere(
        (role) => role.$1 == 'accent',
      );
      expect(colors[accent], const Color(0xff112233));
    });

    test(
      'another palette is read from its file, in the order of the roles',
      () {
        final colors = controller.paletteColors('Light')!;
        final background = ThemeController.paletteRoles.indexWhere(
          (role) => role.$1 == 'background',
        );
        expect(colors[background], const Color(0xfff0f0f0));
      },
    );

    test('a palette that is not there has none', () {
      expect(controller.paletteColors('Nowhere'), isNull);
    });

    test('a palette that is broken has none', () {
      inTheme('mine', ['palettes', 'Broken.json']).writeAsStringSync('{ nope');
      expect(controller.paletteColors('Broken'), isNull);
    });

    test('a palette is read again once its file changes, and not before', () {
      final file = inTheme('mine', ['palettes', 'Light.json']);
      final first = controller.paletteColors('Light')!;
      expect(identical(controller.paletteColors('Light'), first), isTrue);

      file.writeAsStringSync(jsonEncode({'background': '#0000ff'}));
      file.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 5)));
      expect(controller.paletteColors('Light')![0], const Color(0xff0000ff));
    });
  });

  group('window', () {
    test(
      'the rounding power is changed and saved, within its limits',
      () async {
        controller.setRoundingPower(4.5);
        expect(controller.value.roundingPower, 4.5);
        await settle();
        expect(json(inTheme('mine', ['theme.json']))['roundingPower'], 4.5);

        controller.setRoundingPower(0);
        expect(
          controller.value.roundingPower,
          ThemeController.minRoundingPower,
        );
        controller.setRoundingPower(99);
        expect(
          controller.value.roundingPower,
          ThemeController.maxRoundingPower,
        );
      },
    );

    test('the title color is named for all it colors', () {
      final label = ThemeController.paletteRoles
          .firstWhere((role) => role.$1 == 'titleBar')
          .$2;
      expect(label, contains('bottom'));
    });
  });

  group('text', () {
    test('the fonts are the files of the theme', () {
      expect(controller.fonts, ['Mono']);
      expect(open('default').fonts, ['Mono']);
    });

    test('the fonts and their sizes are changed and saved', () async {
      controller.setFontFamily('Mono');
      controller.setMonospaceFontFamily('Mono');
      controller.setFontSize('title', 30);
      controller.setFontSize('body', 15);
      await settle();

      final saved = json(inTheme('mine', ['theme.json']));
      expect(saved['fontFamily'], 'Mono');
      expect(saved['monospaceFontFamily'], 'Mono');
      expect((saved['fontSize'] as Map)['title'], 30);
      expect((saved['fontSize'] as Map)['body'], 15);
    });

    test(
      'a size stays within limits, and a role that does not exist is refused',
      () {
        controller.setFontSize('caption', 1);
        expect(controller.value.fontSizeCaption, ThemeController.minFontSize);
        controller.setFontSize('heading', 999);
        expect(controller.value.fontSizeHeading, ThemeController.maxFontSize);
        expect(() => controller.setFontSize('nope', 12), throwsArgumentError);
      },
    );
  });

  test(
    'a controller of a theme that could not be read saves nothing',
    () async {
      final unreadable = ThemeController(
        const AppTheme(),
        directory: Directory(sep([themes.path, 'mine'])),
        config: ConfigFile(configFile),
        persist: false,
      );
      unreadable.setColor('accent', const Color(0xff112233));
      unreadable.setCornerRadius(1);
      await settle();
      expect(
        json(inTheme('mine', ['palettes', 'Dark.json']))['accent'],
        '#ff0000',
      );
      expect(json(inTheme('mine', ['theme.json']))['cornerRadius'], 12);
      unreadable.dispose();
    },
  );
}
