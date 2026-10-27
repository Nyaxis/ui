import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor/key_context.dart';
import 'package:ui/editor/keymap.dart';

void main() {
  test('keys are written with their modifiers in order', () {
    expect(Keymap.toKeys('ctrl-s'), 'ctrl-s');
    expect(Keymap.toKeys('Shift-Ctrl-F5'), 'ctrl-shift-f5');
    expect(Keymap.toKeys('secondary-cmd-alt-p'), 'ctrl-alt-win-p');
    expect(Keymap.toKeys('ctrl--'), 'ctrl--');
    expect(Keymap.toKeys('escape'), 'escape');
    expect(Keymap.toKeys('ctrl-k  Ctrl-O'), 'ctrl-k ctrl-o');
  });

  test('keys are shown the way a menu writes them', () {
    expect(Keymap.formatKeys('ctrl-alt-shift-t'), 'Ctrl-Alt-Shift-T');
    expect(Keymap.formatKeys('ctrl-k shift-enter'), 'Ctrl-K Shift-Enter');
    expect(Keymap.formatKeys('ctrl--'), 'Ctrl--');
    expect(Keymap.formatKeys('alt-pagedown'), 'Alt-PageDown');
    expect(Keymap.formatKeys('f5'), 'F5');
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
      expect(Keymap.toKeys(keys), isNull, reason: keys);
    }
  });

  String show(Iterable<Binding> bindings) =>
      [for (final b in bindings) '${b.keys}=${b.action}'].join(' ');

  test('the bundled defaults bind save', () {
    final defaults = File('assets/keymaps/default.json').readAsStringSync();
    expect(show(Keymap.resolve([defaults])), 'ctrl-s=workspace::Save');
  });

  test('keymaps apply in order, with comments and trailing commas', () {
    final bindings = Keymap.resolve([
      '[{"bindings": {"ctrl-s": "workspace::Save"}}]',
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
  {"context": "a ||", "bindings": {"ctrl-p": "menu::SelectPrevious"}},
]
''',
    ]);
    expect(
      show(bindings),
      'ctrl-s=workspace::Save ctrl-shift-s=workspace::Save ctrl-s=null '
      'ctrl-,=zed::OpenSettingsFile',
    );
  });

  test('a keymap that is not a list is refused', () {
    expect(() => Keymap.resolve(['{}']), throwsFormatException);
    expect(() => Keymap.resolve(['[{']), throwsFormatException);
  });

  group('context expressions', () {
    const editor = KeyContext({'Workspace', 'Editor'}, {'mode': 'full'});
    const workspace = KeyContext({'Workspace'});

    bool matches(String source, KeyContext context) =>
        ContextExpression.parse(source).matches(context);

    test('names, negation and comparisons', () {
      expect(matches('Editor', editor), isTrue);
      expect(matches('Editor', workspace), isFalse);
      expect(matches('!Editor', workspace), isTrue);
      expect(matches('mode == full', editor), isTrue);
      expect(matches('mode == compact', editor), isFalse);
      expect(matches('mode != compact', editor), isTrue);
      expect(matches('mode != full', workspace), isTrue);
    });

    test('combinations, with and binding tighter than or', () {
      expect(matches('Picker || Editor && mode == full', editor), isTrue);
      expect(matches('Picker || Editor && mode == full', workspace), isFalse);
      expect(matches('(Picker || Editor) && Workspace', editor), isTrue);
      expect(matches('Workspace > Editor', editor), isTrue);
      expect(matches('Workspace > Editor', workspace), isFalse);
    });

    test('what is not an expression is refused', () {
      for (final source in ['', 'a &&', '(a', 'a b', '== a', 'a ==']) {
        expect(
          () => ContextExpression.parse(source),
          throwsFormatException,
          reason: source,
        );
      }
    });
  });
}
