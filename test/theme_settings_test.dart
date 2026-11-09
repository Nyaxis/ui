import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/settings/config_file.dart';
import 'package:ui/theme/app_theme.dart';
import 'package:ui/theme/theme_controller.dart';
import 'package:ui/ui/color_picker.dart';
import 'package:ui/ui/palette_preview.dart';
import 'package:ui/ui/settings_controls.dart';
import 'package:ui/ui/theme_settings.dart';

import 'temp_dir.dart';

void main() {
  const theme = AppTheme();

  group('hex colors', () {
    test('they are read with or without the hash, in short or long form', () {
      expect(parseHexColor('#112233'), const Color(0xff112233));
      expect(parseHexColor('112233'), const Color(0xff112233));
      expect(parseHexColor(' #ABCDEF '), const Color(0xffabcdef));
      expect(parseHexColor('#fa0'), const Color(0xffffaa00));
    });

    test('anything else is not a color', () {
      for (final bad in [
        '',
        '#',
        '#12',
        '#1234',
        '#12345',
        '#1234567',
        '#gg0000',
        'red',
        '#11 22 33',
      ]) {
        expect(parseHexColor(bad), isNull, reason: bad);
      }
    });

    test('a color is written as lowercase hex, without transparency', () {
      expect(colorToHex(const Color(0xffABCDEF)), '#abcdef');
      expect(colorToHex(const Color(0x80112233)), '#112233');
      expect(colorToHex(const Color(0xff000001)), '#000001');
    });
  });

  group('switch', () {
    Future<Container> pumpSwitch(WidgetTester tester, bool value) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SwitchControl(
                theme: theme,
                value: value,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // the track draws itself with a container too, so the knob is the last
      return tester.widget<Container>(
        find
            .descendant(
              of: find.byType(AnimatedContainer),
              matching: find.byType(Container),
            )
            .last,
      );
    }

    testWidgets('on, the track is the accent and the knob is solid', (
      tester,
    ) async {
      final knob = await pumpSwitch(tester, true);
      final track = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect((track.decoration! as BoxDecoration).color, theme.accent);
      expect((knob.decoration! as BoxDecoration).color, theme.titleBar);
    });

    testWidgets('off, the track is the disabled color and the knob is dimmed', (
      tester,
    ) async {
      final knob = await pumpSwitch(tester, false);
      final track = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect((track.decoration! as BoxDecoration).color, theme.disabled);
      expect(
        (knob.decoration! as BoxDecoration).color,
        theme.textPrimary.withValues(alpha: 0.5),
      );
    });
  });

  group('dropdown', () {
    Future<List<String>> pumpDropdown(
      WidgetTester tester, {
      List<(String, String)> options = const [('a', 'Alpha'), ('b', 'Beta')],
      String value = 'a',
    }) async {
      final chosen = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: DropdownControl<String>(
                theme: theme,
                value: value,
                options: options,
                onChanged: chosen.add,
              ),
            ),
          ),
        ),
      );
      return chosen;
    }

    testWidgets(
      'it shows the current choice, and its menu offers all of them',
      (tester) async {
        final chosen = await pumpDropdown(tester);
        expect(find.text('Alpha'), findsOneWidget);
        expect(find.text('Beta'), findsNothing);

        await tester.tap(find.text('Alpha'));
        await tester.pumpAndSettle();
        expect(find.text('Beta'), findsOneWidget);
        expect(find.text('Alpha'), findsNWidgets(2));
        expect(chosen, isEmpty);
      },
    );

    testWidgets('choosing an option reports it and closes the menu', (
      tester,
    ) async {
      final chosen = await pumpDropdown(tester);
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      expect(chosen, ['b']);
      expect(find.text('Beta'), findsNothing);
    });

    testWidgets('a value that is not an option is shown as it is', (
      tester,
    ) async {
      await pumpDropdown(tester, value: 'ghost');
      expect(find.text('ghost'), findsOneWidget);
    });

    testWidgets('with nothing to choose from it opens nothing', (tester) async {
      await pumpDropdown(tester, options: const [], value: 'ghost');
      await tester.tap(find.text('ghost'));
      await tester.pumpAndSettle();
      expect(find.byType(Overlay), findsOneWidget);
      expect(find.text('Beta'), findsNothing);
    });
  });

  group('dropdown with a preview', () {
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: DropdownControl<String>(
                theme: theme,
                value: 'a',
                options: const [('a', 'Alpha'), ('b', 'Beta'), ('c', 'Gamma')],
                onChanged: (_) {},
                leadingFor: (option) => option == 'c'
                    ? null
                    : SizedBox(
                        key: ValueKey('preview-$option'),
                        width: 20,
                        height: 10,
                      ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('the button shows the preview of the one chosen', (
      tester,
    ) async {
      await pump(tester);
      expect(find.byKey(const ValueKey('preview-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('preview-b')), findsNothing);
    });

    testWidgets('the menu shows a preview before each name that has one', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('preview-a')), findsNWidgets(2));
      expect(find.byKey(const ValueKey('preview-b')), findsOneWidget);
      expect(find.text('Gamma'), findsOneWidget);
    });
  });

  group('palette preview', () {
    final colors = [
      for (var i = 0; i < 12; i++) Color(0xff000000 | (i * 0x101010)),
    ];

    testWidgets('it is a box in the background color with a square for each '
        'other color', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PalettePreview(colors: colors, border: theme.border),
            ),
          ),
        ),
      );

      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(PalettePreview),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((box.decoration! as BoxDecoration).color, colors[0]);

      final squares = find.descendant(
        of: find.byType(PalettePreview),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints?.maxWidth == 8 &&
              w.constraints?.maxHeight == 8,
        ),
      );
      expect(squares, findsNWidgets(11));
      expect(
        tester.getSize(find.byType(PalettePreview)),
        const Size(PalettePreview.width, PalettePreview.height),
      );
    });

    testWidgets('colors that are not a whole palette draw an empty space', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PalettePreview(
                colors: colors.take(5).toList(),
                border: theme.border,
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(PalettePreview)),
        const Size(PalettePreview.width, PalettePreview.height),
      );
    });
  });

  group('color field', () {
    Future<List<Color>> pumpField(
      WidgetTester tester, {
      Color color = const Color(0xff112233),
    }) async {
      final changes = <Color>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ColorField(
                theme: theme,
                color: color,
                onChanged: changes.add,
              ),
            ),
          ),
        ),
      );
      return changes;
    }

    testWidgets('it shows the color as hex', (tester) async {
      await pumpField(tester);
      expect(find.widgetWithText(TextField, '#112233'), findsOneWidget);
    });

    testWidgets('typing a color reports it as soon as it is one', (
      tester,
    ) async {
      final changes = await pumpField(tester);
      await tester.enterText(find.byType(TextField), '#ff0000');
      await tester.pump();
      expect(changes, [const Color(0xffff0000)]);
    });

    testWidgets(
      'half a color reports nothing, and the field says it is not one',
      (tester) async {
        final changes = await pumpField(tester);
        await tester.enterText(find.byType(TextField), '#ff00');
        await tester.pump();
        expect(changes, isEmpty);

        final field = tester.widget<TextField>(find.byType(TextField));
        final border = field.decoration!.enabledBorder! as OutlineInputBorder;
        expect(border.borderSide.color, theme.red);
      },
    );

    testWidgets('leaving the field with something else puts the color back', (
      tester,
    ) async {
      final changes = await pumpField(tester);
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '#zz');
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      expect(changes, isEmpty);
      expect(find.widgetWithText(TextField, '#112233'), findsOneWidget);
    });

    testWidgets('a color that comes from elsewhere replaces the text', (
      tester,
    ) async {
      await pumpField(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ColorField(
                theme: theme,
                color: const Color(0xff00ff00),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.widgetWithText(TextField, '#00ff00'), findsOneWidget);
    });

    testWidgets('the swatch opens the picker, which changes the color', (
      tester,
    ) async {
      final changes = await pumpField(tester);
      await tester.tap(find.byKey(const ValueKey('swatch')));
      await tester.pumpAndSettle();
      expect(find.byType(HsvPicker), findsOneWidget);

      await tester.tapAt(
        tester.getTopRight(find.byKey(const ValueKey('hsv-square'))) +
            const Offset(-1, 1),
      );
      await tester.pump();
      expect(changes, isNotEmpty);

      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.byType(HsvPicker), findsNothing);
    });
  });

  group('hsv picker', () {
    Future<List<Color>> pumpPicker(WidgetTester tester, Color color) async {
      final changes = <Color>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: HsvPicker(color: color, onChanged: changes.add),
            ),
          ),
        ),
      );
      return changes;
    }

    testWidgets('the top right of the square is the brightest, fullest color', (
      tester,
    ) async {
      final changes = await pumpPicker(tester, const Color(0xffff0000));
      final square = find.byKey(const ValueKey('hsv-square'));
      await tester.tapAt(tester.getTopRight(square) + const Offset(-0.5, 0.5));
      await tester.pump();
      final color = HSVColor.fromColor(changes.last);
      expect(color.saturation, closeTo(1, 0.01));
      expect(color.value, closeTo(1, 0.01));
    });

    testWidgets('the bottom of the square is black, and the left is gray', (
      tester,
    ) async {
      final changes = await pumpPicker(tester, const Color(0xffff0000));
      final square = find.byKey(const ValueKey('hsv-square'));
      await tester.tapAt(
        tester.getBottomLeft(square) + const Offset(0.5, -0.5),
      );
      await tester.pump();
      expect(HSVColor.fromColor(changes.last).value, closeTo(0, 0.01));

      await tester.tapAt(tester.getTopLeft(square) + const Offset(0.5, 0.5));
      await tester.pump();
      expect(HSVColor.fromColor(changes.last).saturation, closeTo(0, 0.01));
    });

    testWidgets(
      'the strip changes the hue and keeps how bright and full it is',
      (tester) async {
        final changes = await pumpPicker(tester, const Color(0xff804020));
        final before = HSVColor.fromColor(const Color(0xff804020));
        final strip = find.byKey(const ValueKey('hsv-strip'));
        await tester.tapAt(tester.getCenter(strip));
        await tester.pump();

        final after = HSVColor.fromColor(changes.last);
        expect(after.hue, closeTo(180, 1.5));
        expect(after.saturation, closeTo(before.saturation, 0.01));
        expect(after.value, closeTo(before.value, 0.01));
      },
    );

    testWidgets('dragging past the edge stays at the edge', (tester) async {
      final changes = await pumpPicker(tester, const Color(0xff808080));
      final square = find.byKey(const ValueKey('hsv-square'));

      var gesture = await tester.startGesture(tester.getCenter(square));
      await gesture.moveTo(
        tester.getTopRight(square) + const Offset(400, -400),
      );
      await tester.pump();
      await gesture.up();
      final corner = HSVColor.fromColor(changes.last);
      expect(corner.saturation, closeTo(1, 0.01));
      expect(corner.value, closeTo(1, 0.01));

      gesture = await tester.startGesture(tester.getCenter(square));
      await gesture.moveTo(
        tester.getBottomLeft(square) + const Offset(-400, 400),
      );
      await tester.pump();
      await gesture.up();
      expect(changes.last, const Color(0xff000000));
    });
  });

  group('stepper with a slider', () {
    Future<List<double>> pumpStepper(
      WidgetTester tester, {
      SliderSpec? Function(List<double> reported)? slider,
    }) async {
      final reported = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: StepperControl(
                theme: theme,
                text: '5',
                onMinus: () {},
                onPlus: () {},
                slider: slider?.call(reported),
              ),
            ),
          ),
        ),
      );
      return reported;
    }

    SliderSpec spec(List<double> reported, {double value = 5}) => SliderSpec(
      value: value,
      min: 0,
      max: 10,
      divisions: 10,
      onChanged: reported.add,
    );

    testWidgets('the slider is beside the buttons, not instead of them', (
      tester,
    ) async {
      await pumpStepper(tester, slider: spec);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('−'), findsOneWidget);
      expect(find.text('+'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('without a slider there is none', (tester) async {
      await pumpStepper(tester);
      expect(find.byType(Slider), findsNothing);
      expect(find.text('+'), findsOneWidget);
    });

    testWidgets('the ends of the track are the ends of the range', (
      tester,
    ) async {
      final reported = await pumpStepper(tester, slider: spec);
      await tester.drag(find.byType(Slider), const Offset(500, 0));
      await tester.pump();
      expect(reported.last, 10);

      await tester.drag(find.byType(Slider), const Offset(-1000, 0));
      await tester.pump();
      expect(reported.last, 0);
    });

    testWidgets('it only reports whole steps', (tester) async {
      final reported = await pumpStepper(tester, slider: spec);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Slider)),
      );
      for (var i = 1; i <= 40; i++) {
        await gesture.moveBy(const Offset(2, 0));
        await tester.pump();
      }
      await gesture.up();

      expect(reported, isNotEmpty);
      expect(reported.every((v) => v == v.roundToDouble()), isTrue);
      expect(reported.toSet().length, reported.length);
    });

    testWidgets(
      'the thumb stays under the pointer while the setting moves in steps',
      (tester) async {
        // the setting never follows here, as when the app is slow to
        final reported = await pumpStepper(tester, slider: spec);
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(Slider)),
        );
        await gesture.moveBy(const Offset(13, 0));
        await tester.pump();

        final dragged = tester.widget<Slider>(find.byType(Slider)).value;
        expect(dragged, greaterThan(5));
        expect(dragged, isNot(dragged.roundToDouble()));
        expect(reported.last, dragged.roundToDouble());

        await gesture.up();
        await tester.pump();
        expect(tester.widget<Slider>(find.byType(Slider)).value, 5);
      },
    );

    testWidgets('a value outside the range does not break it', (tester) async {
      await pumpStepper(tester, slider: (r) => spec(r, value: 99));
      expect(find.byType(Slider), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 10);
    });
  });

  group('theme settings', () {
    late Directory root;
    late Directory themes;
    late ThemeController controller;

    String sep(List<String> parts) => parts.join(Platform.pathSeparator);

    void writeTheme(String name) {
      File(sep([themes.path, name, 'theme.json']))
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'palette': 'Dark'}));
      File(sep([themes.path, name, 'palettes', 'Dark.json']))
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'background': '#101010'}));
      File(sep([themes.path, name, 'palettes', 'Light.json']))
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'background': '#f0f0f0'}));
    }

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      root = Directory.systemTemp.createTempSync('nyaxis-ui');
      themes = Directory(sep([root.path, 'themes']))..createSync();
      // not `default`, which the app fills in from its assets when it moves to it
      writeTheme('other');
      writeTheme('mine');
      controller = ThemeController(
        const AppTheme(),
        palette: 'Dark',
        directory: Directory(sep([themes.path, 'mine'])),
        config: ConfigFile(File(sep([root.path, 'config.json']))),
      );
    });

    tearDown(() async {
      controller.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await deleteTemp(root);
    });

    Future<void> pumpSettings(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => SingleChildScrollView(
                child: ThemeSettings(
                  theme: controller.value,
                  controller: controller,
                ),
              ),
            ),
          ),
        ),
      );
    }

    /// lets the file work the controller does go on, which the test clock
    /// does not wait for
    ///
    /// with [until], it goes on for as long as that takes, up to a few
    /// seconds; without, for a moment, which is for what must not happen
    Future<void> work(WidgetTester tester, {bool Function()? until}) async {
      // what a tap starts is a long chain of awaits on files, and each of
      // them goes on only at the next pump, so the pumps are close together.
      // the clock of the test moves too, for the timers of its own
      for (var i = 0; i < 2000; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 5));
        if (until == null ? i >= 80 : until()) {
          break;
        }
      }
      await tester.pumpAndSettle();
    }

    testWidgets(
      'it shows the theme and the palette in use, and a row for every color',
      (tester) async {
        await pumpSettings(tester);

        expect(find.text('mine'), findsOneWidget);
        expect(find.text('Dark'), findsOneWidget);
        // a label can also be a section's title, such as "Text"
        for (final (_, label) in ThemeController.paletteRoles) {
          expect(find.text(label), findsWidgets, reason: label);
        }
        expect(
          find.byType(ColorField),
          findsNWidgets(ThemeController.paletteRoles.length),
        );
        expect(find.text('Code colors'), findsOneWidget);
      },
    );

    testWidgets('the dropdown moves to another theme', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('mine'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('other'));
      await work(tester, until: () => controller.themeName == 'other');

      expect(controller.themeName, 'other');
    });

    testWidgets(
      'the palette dropdown lists the files of the theme and moves to one',
      (tester) async {
        await pumpSettings(tester);
        await tester.tap(find.text('Dark'));
        await tester.pumpAndSettle();
        expect(find.text('Light'), findsOneWidget);
        await tester.tap(find.text('Light'));
        await work(tester, until: () => controller.palette == 'Light');

        expect(controller.palette, 'Light');
        expect(controller.value.background, const Color(0xfff0f0f0));
      },
    );

    testWidgets(
      'New asks for a name, says what is wrong with one, and makes the theme',
      (tester) async {
        await pumpSettings(tester);
        await tester.tap(find.text('New').first);
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).last, 'mine');
        await tester.pump();
        expect(find.text('That name is already in use'), findsOneWidget);

        await tester.enterText(find.byType(TextField).last, 'Fresh');
        await tester.pump();
        expect(find.textContaining('copy "mine" as "Fresh"'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await work(tester, until: () => controller.themeName == 'Fresh');

        expect(controller.themeName, 'Fresh');
        expect(controller.themes, contains('Fresh'));
        expect(find.text('Fresh'), findsOneWidget);
      },
    );

    testWidgets('a name that is refused is not submitted', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('New').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'a/b');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await work(tester);

      expect(controller.themes, ['mine', 'other']);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Rename starts from the name in use', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('Rename').first);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'mine'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Renamed');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await work(tester, until: () => controller.themeName == 'Renamed');

      expect(controller.themeName, 'Renamed');
    });

    testWidgets('Remove asks first, and cancelling keeps the theme', (
      tester,
    ) async {
      await pumpSettings(tester);
      await tester.tap(find.text('Remove').first);
      await tester.pumpAndSettle();
      expect(find.text('Remove the theme "mine"?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await work(tester);
      expect(controller.themes, ['mine', 'other']);
    });

    testWidgets('Remove removes the theme once it is confirmed', (
      tester,
    ) async {
      await pumpSettings(tester);
      await tester.tap(find.text('Remove').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove').last);
      await work(tester, until: () => controller.themes.length == 1);

      expect(controller.themes, ['other']);
      expect(controller.themeName, 'other');
    });

    testWidgets('Remove is not offered for the default theme', (tester) async {
      writeTheme('default');
      await tester.runAsync(() => controller.switchTheme('default'));
      await pumpSettings(tester);
      await tester.tap(find.text('Remove').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('Remove the theme'), findsNothing);
      expect(find.text('Rename'), findsNWidgets(2));
    });

    testWidgets('the palette cannot be removed when it is the only one', (
      tester,
    ) async {
      File(sep([themes.path, 'mine', 'palettes', 'Light.json'])).deleteSync();
      await pumpSettings(tester);
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Remove the palette'), findsNothing);
    });

    testWidgets('an error is told in a dialog', (tester) async {
      await pumpSettings(tester);
      Directory(sep([themes.path, 'other'])).deleteSync(recursive: true);
      await tester.tap(find.text('Remove').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove').last);
      await work(
        tester,
        until: () => find
            .text('There is no other theme to move to first')
            .evaluate()
            .isNotEmpty,
      );

      expect(
        find.text('There is no other theme to move to first'),
        findsOneWidget,
      );
    });

    testWidgets('a hex typed in a color row changes that color in the theme', (
      tester,
    ) async {
      await pumpSettings(tester);
      final field = find.byType(TextField).first;
      await tester.enterText(field, '#123456');
      await tester.pump();

      expect(controller.colorOf('background'), const Color(0xff123456));
      await work(tester);
    });

    testWidgets('every number has a slider, and it changes the theme', (
      tester,
    ) async {
      await pumpSettings(tester);
      // corner radius, rounding power, border width, opacity, four sizes
      expect(find.byType(Slider), findsNWidgets(8));

      await tester.drag(find.byType(Slider).at(0), const Offset(1000, 0));
      await tester.pump();
      expect(controller.value.cornerRadius, 24);

      await tester.drag(find.byType(Slider).at(1), const Offset(1000, 0));
      await tester.pump();
      expect(controller.value.roundingPower, ThemeController.maxRoundingPower);

      await tester.drag(find.byType(Slider).at(3), const Offset(-1000, 0));
      await tester.pump();
      expect(controller.value.backgroundOpacity, closeTo(0.3, 0.001));

      await tester.drag(find.byType(Slider).at(6), const Offset(1000, 0));
      await tester.pump();
      expect(controller.value.fontSizeBody, ThemeController.maxFontSize);
      await work(tester);
    });

    testWidgets('the steppers change the window and the text sizes', (
      tester,
    ) async {
      await pumpSettings(tester);
      final before = controller.value.cornerRadius;
      final plus = find.text('+');
      await tester.tap(plus.first);
      await tester.pump();
      expect(controller.value.cornerRadius, before + 1);

      final powerBefore = controller.value.roundingPower;
      await tester.tap(plus.at(1));
      await tester.pump();
      expect(controller.value.roundingPower, powerBefore + 0.5);

      final bodyBefore = controller.value.fontSizeBody;
      await tester.tap(plus.at(plus.evaluate().length - 2));
      await tester.pump();
      expect(controller.value.fontSizeBody, bodyBefore + 1);
      await work(tester);
    });
  });
}
