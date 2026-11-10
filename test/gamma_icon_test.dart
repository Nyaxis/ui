import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/ui/gamma_icon.dart';

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
    testWidgets('is the corrected one once it is made', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: GammaIcon(
              name: 'sidebar-closed',
              size: 14,
              color: Color(0xFFCDD6F4),
            ),
          ),
        ),
      );
      // the plain icon is there until the other is ready
      expect(find.byType(RawImage), findsNothing);
      for (var i = 0; i < 50 && find.byType(RawImage).evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.byType(RawImage), findsOneWidget);
      final raw = tester.widget<RawImage>(find.byType(RawImage));
      expect(raw.width, 14);
      expect(raw.color, const Color(0xFFCDD6F4));
      expect(raw.colorBlendMode, BlendMode.srcIn);
    });
  });
}
