import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor/file_icon_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an extension finds its icon in the flavor asked for', () async {
    final theme = await FileIconTheme.load('Catppuccin Frappé');
    final asset = theme!.assetFor('lua');
    expect(asset, 'assets/file_icons/icons/frappe/lua.svg');
    await rootBundle.load(asset);
    expect(
      theme.assetFor('not-an-extension'),
      'assets/file_icons/icons/frappe/_file.svg',
    );
  });

  test('a theme that is not bundled gives none', () async {
    expect(await FileIconTheme.load('Nope'), isNull);
  });
}
