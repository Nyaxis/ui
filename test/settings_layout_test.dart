import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor/editor_tabs.dart';
import 'package:ui/settings/editor_settings.dart';
import 'package:ui/theme/app_theme.dart';
import 'package:ui/theme/theme_controller.dart';
import 'package:ui/ui/settings_view.dart';

void main() {
  for (final width in [460.0, 560.0, 900.0]) {
    testWidgets('no row of the settings overflows at $width px wide', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final dir = Directory.systemTemp.createTempSync('nyaxis-narrow');
      final controller = ThemeController(
        const AppTheme(),
        palette: 'Dark',
        directory: Directory(
          '${dir.path}${Platform.pathSeparator}themes${Platform.pathSeparator}t',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsView(
              theme: controller.value,
              controller: controller,
              prefs: const EditorPrefs(fontSize: 15),
              onPrefs: (_) {},
              autoSave: AutoSave.afterDelay,
              onAutoSave: (_) {},
              autoSaveDelay: const Duration(seconds: 2),
              onAutoSaveDelay: (_) {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      controller.dispose();
      dir.deleteSync(recursive: true);
    });
  }
}
