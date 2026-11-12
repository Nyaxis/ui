import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/ui/device_pixels.dart';
import 'package:ui/ui/gamma_icon.dart';
import 'package:ui/ui/skinnable_icon.dart';

/// waits, in real time, until [finder] finds something, while the icon loads
Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

void main() {
  group('the correction of the coverage of an icon', () {
    test('keeps what is not covered and what is covered whole', () {
      for (final brightness in [0.1, 0.5, 0.84, 1.0]) {
        expect(correctCoverage(0, brightness), 0, reason: '$brightness');
        expect(correctCoverage(1, brightness), closeTo(1, 1e-9));
      }
    });

    test('adds to the edges of a light icon', () {
      // the color of the text in Catppuccin Mocha is light: 0.84 bright, and
      // gamma 1.8 as the system has it by default. with its ratios, what is
      // half covered comes out as about 0.6325
      final brightness = colorBrightness(const Color(0xFFCDD6F4));
      expect(brightness, closeTo(0.84, 0.01));
      expect(correctCoverage(0.5, brightness), closeTo(0.6325, 0.002));
      expect(correctCoverage(0.5, brightness), greaterThan(0.5));
    });

    test('a dark icon on a light background is brought in less or more', () {
      // dark colors get the contrast that light ones do not
      final dark = correctCoverage(0.5, 0.2);
      expect(dark, greaterThan(0));
      expect(dark, lessThan(1));
      expect(dark, isNot(closeTo(correctCoverage(0.5, 0.84), 1e-6)));
    });

    test('never goes out of 0 to 1, and goes up with the coverage', () {
      for (final brightness in [0.0, 0.3, 0.6, 0.9, 1.0]) {
        var last = -1.0;
        for (var i = 0; i <= 20; i++) {
          final value = correctCoverage(i / 20, brightness);
          expect(value, inInclusiveRange(0.0, 1.0));
          expect(value, greaterThanOrEqualTo(last - 1e-9));
          last = value;
        }
      }
    });

    test('brightness is by the weights of the eye', () {
      expect(colorBrightness(const Color(0xFF000000)), 0);
      expect(colorBrightness(const Color(0xFFFFFFFF)), closeTo(1, 1e-9));
      expect(
        colorBrightness(const Color(0xFF00FF00)),
        greaterThan(colorBrightness(const Color(0xFFFF0000))),
      );
    });
  });

  group('the icon', () {
    late Directory theme;

    setUp(() {
      theme = Directory.systemTemp.createTempSync('nyaxis_icons');
      Directory('${theme.path}${Platform.pathSeparator}icons').createSync();
      SkinnableIcon.themeDirectory = () => theme;
      SkinnableIcon.forgetFiles();
    });

    tearDown(() {
      SkinnableIcon.themeDirectory = () => null;
      SkinnableIcon.forgetFiles();
      theme.deleteSync(recursive: true);
    });

    /// the file of the theme for an icon, which is only found by this name
    File skin(String name, String extension) => File(
      '${theme.path}${Platform.pathSeparator}icons'
      '${Platform.pathSeparator}$name.$extension',
    );

    /// the icon on a screen with a device pixel to each logical one, which is
    /// not what a test has by default
    Widget icon(String name, {double size = 14}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SkinnableIcon(
          name: name,
          size: size,
          color: const Color(0xFFCDD6F4),
        ),
      ),
    );

    Future<void> pump(WidgetTester tester, String name, {double size = 14}) {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      return tester.pumpWidget(icon(name, size: size));
    }

    testWidgets('is the corrected one once it is made', (tester) async {
      await pump(tester, 'sidebar-closed');
      // the plain icon is there until the other is ready
      expect(find.byType(SnappedImage), findsNothing);
      await _until(tester, find.byType(SnappedImage));
      expect(find.byType(SnappedImage), findsOneWidget);
      final image = tester.widget<SnappedImage>(find.byType(SnappedImage));
      expect(image.size, 14);
      expect(image.color, const Color(0xFFCDD6F4));
      expect(image.image.width, 14);
    });

    testWidgets('is the corrected one for a file of the theme that is an svg', (
      tester,
    ) async {
      // the default theme has the bundled icons as files, which are not the
      // theme's own to be drawn as they are
      skin('sidebar-closed', 'svg').writeAsStringSync(
        File('assets/icons/sidebar-closed/sidebar-closed-16.svg')
            .readAsStringSync(),
      );
      SkinnableIcon.forgetFiles();
      expect(SkinnableIcon.hasSkin('sidebar-closed'), isTrue);
      expect(SkinnableIcon.skinIsSvg('sidebar-closed'), isTrue);
      await pump(tester, 'sidebar-closed');
      expect(find.byType(GammaIcon), findsOneWidget);
      await _until(tester, find.byType(SnappedImage));
      expect(find.byType(SnappedImage), findsOneWidget);
    });

    testWidgets('is the file that the theme has, and not the bundled one', (
      tester,
    ) async {
      // a square that is all covered, as the theme's own icon
      skin('sidebar-closed', 'svg').writeAsStringSync(
        '<svg width="16" height="16" viewBox="0 0 16 16" '
        'xmlns="http://www.w3.org/2000/svg">'
        '<rect width="16" height="16" fill="currentColor"/></svg>',
      );
      SkinnableIcon.forgetFiles();
      await pump(tester, 'sidebar-closed');
      await _until(tester, find.byType(SnappedImage));
      final image = tester.widget<SnappedImage>(find.byType(SnappedImage));
      final data = (await tester.runAsync(() => image.image.toByteData()))!;
      // every pixel is covered, which the bundled icon, a frame, is not
      for (var i = 3; i < data.lengthInBytes; i += 4) {
        expect(data.getUint8(i), 255, reason: 'pixel ${i ~/ 4}');
      }
    });

    testWidgets('is not corrected for an image of the theme', (tester) async {
      skin('sidebar-closed', 'png').writeAsBytesSync([0, 1, 2]);
      SkinnableIcon.forgetFiles();
      expect(SkinnableIcon.hasSkin('sidebar-closed'), isTrue);
      expect(SkinnableIcon.skinIsSvg('sidebar-closed'), isFalse);
      await pump(tester, 'sidebar-closed');
      await tester.pump();
      expect(find.byType(GammaIcon), findsNothing);
      expect(find.byType(SnappedImage), findsNothing);
    });

    testWidgets('is made again for a file that was changed', (tester) async {
      final file = skin('sidebar-closed', 'svg');
      file.writeAsStringSync(
        '<svg width="16" height="16" viewBox="0 0 16 16" '
        'xmlns="http://www.w3.org/2000/svg">'
        '<rect width="16" height="16" fill="currentColor"/></svg>',
      );
      SkinnableIcon.forgetFiles();
      await pump(tester, 'sidebar-closed');
      await _until(tester, find.byType(SnappedImage));
      final first = tester.widget<SnappedImage>(find.byType(SnappedImage));
      final firstData = (await tester.runAsync(
        () => first.image.toByteData(),
      ))!;
      int covered(ByteData d) {
        var sum = 0;
        for (var i = 3; i < d.lengthInBytes; i += 4) {
          sum += d.getUint8(i);
        }
        return sum;
      }

      // a thin line, as another file, with another size, and the widget is
      // built again
      file.writeAsStringSync(
        '<svg width="16" height="16" viewBox="0 0 16 16" '
        'xmlns="http://www.w3.org/2000/svg">'
        '<rect width="16" height="2" fill="currentColor"/></svg>   ',
      );
      await tester.pumpWidget(icon('sidebar-closed', size: 15));
      await pump(tester, 'sidebar-closed');
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        final now = tester.widget<SnappedImage>(find.byType(SnappedImage));
        if (!identical(now.image, first.image)) {
          break;
        }
      }
      final second = tester.widget<SnappedImage>(find.byType(SnappedImage));
      final secondData = (await tester.runAsync(
        () => second.image.toByteData(),
      ))!;
      expect(covered(secondData), lessThan(covered(firstData)));
    });

    group('is on whole device pixels', () {
      /// where the icon is drawn, in device pixels, on a screen of [ratio],
      /// when it is [left] logical pixels from the left
      Future<Rect> drawn(
        WidgetTester tester,
        double ratio,
        double left,
        double top,
      ) async {
        tester.view.devicePixelRatio = ratio;
        tester.view.physicalSize = Size(400 * ratio, 400 * ratio);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Padding(
              padding: EdgeInsets.only(left: left, top: top),
              child: Align(
                alignment: Alignment.topLeft,
                child: GammaIcon(
                  name: 'sidebar-closed',
                  size: 14,
                  color: const Color(0xFFCDD6F4),
                ),
              ),
            ),
          ),
        );
        await _until(tester, find.byType(SnappedImage));
        final render = tester.renderObject<RenderBox>(
          find.byType(SnappedImage),
        );
        final canvas = TestRecordingCanvas();
        final context = TestRecordingPaintingContext(canvas);
        render.paint(context, render.localToGlobal(Offset.zero));
        final call = canvas.invocations.firstWhere(
          (i) => i.invocation.memberName == #drawImageRect,
        );
        final rect = call.invocation.positionalArguments[2] as Rect;
        return Rect.fromLTWH(
          rect.left * ratio,
          rect.top * ratio,
          rect.width * ratio,
          rect.height * ratio,
        );
      }

      testWidgets('the corner is on a pixel, and it is as many as the image', (
        tester,
      ) async {
        for (final left in [4.0, 4.2, 4.5, 4.8]) {
          final rect = await drawn(tester, 1.25, left, 3.3);
          expect(rect.left, closeTo(roundToDevicePixel(left, 1.25), 1e-6));
          expect(rect.top, closeTo(roundToDevicePixel(3.3, 1.25), 1e-6));
          // 14 logical pixels are 17.5 device pixels, which are 17 of them
          expect(rect.width, closeTo(17, 1e-6));
          expect(rect.height, closeTo(17, 1e-6));
        }
      });

      testWidgets('is not scaled, which would be what makes it blurred', (
        tester,
      ) async {
        for (final ratio in [1.0, 1.5, 2.0]) {
          final rect = await drawn(tester, ratio, 4.37, 2.61);
          final image = tester
              .widget<SnappedImage>(find.byType(SnappedImage))
              .image;
          expect(rect.width, closeTo(image.width.toDouble(), 1e-6));
          expect(rect.height, closeTo(image.height.toDouble(), 1e-6));
          expect(rect.left, rect.left.roundToDouble());
          expect(rect.top, rect.top.roundToDouble());
        }
      });

      testWidgets('the image has the pixels of its box', (tester) async {
        await drawn(tester, 1.5, 4, 4);
        final image = tester
            .widget<SnappedImage>(find.byType(SnappedImage))
            .image;
        // 14 logical pixels are 21 device pixels
        expect(image.width, 21);
        expect(image.height, 21);
      });
    });
  });
}
