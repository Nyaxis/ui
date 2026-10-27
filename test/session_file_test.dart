import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor/session_file.dart';
import 'package:ui/editor/text_encoding.dart';

void main() {
  late Directory dir;
  late SessionFile session;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('session_test');
    session = SessionFile(File('${dir.path}/nested/session.json'));
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('unsaved tabs come back as they were written', () async {
    await session.write([
      const SavedTab(
        name: 'a.luau',
        file: r'C:\scripts\a.luau',
        encoding: TextEncoding.utf16le,
        text: 'print("é")\r\n',
      ),
      const SavedTab(
        name: 'Untitled.luau',
        file: null,
        encoding: TextEncoding.utf8,
        text: '',
      ),
    ]);
    final tabs = await session.read();
    expect(tabs.map((t) => t.name), ['a.luau', 'Untitled.luau']);
    expect(tabs[0].file, r'C:\scripts\a.luau');
    expect(tabs[0].encoding, TextEncoding.utf16le);
    expect(tabs[0].text, 'print("é")\r\n');
    expect(tabs[1].file, isNull);
  });

  test(
    'a new session replaces the old one, and leaves no temporary file',
    () async {
      await session.write([
        const SavedTab(
          name: 'a.luau',
          file: null,
          encoding: TextEncoding.utf8,
          text: 'x',
        ),
      ]);
      await session.write([]);
      expect(await session.read(), isEmpty);
      expect(File('${session.file.path}.tmp').existsSync(), isFalse);
    },
  );

  test('a missing or damaged file gives no tabs', () async {
    expect(await session.read(), isEmpty);
    await session.file.parent.create(recursive: true);
    await session.file.writeAsString('{"tabs": [');
    expect(await session.read(), isEmpty);
  });
}
