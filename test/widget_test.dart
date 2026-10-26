import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/main.dart';
import 'package:ui/theme/app_theme.dart';
import 'package:ui/theme/theme_controller.dart';
import 'package:ui/ui/superellipse.dart';

void main() {
  testWidgets('window corner radius follows the theme controller', (
    tester,
  ) async {
    final controller = ThemeController(const AppTheme(cornerRadius: 12));
    await tester.pumpWidget(NyaxisApp(controller: controller));

    SuperellipseBorder shape() {
      final clipper =
          tester.widget<ClipPath>(find.byType(ClipPath).first).clipper
              as ShapeBorderClipper;
      return clipper.shape as SuperellipseBorder;
    }

    expect(shape().radius, 12);

    controller.setCornerRadius(28);
    await tester.pump();

    expect(shape().radius, 28);
  });
}
