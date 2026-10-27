import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_monaco/flutter_monaco.dart';

/// the keys that run each action, in the format of zed's keymaps: sections of
/// `"keys": "namespace::Action"` bindings. the defaults are bundled, and
/// `keymap.json` in `%APPDATA%\Nyaxis` is applied after them, so its bindings
/// win, and a key set to null is unbound.
///
/// the editor swallows key presses, so keys are bound in monaco, which tells
/// flutter which action was pressed; what an action does is set with [on], and
/// keys of actions without a handler are left alone
class Keymap {
  static const _defaults = 'assets/keymaps/default.json';

  static const _template = '''
// Nyaxis keymap
//
// Bindings here are added to the default ones in assets/keymaps/default.json
// and win over them. Set a key to null to unbind it:
//   "ctrl-s": null
[
  {
    "context": "Workspace",
    "bindings": {
      // "ctrl-shift-s": "workspace::Save"
    },
  },
]
''';

  /// monaco keys to action
  var _bindings = <String, String>{};
  final _handlers = <String, Future<void> Function()>{};
  StreamSubscription<MonacoEvent>? _events;

  void on(String action, Future<void> Function() handler) {
    _handlers[action] = handler;
  }

  /// the keymap is read when the editor attaches, so changing the file takes a
  /// restart
  Future<void> attach(MonacoController controller) async {
    final defaults = await rootBundle.loadString(_defaults);
    final user = await _readUserKeymap();
    try {
      _bindings = resolve([defaults, ?user]);
    } on FormatException catch (e) {
      debugPrint('Keymap: unreadable keymap.json ($e)');
      _bindings = resolve([defaults]);
    }
    _events = controller.events.listen((event) {
      if (event is MonacoUnknownEvent && event.name == 'nyaxis.action') {
        unawaited(_handlers[event.data['action']]?.call());
      }
    });
    await controller.runJavaScript(_script);
  }

  /// creates the file with a template when it is missing, so it can be found
  Future<String?> _readUserKeymap() async {
    final appData = Platform.environment['APPDATA'];
    if (appData == null) {
      debugPrint('Keymap: APPDATA unavailable, using the defaults');
      return null;
    }
    final file = File('$appData\\Nyaxis\\keymap.json');
    try {
      if (!file.existsSync()) {
        await file.parent.create(recursive: true);
        await file.writeAsString(_template);
      }
      return await file.readAsString();
    } catch (e) {
      debugPrint('Keymap: unreadable ${file.path} ($e)');
      return null;
    }
  }

  String get _script => [
    'const act = (action) => () => window.flutterChannel.postMessage('
        "JSON.stringify({kind: 'event', name: 'nyaxis.action', data: {action}}));",
    for (final binding in _bindings.entries)
      if (_handlers.containsKey(binding.value))
        'editor.addCommand(${binding.key}, act(${jsonEncode(binding.value)}));',
  ].join('\n');

  /// monaco keys to action, for keymaps in the order they apply. a later
  /// binding of the same keys replaces an earlier one
  ///
  /// shortcut: every key goes through the editor for now, so only sections
  /// without a context, or in `Workspace` or `Editor`, apply; evaluate
  /// contexts when something outside the editor takes keys
  static Map<String, String> resolve(Iterable<String> keymaps) {
    final bindings = <String, String>{};
    for (final keymap in keymaps) {
      final sections = jsonDecode(_stripComments(keymap));
      if (sections is! List) {
        throw const FormatException('a keymap is a list of sections');
      }
      for (final section in sections) {
        if (section is! Map || section['bindings'] is! Map) {
          continue;
        }
        final context = section['context'];
        if (context != null && context != 'Workspace' && context != 'Editor') {
          continue;
        }
        for (final binding in (section['bindings'] as Map).entries) {
          final keys = toMonaco('${binding.key}');
          final action = binding.value;
          if (keys == null || (action != null && action is! String)) {
            debugPrint('Keymap: ignoring ${binding.key}: $action');
          } else if (action == null) {
            bindings.remove(keys);
          } else {
            bindings[keys] = action as String;
          }
        }
      }
    }
    return bindings;
  }

  /// comments and trailing commas, which zed's files have and json has not
  static String _stripComments(String text) {
    final out = <String>[];
    var inString = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (inString) {
        out.add(c);
        if (c == r'\' && i + 1 < text.length) {
          out.add(text[++i]);
        } else if (c == '"') {
          inString = false;
        }
      } else if (c == '/' && text.startsWith('//', i)) {
        while (i + 1 < text.length && text[i + 1] != '\n') {
          i++;
        }
      } else if (c == '/' && text.startsWith('/*', i)) {
        final end = text.indexOf('*/', i + 2);
        i = end < 0 ? text.length : end + 1;
      } else {
        if (c == '}' || c == ']') {
          while (out.isNotEmpty && out.last.trim().isEmpty) {
            out.removeLast();
          }
          if (out.isNotEmpty && out.last == ',') {
            out.removeLast();
          }
        }
        out.add(c);
        inString = c == '"';
      }
    }
    return out.join();
  }

  static const _modifiers = {
    'ctrl': 'CtrlCmd',
    'secondary': 'CtrlCmd',
    'shift': 'Shift',
    'alt': 'Alt',
    'win': 'WinCtrl',
    'cmd': 'WinCtrl',
    'super': 'WinCtrl',
  };

  static const _named = {
    'enter': 'Enter',
    'escape': 'Escape',
    'tab': 'Tab',
    'space': 'Space',
    'backspace': 'Backspace',
    'delete': 'Delete',
    'insert': 'Insert',
    'home': 'Home',
    'end': 'End',
    'pageup': 'PageUp',
    'pagedown': 'PageDown',
    'up': 'UpArrow',
    'down': 'DownArrow',
    'left': 'LeftArrow',
    'right': 'RightArrow',
    '-': 'Minus',
    '=': 'Equal',
    ',': 'Comma',
    '.': 'Period',
    '/': 'Slash',
    ';': 'Semicolon',
    "'": 'Quote',
    '[': 'BracketLeft',
    ']': 'BracketRight',
    r'\': 'Backslash',
    '`': 'Backquote',
  };

  static String? _keyCode(String key) {
    if (RegExp(r'^[a-z]$').hasMatch(key)) {
      return 'Key${key.toUpperCase()}';
    }
    if (RegExp(r'^[0-9]$').hasMatch(key)) {
      return 'Digit$key';
    }
    if (RegExp(r'^f([1-9]|1[0-9]|2[0-4])$').hasMatch(key)) {
      return key.toUpperCase();
    }
    return _named[key];
  }

  /// one keystroke, like `ctrl-shift-p` or `ctrl--`
  static String? _keystroke(String stroke) {
    final modifiers = <String>[];
    var key = stroke.toLowerCase();
    // a leading `-` is the key, so only a dash after a name is a separator
    for (var dash = key.indexOf('-'); dash > 0; dash = key.indexOf('-')) {
      final modifier = _modifiers[key.substring(0, dash)];
      if (modifier == null) {
        break;
      }
      modifiers.add(modifier);
      key = key.substring(dash + 1);
    }
    final code = _keyCode(key);
    if (code == null) {
      return null;
    }
    return [
      for (final m in modifiers) 'monaco.KeyMod.$m',
      'monaco.KeyCode.$code',
    ].join(' | ');
  }

  /// the monaco expression for [keys], one keystroke or a chord of two such as
  /// `ctrl-k ctrl-o`, or null when they are not understood; only known names
  /// reach the page, so a file cannot put script in it
  static String? toMonaco(String keys) {
    final strokes = [
      for (final s in keys.trim().split(RegExp(r'\s+'))) _keystroke(s),
    ];
    if (strokes.length > 2 || strokes.contains(null)) {
      return null;
    }
    return strokes.length == 1
        ? strokes.single
        : 'monaco.KeyMod.chord(${strokes[0]}, ${strokes[1]})';
  }

  void dispose() {
    _events?.cancel();
  }
}
