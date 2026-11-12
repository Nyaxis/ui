import 'dart:io';

import 'package:flutter/services.dart';
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

  test('the bundled defaults bind save and the tab menu', () {
    final defaults = File('assets/keymaps/default.json').readAsStringSync();
    expect(
      show(Keymap.resolve([defaults])),
      'ctrl-s=workspace::Save '
      'ctrl-n=workspace::NewFile '
      'ctrl-alt-n=workspace::Open '
      'ctrl-g=go_to_line::Toggle '
      'ctrl-1=workspace::ShowEditor '
      'ctrl-,=workspace::ShowSettings '
      'ctrl-==zed::IncreaseBufferFontSize '
      'ctrl-+=zed::IncreaseBufferFontSize '
      'ctrl-shift-+=zed::IncreaseBufferFontSize '
      'ctrl--=zed::DecreaseBufferFontSize '
      'ctrl-0=zed::ResetBufferFontSize '
      'ctrl-k m=language_selector::Toggle '
      'ctrl-k n=encoding_selector::Toggle '
      'ctrl-f4=pane::CloseActiveItem '
      'ctrl-w=pane::CloseActiveItem '
      'ctrl-alt-shift-t=pane::CloseOtherItems '
      'ctrl-k e=pane::CloseItemsToTheLeft '
      'ctrl-k t=pane::CloseItemsToTheRight '
      'ctrl-k u=pane::CloseCleanItems '
      'ctrl-k w=pane::CloseAllItems '
      'alt-shift-c=workspace::CopyPath '
      'ctrl-k ctrl-shift-c=workspace::CopyRelativePath '
      'ctrl-k p=editor::CopyPath '
      'ctrl-k r=editor::RevealInFileManager '
      'ctrl-k shift-enter=pane::TogglePinTab',
    );
  });

  test('the tab menu shows the keys of the actions that it names', () {
    final defaults = File('assets/keymaps/default.json').readAsStringSync();
    final keymap = Keymap.resolve([defaults]);
    String? keys(String action) {
      // the last binding of an action is the one that counts
      final found = [
        for (final b in keymap)
          if (b.action == action) b.keys,
      ];
      return found.isEmpty ? null : found.last;
    }

    expect(keys('pane::CloseActiveItem'), 'ctrl-w');
    expect(keys('pane::CloseOtherItems'), 'ctrl-alt-shift-t');
    expect(keys('pane::CloseItemsToTheLeft'), 'ctrl-k e');
    expect(keys('pane::CloseItemsToTheRight'), 'ctrl-k t');
    expect(keys('pane::CloseCleanItems'), 'ctrl-k u');
    expect(keys('pane::CloseAllItems'), 'ctrl-k w');
    expect(keys('workspace::CopyPath'), 'alt-shift-c');
    expect(keys('workspace::CopyRelativePath'), 'ctrl-k ctrl-shift-c');
    expect(keys('editor::RevealInFileManager'), 'ctrl-k r');
    expect(keys('pane::TogglePinTab'), 'ctrl-k shift-enter');
    expect(keys('workspace::NewFile'), 'ctrl-n');
    expect(keys('language_selector::Toggle'), 'ctrl-k m');
  });

  testWidgets('a key that is held runs its action again for every repeat', (
    tester,
  ) async {
    final keymap = Keymap();
    var larger = 0;
    var smaller = 0;
    keymap.on('zed::IncreaseBufferFontSize', () async => larger++);
    keymap.on('zed::DecreaseBufferFontSize', () async => smaller++);
    await keymap.attachNative(() => true);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.equal);
    expect(larger, 1);
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.equal);
    }
    expect(larger, 5);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.equal);
    // letting go stops it
    await tester.pump();
    expect(larger, 5);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.minus);
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.minus);
    }
    expect(smaller, 4);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.minus);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
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
