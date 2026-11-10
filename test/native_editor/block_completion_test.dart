import 'package:flutter_test/flutter_test.dart';

import 'package:ui/native_editor/block_completion.dart';
import 'package:ui/native_editor/editor_controller.dart';

String _of(String line, {String? next}) {
  final c = completeBlock(line, nextLine: next);
  return c == null ? 'none' : '${c.suffix}|${c.closer}';
}

/// the text after enter is pressed at the end of [text], with the cursor
/// shown as `^`
String _enter(String text, {bool tabs = false}) {
  final controller = EditorController(text: text)
    ..completeBlocks = true
    ..useTabs = tabs;
  controller.selections.selectRanges([(text.length, text.length)]);
  controller.insertNewline();
  final result = controller.text;
  final at = controller.selections.first.head;
  controller.dispose();
  return '${result.substring(0, at)}^${result.substring(at)}';
}

void main() {
  group('what a line opens', () {
    test('conditions get their then and their end', () {
      expect(_of('if x then'), '|end');
      expect(_of('if x'), ' then|end');
      expect(_of('if a == 1 and b'), ' then|end');
      expect(_of('if x and'), 'none');
      expect(_of('if f('), 'none');
      expect(_of('elseif y then'), '|null');
      expect(_of('elseif y'), ' then|null');
      expect(_of('else'), '|null');
      expect(_of('if x then return end'), 'none');
    });

    test('loops get their do and their end', () {
      expect(_of('for i = 1, 10 do'), '|end');
      expect(_of('for i = 1, 10'), ' do|end');
      expect(_of('for _, v in pairs(t)'), ' do|end');
      expect(_of('while true'), ' do|end');
      expect(_of('do'), '|end');
      expect(_of('repeat'), '|null');
    });

    test('functions get their end, and a call that takes one is closed', () {
      expect(_of('function f()'), '|end');
      expect(_of('local function f(a: number): number'), '|end');
      expect(_of('function Counter:increment(by: number?)'), '|end');
      expect(_of('local f = function(a)'), '|end');
      expect(_of('task.spawn(function()'), '|end)');
      expect(_of('Event:Connect(function(a, b)'), '|end)');
      expect(_of('x = pcall(function()'), '|end)');
    });

    test('other lines and comments open nothing', () {
      expect(_of('local x = 1'), 'none');
      expect(_of('print("if x then")'), 'none');
      expect(_of('-- if x then'), 'none');
      expect(_of('   '), 'none');
      expect(_of('return function'), 'none');
    });

    test('a block that has its end is not given another', () {
      expect(_of('if x then', next: '    foo()'), '|null');
      expect(_of('if x then', next: 'end'), '|null');
      expect(_of('  if x then', next: '  else'), '|null');
      expect(_of('  if x then', next: '  foo()'), '|end');
      expect(_of('if x then', next: 'foo()'), '|end');
      expect(_of('x(function()', next: 'end)'), '|null');
    });
  });

  group('enter in the editor', () {
    test('a block opener gets its end and an indented line', () {
      expect(_enter('if x then'), 'if x then\n    ^\nend');
      expect(_enter('function f()'), 'function f()\n    ^\nend');
      expect(
        _enter('task.spawn(function()'),
        'task.spawn(function()\n    ^\nend)',
      );
    });

    test('the missing keyword is typed, and the indent is kept', () {
      expect(_enter('if x'), 'if x then\n    ^\nend');
      expect(_enter('if x '), 'if x then\n    ^\nend');
      expect(
        _enter('\tfor i = 1, 3', tabs: true),
        '\tfor i = 1, 3 do\n\t\t^\n\tend',
      );
      expect(_enter('  while ok'), '  while ok do\n      ^\n  end');
    });

    test('other lines only keep the indent, as they did', () {
      expect(_enter('  local x = 1'), '  local x = 1\n  ^');
      expect(_enter('else'), 'else\n    ^');
    });

    test(
      'in the middle of a line, or with text selected, nothing is added',
      () {
        final controller = EditorController(text: 'if x then foo()')
          ..completeBlocks = true;
        controller.selections.selectRanges([(9, 9)]);
        controller.insertNewline();
        expect(controller.text, 'if x then\n foo()');
        controller.dispose();
      },
    );

    test('without the setting it is a plain new line', () {
      final controller = EditorController(text: 'if x then');
      controller.selections.selectRanges([(9, 9)]);
      controller.insertNewline();
      expect(controller.text, 'if x then\n');
      controller.dispose();
    });

    test('each of several cursors completes its own line', () {
      final controller = EditorController(text: 'if a then\nif b then')
        ..completeBlocks = true;
      controller.selections.selectRanges([(9, 9), (19, 19)]);
      controller.insertNewline();
      expect(controller.text, 'if a then\n    \nend\nif b then\n    \nend');
      controller.dispose();
    });
  });
}
