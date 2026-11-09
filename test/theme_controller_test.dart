import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/theme/app_theme.dart';
import 'package:ui/theme/theme_controller.dart';

void main() {
  late Directory dir;
  late ThemeController controller;

  File inTheme(String name) =>
      File('${dir.path}${Platform.pathSeparator}$name');

  Map<String, dynamic> saved() =>
      jsonDecode(inTheme('theme.json').readAsStringSync())
          as Map<String, dynamic>;

  void writePalette(String name, String accent) {
    final file = inTheme('palettes${Platform.pathSeparator}$name.json');
    file.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({'accent': accent, 'background': '#000000'}),
    );
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nyaxis-theme');
    controller = ThemeController(
      const AppTheme(),
      palette: 'Catppuccin Mocha',
      directory: dir,
    );
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('each setting changes the theme and is saved to theme.json', () async {
    controller.setCornerRadius(12);
    controller.setBorderWidth(3);
    controller.setBackgroundOpacity(0.8);
    controller.setAcrylic(true);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final theme = controller.value;
    expect(theme.cornerRadius, 12);
    expect(theme.borderWidth, 3);
    expect(theme.backgroundOpacity, 0.8);
    expect(theme.acrylic, isTrue);

    final json = saved();
    expect(json['cornerRadius'], 12);
    expect(json['borderWidth'], 3);
    expect(json['backgroundOpacity'], 0.8);
    expect(json['acrylic'], isTrue);
    expect(json['palette'], 'Catppuccin Mocha');
  });

  test('the opacity stays between none and full', () {
    controller.setBackgroundOpacity(3);
    expect(controller.value.backgroundOpacity, 1);
    controller.setBackgroundOpacity(-1);
    expect(controller.value.backgroundOpacity, 0);
  });

  test(
    'a palette gives its colors, keeps the rest, and is remembered',
    () async {
      writePalette('Mine', '#112233');
      controller.setCornerRadius(5);

      await controller.setPalette('Mine');

      expect(controller.palette, 'Mine');
      expect(controller.value.accent, const Color(0xff112233));
      expect(controller.value.background, const Color(0xff000000));
      expect(controller.value.cornerRadius, 5);
      expect(saved()['palette'], 'Mine');
    },
  );

  test(
    'the palette is already the new one when listeners hear of it',
    () async {
      writePalette('Mine', '#112233');
      String? seen;
      controller.addListener(() => seen = controller.palette);
      await controller.setPalette('Mine');
      expect(seen, 'Mine');
    },
  );

  test(
    'a palette that is missing, broken or not a plain name changes nothing',
    () async {
      inTheme('palettes${Platform.pathSeparator}Broken.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{ nope');
      final before = controller.value;

      await controller.setPalette('Nowhere');
      await controller.setPalette('Broken');
      await controller.setPalette('..');
      await controller.setPalette(r'a\b');

      expect(controller.value, same(before));
      expect(controller.palette, 'Catppuccin Mocha');
    },
  );

  test('the palettes list the Catppuccin flavors first, then the others', () {
    for (final name in [
      'Zebra',
      'Catppuccin Mocha',
      'Apple',
      'Catppuccin Latte',
    ]) {
      writePalette(name, '#ffffff');
    }
    inTheme('palettes${Platform.pathSeparator}notes.txt')
        .writeAsStringSync('not a palette');

    expect(controller.palettes, [
      'Catppuccin Latte',
      'Catppuccin Mocha',
      'Apple',
      'Zebra',
    ]);
  });

  test('without a folder the palette is the only one and nothing is saved', () {
    final loose = ThemeController(const AppTheme(), palette: 'Only');
    loose.setCornerRadius(9);
    expect(loose.value.cornerRadius, 9);
    expect(loose.palettes, ['Only']);
  });
}
