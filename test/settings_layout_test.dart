import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor/editor_tabs.dart';
import 'package:ui/native_editor/scrollbar_layout.dart';
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
              syntaxStyles: const {'keyword': 'bold', 'comment': 'none'},
              onSyntaxStyles: (_) {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final error = tester.takeException();
      if (error is FlutterError) {
        // names the widget that overflowed, which the short message does not
        debugPrint(error.toStringDeep());
      }
      expect(error, isNull);
      controller.dispose();
      dir.deleteSync(recursive: true);
    });
  }

  group('code styles', () {
    late Directory dir;
    late ThemeController controller;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('nyaxis-styles');
      controller = ThemeController(
        const AppTheme(),
        palette: 'Dark',
        directory: Directory(
          '${dir.path}${Platform.pathSeparator}themes${Platform.pathSeparator}t',
        ),
      );
    });

    tearDown(() {
      controller.dispose();
      dir.deleteSync(recursive: true);
    });

    Future<void> pump(
      WidgetTester tester,
      Map<String, String>? styles,
      ValueChanged<Map<String, String>> onStyles,
    ) async {
      tester.view.physicalSize = const Size(900, 4200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsView(
              theme: controller.value,
              controller: controller,
              prefs: const EditorPrefs(),
              onPrefs: (_) {},
              autoSave: AutoSave.off,
              onAutoSave: (_) {},
              autoSaveDelay: const Duration(seconds: 2),
              onAutoSaveDelay: (_) {},
              syntaxStyles: styles,
              onSyntaxStyles: onStyles,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('there is no section when the editor does not color code', (
      tester,
    ) async {
      await pump(tester, null, (_) {});
      expect(find.text('Code styles'), findsNothing);
    });

    testWidgets('choosing a style says it for that kind', (tester) async {
      Map<String, String>? chosen;
      await pump(tester, const {}, (styles) => chosen = styles);
      expect(find.text('Code styles'), findsOneWidget);
      // the rows go comments, keywords, ...
      await tester.tap(find.text('Bold').at(1));
      expect(chosen, {'keyword': 'bold'});
      await tester.tap(find.text('Bold italic').at(2));
      expect(chosen, {'string': 'bold italic'});
    });

    testWidgets('comments are italic until they are said to be another', (
      tester,
    ) async {
      Map<String, String>? chosen;
      await pump(tester, const {}, (styles) => chosen = styles);
      await tester.tap(find.text('Regular').at(0));
      expect(chosen, {'comment': 'none'});
      await tester.tap(find.text('Bold').at(0));
      expect(chosen, {'comment': 'bold'});
      // back to what it was is not kept
      await pump(tester, const {
        'comment': 'none',
      }, (styles) => chosen = styles);
      await tester.tap(find.text('Italic').at(0));
      expect(chosen, <String, String>{});
    });

    testWidgets('the scrollbars and the wheel zoom are chosen', (tester) async {
      EditorPrefs? chosen;
      tester.view.physicalSize = const Size(900, 4200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      Future<void> show(Map<String, String>? styles) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsView(
              theme: controller.value,
              controller: controller,
              prefs: const EditorPrefs(),
              onPrefs: (prefs) => chosen = prefs,
              autoSave: AutoSave.off,
              onAutoSave: (_) {},
              autoSaveDelay: const Duration(seconds: 2),
              onAutoSaveDelay: (_) {},
              syntaxStyles: styles,
              onSyntaxStyles: styles == null ? null : (_) {},
            ),
          ),
        ),
      );
      await show(const {});
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Scrollbars'), findsOneWidget);
      expect(find.text('Mouse wheel zoom'), findsOneWidget);
      await tester.tap(find.text('Always'));
      expect(chosen?.scrollbars, ScrollbarVisibility.always);
      await tester.tap(find.text('Never'));
      expect(chosen?.scrollbars, ScrollbarVisibility.never);
    });

    testWidgets('the styles that are set can all be reset', (tester) async {
      Map<String, String>? chosen;
      await pump(tester, const {
        'keyword': 'bold',
        'string': 'italic',
      }, (styles) => chosen = styles);
      await tester.tap(find.text('Reset all'));
      expect(chosen, <String, String>{});
    });
  });
}
