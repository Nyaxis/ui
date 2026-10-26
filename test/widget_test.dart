import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/main.dart';
import 'package:ui/theme/app_theme.dart';
import 'package:ui/theme/theme_controller.dart';

void main() {
  testWidgets('window corner radius follows the theme controller', (
    tester,
  ) async {
    final controller = ThemeController(const AppTheme(cornerRadius: 12));
    await tester.pumpWidget(NyaxisApp(controller: controller));

    final clip = find.byType(ClipRRect).first;
    expect(
      tester.widget<ClipRRect>(clip).borderRadius,
      BorderRadius.circular(12),
    );

    controller.setCornerRadius(28);
    await tester.pump();

    expect(
      tester.widget<ClipRRect>(clip).borderRadius,
      BorderRadius.circular(28),
    );
  });
}
