import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/native_editor/editor_style.dart';
import 'package:ui/theme/app_theme.dart';
import 'package:ui/ui/hover_tooltip.dart';

void main() {
  group('the size of the interface', () {
    test('is 16 until it is set, and a rem is then 16 pixels', () {
      const theme = AppTheme();
      expect(theme.uiFontSize, 16);
      expect(theme.rem(16), 16);
      expect(theme.rem(14), 14);
    });

    test('says what a rem is, so that sizes in rems go with it', () {
      final theme = const AppTheme().copyWith(uiFontSize: 20);
      expect(theme.rem(16), 20);
      expect(theme.rem(14), 17.5);
      expect(theme.rem(8), 10);
      final smaller = const AppTheme().copyWith(uiFontSize: 12);
      expect(smaller.rem(16), 12);
      expect(smaller.rem(4), 3);
    });

    test('is read from the size called ui in the theme, and 16 without', () {
      expect(
        AppTheme.fromJson({
          'fontSize': {'ui': 18},
        }).uiFontSize,
        18,
      );
      expect(
        AppTheme.fromJson({
          'fontSize': {'body': 13},
        }).uiFontSize,
        16,
      );
      expect(AppTheme.fromJson(const {}).uiFontSize, 16);
    });

    test('is not the size of the body text, which has its own', () {
      final theme = const AppTheme().copyWith(uiFontSize: 20);
      expect(theme.fontSizeBody, 13);
      expect(theme.rem(13), isNot(13));
    });

    test('is what a popover goes by, through its scale', () {
      const style = EditorStyle(popoverScale: 1.25);
      expect(style.popoverRem(8), 10);
      expect(style.popoverRem(32), 40);
      expect(const EditorStyle().popoverRem(8), 8);
    });
  });

  group('a tooltip', () {
    const theme = AppTheme();

    Future<void> pumpPanel(WidgetTester tester, AppTheme theme) =>
        tester.pumpWidget(
          MaterialApp(
            home: Align(
              alignment: Alignment.topLeft,
              child: TooltipPanel(
                theme: theme,
                title: 'Go to Line/Column',
                keys: 'ctrl-g',
              ),
            ),
          ),
        );

    testWidgets('goes with the size of the interface', (tester) async {
      await pumpPanel(tester, theme);
      final normal = tester.getRect(find.byType(TooltipPanel));
      expect(
        tester.widget<Text>(find.text('Go to Line/Column')).style!.fontSize,
        14,
      );
      await pumpPanel(tester, theme.copyWith(uiFontSize: 20));
      final bigger = tester.getRect(find.byType(TooltipPanel));
      expect(
        tester.widget<Text>(find.text('Go to Line/Column')).style!.fontSize,
        17.5,
      );
      expect(bigger.width, greaterThan(normal.width * 1.2));
      expect(bigger.height, greaterThan(normal.height * 1.2));
      // the room at the left and the top is of rems too
      final title = tester.getRect(find.text('Go to Line/Column'));
      expect(title.left - bigger.left, closeTo(10 + 1 + 10, 0.5));
    });

    testWidgets('has a gap to the pointer that is of pixels, and not of rems', (
      tester,
    ) async {
      expect(TooltipMetrics.pointerGap, 1);
      expect(TooltipMetrics(theme.copyWith(uiFontSize: 20)).roomTop, 12.5);
    });
  });
}
