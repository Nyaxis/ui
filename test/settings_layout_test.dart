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

  group('names', () {
    late Directory dir;
    late ThemeController controller;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('nyaxis-names');
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
      WidgetTester tester, {
      EditorPrefs prefs = const EditorPrefs(),
      ValueChanged<EditorPrefs>? onPrefs,
      AutoSave autoSave = AutoSave.afterDelay,
      ValueChanged<AutoSave>? onAutoSave,
    }) async {
      tester.view.physicalSize = const Size(900, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsView(
              theme: controller.value,
              controller: controller,
              prefs: prefs,
              onPrefs: onPrefs ?? (_) {},
              autoSave: autoSave,
              onAutoSave: onAutoSave ?? (_) {},
              autoSaveDelay: const Duration(seconds: 2),
              onAutoSaveDelay: (_) {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('the sections are those of the editor\'s settings window', (
      tester,
    ) async {
      await pump(tester);
      for (final section in [
        'Buffer Font',
        'Highlighting',
        'Auto Save',
        'Scrolling',
        'Gutter',
        'Scrollbar',
        'Indentation',
        'Wrapping',
        'Autoclose',
      ]) {
        expect(find.text(section), findsOneWidget, reason: section);
      }
      // in the order that they go in, down the page
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      final order = [
        'Buffer Font',
        'Highlighting',
        'Auto Save',
        'Scrolling',
        'Gutter',
        'Scrollbar',
        'Indentation',
        'Wrapping',
        'Autoclose',
      ];
      for (var i = 1; i < order.length; i++) {
        expect(top(order[i]), greaterThan(top(order[i - 1])), reason: order[i]);
      }
    });

    testWidgets('the settings have the titles and the descriptions there', (
      tester,
    ) async {
      await pump(tester);
      const settings = {
        'Font Size': 'Font size for editor text.',
        'Unnecessary Code Fade':
            'How much to fade out unused code (0.0 - 0.9).',
        'Auto Save Mode': 'When to auto save buffer changes.',
        'Delay (milliseconds)':
            'Save after inactivity period (in milliseconds).',
        'Mouse Wheel Zoom': 'Whether to zoom the editor font size with the mouse wheel while holding the primary modifier key.',
        'Show Line Numbers': 'Show line numbers in the gutter.',
        'Tab Size': 'How many columns a tab should occupy.',
        'Soft Wrap': 'How to soft-wrap long lines of text.',
        'Use Autoclose': "Whether to automatically type closing characters for you. For example, when you type '(', the editor will automatically add a closing ')' at the correct position.",
      };
      for (final MapEntry(key: title, value: description) in settings.entries) {
        expect(find.text(title), findsOneWidget, reason: title);
        expect(find.text(description), findsOneWidget, reason: title);
      }
    });

    testWidgets('the hover popover has the section and the titles there', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Hover Popover'), findsOneWidget);
      const settings = {
        'Enabled': 'Show the informational hover box when moving the mouse over symbols in the editor.',
        'Delay': 'Time to wait in milliseconds before showing the informational hover box.',
        'Sticky': 'Whether the hover popover sticks when the mouse moves toward it, allowing interaction with its contents.',
        'Hiding Delay': 'Time to wait in milliseconds before hiding the hover popover after the mouse moves away.',
      };
      for (final MapEntry(key: title, value: description) in settings.entries) {
        expect(find.text(title), findsOneWidget, reason: title);
        expect(find.text(description), findsOneWidget, reason: title);
      }
      // the section goes between the scrolling and the gutter
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('Hover Popover'), greaterThan(top('Scrolling')));
      expect(top('Hover Popover'), lessThan(top('Gutter')));
    });

    testWidgets('the choices of auto save are named as there', (tester) async {
      AutoSave? chosen;
      await pump(tester, onAutoSave: (a) => chosen = a);
      for (final name in [
        'Off',
        'After Delay',
        'On Focus Change',
        'On Window Change',
      ]) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      await tester.tap(find.text('On Focus Change'));
      expect(chosen, AutoSave.onFocusChange);
      await tester.tap(find.text('On Window Change'));
      expect(chosen, AutoSave.onWindowChange);
    });

    testWidgets('the delay of auto save is said in milliseconds', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('2000'), findsOneWidget);
      await pump(tester, autoSave: AutoSave.off);
      expect(find.text('Delay (milliseconds)'), findsNothing);
    });

    testWidgets('soft wrap is none or the width of the editor', (tester) async {
      EditorPrefs? chosen;
      await pump(tester, onPrefs: (p) => chosen = p);
      // the last, as the choices of the diagnostics of the scrollbar have one
      // above it
      await tester.tap(find.text('None').last);
      expect(chosen?.wordWrap, isFalse);
      await tester.tap(find.text('Editor Width'));
      expect(chosen?.wordWrap, isTrue);
    });

    testWidgets('the old names are gone', (tester) async {
      await pump(tester);
      for (final old in [
        'Editor',
        'Files',
        'Font size',
        'Tab size',
        'Word wrap',
        'Close brackets automatically',
        'Mouse wheel zoom',
        'Unnecessary code fade',
        'Auto save',
        'Auto save delay',
      ]) {
        expect(find.text(old), findsNothing, reason: old);
      }
    });
  });

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
      tester.view.physicalSize = const Size(900, 6000);
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
      tester.view.physicalSize = const Size(900, 6000);
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
      expect(find.text('Mouse Wheel Zoom'), findsOneWidget);
      // the rows of the scrollbar, as the settings of an editor have them
      for (final label in [
        'Show',
        'Cursors',
        'Search Results',
        'Selected Text',
        'Selected Symbol',
        'Diagnostics',
        'Horizontal Scrollbar',
        'Vertical Scrollbar',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.tap(find.text('Always'));
      expect(chosen?.scrollbar.show, ScrollbarVisibility.always);
      await tester.tap(find.text('System'));
      expect(chosen?.scrollbar.show, ScrollbarVisibility.system);
      await tester.tap(find.text('Never'));
      expect(chosen?.scrollbar.show, ScrollbarVisibility.never);
      await tester.tap(find.text('Error'));
      expect(chosen?.scrollbar.diagnostics, ScrollbarDiagnostics.error);
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
