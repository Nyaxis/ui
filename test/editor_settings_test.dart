import 'dart:convert';
import 'dart:io';

import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/native_editor/scrollbar_layout.dart';
import 'package:ui/settings/config_file.dart';
import 'package:ui/settings/editor_settings.dart';

import 'temp_dir.dart';

void main() {
  group('EditorPrefs', () {
    test('a file that says nothing gives what the editor always had', () {
      for (final json in [null, 'text', <String, dynamic>{}]) {
        expect(EditorPrefs.fromJson(json), const EditorPrefs());
      }
      const defaults = EditorPrefs();
      expect(defaults.fontSize, isNull);
      expect(defaults.wordWrap, isTrue);
      expect(defaults.minimap, isFalse);
      expect(defaults.tabSize, 4);
      expect(defaults.smoothScrolling, isTrue);
      expect(defaults.renderWhitespace, RenderWhitespace.selection);
    });

    test('the scrollbars are auto, and another is read by its name', () {
      expect(const EditorPrefs().scrollbars, ScrollbarVisibility.auto);
      expect(
        EditorPrefs.fromJson({'scrollbars': 'always'}).scrollbars,
        ScrollbarVisibility.always,
      );
      expect(
        EditorPrefs.fromJson({'scrollbars': 'sometimes'}).scrollbars,
        ScrollbarVisibility.auto,
      );
      const prefs = EditorPrefs(scrollbars: ScrollbarVisibility.never);
      expect(prefs.toJson()['scrollbars'], 'never');
      expect(EditorPrefs.fromJson(prefs.toJson()), prefs);
      expect(prefs.withFontSize(12).scrollbars, ScrollbarVisibility.never);
    });

    test('the wheel zoom is off, and is kept', () {
      expect(const EditorPrefs().mouseWheelZoom, isFalse);
      expect(
        EditorPrefs.fromJson({'mouseWheelZoom': true}).mouseWheelZoom,
        isTrue,
      );
      expect(
        EditorPrefs.fromJson({'mouseWheelZoom': 'yes'}).mouseWheelZoom,
        isFalse,
      );
      const prefs = EditorPrefs(mouseWheelZoom: true);
      expect(prefs.toJson()['mouseWheelZoom'], isTrue);
      expect(EditorPrefs.fromJson(prefs.toJson()), prefs);
      expect(prefs.withFontSize(12).mouseWheelZoom, isTrue);
      expect(prefs.copyWith(tabSize: 2).mouseWheelZoom, isTrue);
    });

    test('values that are out of range or the wrong type are fixed', () {
      final prefs = EditorPrefs.fromJson({
        'fontSize': 500,
        'tabSize': 0,
        'wordWrap': 'yes',
        'minimap': true,
        'renderWhitespace': 'everything',
      });
      expect(prefs.fontSize, EditorPrefs.maxFontSize);
      expect(prefs.tabSize, EditorPrefs.minTabSize);
      expect(prefs.wordWrap, isTrue);
      expect(prefs.minimap, isTrue);
      expect(prefs.renderWhitespace, RenderWhitespace.selection);
    });

    test('they survive a round trip through json', () {
      const prefs = EditorPrefs(
        fontSize: 16,
        tabSize: 2,
        wordWrap: false,
        minimap: true,
        lineNumbers: false,
        renderWhitespace: RenderWhitespace.all,
        fontLigatures: true,
        smoothScrolling: false,
        bracketPairColorization: false,
        autoClosingBrackets: false,
      );
      expect(
        EditorPrefs.fromJson(jsonDecode(jsonEncode(prefs.toJson()))),
        prefs,
      );
    });

    test('the theme size is used until a size is set, and reset goes back', () {
      const prefs = EditorPrefs();
      expect(prefs.toOptions(13).fontSize, 13);
      final sized = prefs.withFontSize(18);
      expect(sized.toOptions(13).fontSize, 18);
      expect(sized.withFontSize(null).toOptions(13).fontSize, 13);
      expect(prefs.withFontSize(2).fontSize, EditorPrefs.minFontSize);
    });

    test('the editor is told every option', () {
      final options = const EditorPrefs(
        wordWrap: false,
        minimap: true,
        lineNumbers: false,
        autoClosingBrackets: false,
      ).toOptions(13);
      expect(options.wordWrap, MonacoWordWrap.off);
      expect(options.minimap?.enabled, isTrue);
      expect(options.lineNumbers, MonacoLineNumbers.off);
      expect(options.autoClosingBrackets, AutoClosingBehavior.never);
      expect(options.tabSize, 4);
    });
  });

  group('EditorSettings', () {
    late Directory dir;
    late File file;
    late ConfigFile config;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('nyaxis-settings');
      file = File('${dir.path}/Nyaxis/config.json');
      config = ConfigFile(file);
    });

    tearDown(() => deleteTemp(dir));

    test('a change is saved and the rest of the file is kept', () async {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('{"theme": "mine", "autoSave": "afterDelay"}');
      final settings = EditorSettings(config);
      await settings.load();

      settings.change(settings.value.copyWith(minimap: true));
      await config.update((_) {});

      final saved = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(saved['theme'], 'mine');
      expect(saved['autoSave'], 'afterDelay');
      expect((saved['editor'] as Map)['minimap'], isTrue);
    });

    test('they are read back on the next start', () async {
      final settings = EditorSettings(config);
      settings.change(const EditorPrefs(tabSize: 8, wordWrap: false));
      await config.update((_) {});

      final next = EditorSettings(config);
      await next.load();
      expect(next.value.tabSize, 8);
      expect(next.value.wordWrap, isFalse);
    });

    test('an unchanged value is not saved', () async {
      final settings = EditorSettings(config);
      settings.change(const EditorPrefs());
      await config.update((_) {});
      expect(file.existsSync(), isTrue);
      expect(
        (jsonDecode(file.readAsStringSync()) as Map).containsKey('editor'),
        isFalse,
      );
    });

    test(
      'the styles of code are saved, read back, and dropped when empty',
      () async {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('{"theme": "mine"}');
        final styles = SyntaxStyleSettings(config);
        await styles.load();
        expect(styles.value, isEmpty);

        styles.change({'keyword': 'bold', 'comment': 'none'});
        await config.update((_) {});
        var saved = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        expect(saved['theme'], 'mine');
        expect(saved['syntaxStyles'], {'keyword': 'bold', 'comment': 'none'});

        final next = SyntaxStyleSettings(config);
        await next.load();
        expect(next.value, {'keyword': 'bold', 'comment': 'none'});

        next.change({});
        await config.update((_) {});
        saved = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        expect(saved.containsKey('syntaxStyles'), isFalse);
        expect(saved['theme'], 'mine');
      },
    );

    test('a file that cannot be read is not overwritten', () async {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('{ not json');
      final settings = EditorSettings(config);
      await settings.load();
      settings.change(const EditorPrefs(minimap: true));
      await config.update((_) {});
      expect(file.readAsStringSync(), '{ not json');
    });
  });
}
