import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor/keymap.dart';

void main() {
  const ctrlS = 'monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS';

  test('keys become a monaco expression', () {
    expect(Keymap.toMonaco('ctrl-s'), ctrlS);
    expect(
      Keymap.toMonaco('Ctrl-Shift-F5'),
      'monaco.KeyMod.CtrlCmd | monaco.KeyMod.Shift | monaco.KeyCode.F5',
    );
    expect(
      Keymap.toMonaco('ctrl--'),
      'monaco.KeyMod.CtrlCmd | monaco.KeyCode.Minus',
    );
    expect(Keymap.toMonaco('escape'), 'monaco.KeyCode.Escape');
    expect(
      Keymap.toMonaco('ctrl-k ctrl-o'),
      'monaco.KeyMod.chord(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyK, '
      'monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyO)',
    );
  });

  test('keys that are not understood are refused', () {
    for (final keys in [
      '',
      'ctrl-',
      'ctrl-ss',
      'hyper-s',
      'f25',
      'shift shift',
      'a b c',
      "a');x('",
    ]) {
      expect(Keymap.toMonaco(keys), isNull, reason: keys);
    }
  });

  test('the bundled defaults bind save', () {
    final defaults = File('assets/keymaps/default.json').readAsStringSync();
    expect(Keymap.resolve([defaults]), {ctrlS: 'workspace::Save'});
  });

  test('a later keymap rebinds and unbinds, with comments and commas', () {
    const defaults = '[{"bindings": {"ctrl-s": "workspace::Save"}}]';
    expect(
      Keymap.resolve([
        defaults,
        '''
// mine
[
  {
    "context": "Workspace",
    "bindings": {
      "ctrl-shift-s": "workspace::Save", /* also */
      "ctrl-s": null,
      "ctrl-,": "zed::OpenSettingsFile", // a comma in a string
    },
  },
  {"context": "Picker", "bindings": {"ctrl-p": "menu::SelectPrevious"}},
]
''',
      ]),
      {
        'monaco.KeyMod.CtrlCmd | monaco.KeyMod.Shift | monaco.KeyCode.KeyS':
            'workspace::Save',
        'monaco.KeyMod.CtrlCmd | monaco.KeyCode.Comma': 'zed::OpenSettingsFile',
      },
    );
  });

  test('a keymap that is not a list is refused', () {
    expect(() => Keymap.resolve(['{}']), throwsFormatException);
    expect(() => Keymap.resolve(['[{']), throwsFormatException);
  });
}
