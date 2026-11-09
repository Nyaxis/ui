import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor/editor_font.dart';

void main() {
  final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);

  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('nyaxis-font'));

  tearDown(() => dir.deleteSync(recursive: true));

  File fontFile(String name) => File('${dir.path}\\$name');

  test('a font of the theme is put in the page as a data url', () async {
    fontFile('Mono.ttf').writeAsBytesSync(bytes);
    final css = await EditorFont.css('Mono', themeFonts: dir);
    expect(css, contains("font-family: 'Mono'"));
    expect(css, contains('data:font/ttf;base64,${base64Encode(bytes)}'));
    expect(css, contains("format('truetype')"));
  });

  test('an opentype font is told apart', () async {
    fontFile('Mono.otf').writeAsBytesSync(bytes);
    final css = await EditorFont.css('Mono', themeFonts: dir);
    expect(css, contains('data:font/otf;'));
    expect(css, contains("format('opentype')"));
  });

  test('the font the app comes with is used when the theme has none', () async {
    final css = await EditorFont.css(
      'JetBrainsMono',
      themeFonts: dir,
      bundled: (asset) async {
        expect(asset, contains('JetBrainsMono'));
        return bytes;
      },
    );
    expect(css, contains('base64,${base64Encode(bytes)}'));
  });

  test('the theme font wins over the one the app comes with', () async {
    fontFile('JetBrainsMono.ttf').writeAsBytesSync(Uint8List.fromList([9]));
    final css = await EditorFont.css(
      'JetBrainsMono',
      themeFonts: dir,
      bundled: (_) async => bytes,
    );
    expect(css, contains('base64,${base64Encode([9])}'));
  });

  test('a font that is not found is left to the page', () async {
    expect(await EditorFont.css('Consolas', themeFonts: dir), isNull);
    expect(await EditorFont.css('Consolas'), isNull);
  });

  test('a name that is not plain is never written into the page', () async {
    // a file that has such a name, as an apostrophe is allowed in one
    fontFile("x'y.ttf").writeAsBytesSync(bytes);
    expect(await EditorFont.css("x'y", themeFonts: dir), isNull);
    expect(EditorFont.isSafe('JetBrains Mono-2'), isTrue);
    expect(EditorFont.isSafe("a'b"), isFalse);
    expect(EditorFont.isSafe('a"b'), isFalse);
    expect(EditorFont.isSafe(r'a\b'), isFalse);
    expect(EditorFont.isSafe(''), isFalse);
  });

  test('a font is put in the loaded page as one style that is replaced', () {
    const css = "@font-face { font-family: 'Mono'; src: url(data:x); }";
    final script = EditorFont.injectScript(css);
    expect(script, contains("getElementById('nyaxis-theme-font')"));
    expect(script, contains('s.textContent = ${jsonEncode(css)};'));
    // the quotes of the css stay inside the string they are written in
    expect(script, contains(r"font-family: 'Mono'"));
    expect(EditorFont.injectScript('a\nb"c'), contains(r'"a\nb\"c"'));
  });

  test('the script measures the text again once the font loaded', () {
    final script = EditorFont.remeasureScript('JetBrainsMono');
    expect(script, contains("document.fonts.load(\"13px 'JetBrainsMono'\")"));
    expect(script, contains('remeasureFonts'));
  });
}
