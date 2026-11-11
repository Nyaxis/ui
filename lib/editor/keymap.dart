import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../native_editor/modifier_keys.dart';
import 'key_context.dart';

/// a key sequence, in the context it applies in, and the action it runs; a
/// null action unbinds the keys
class Binding {
  const Binding(this.context, this.keys, this.action);

  final ContextExpression? context;

  /// the strokes in [Keymap.toKeys] form, like `ctrl-k ctrl-o`
  final String keys;
  final String? action;
}

/// the keys that run each action, in the format of zed's keymaps: sections of
/// `"keys": "namespace::Action"` bindings, each for a context. the defaults are
/// bundled, and `keymap.json` in `%APPDATA%\Nyaxis` is applied after them, so
/// its bindings win, and a key set to null is unbound. the file is polled, so
/// changes apply at once.
///
/// keys are read by flutter wherever they are pressed, and go to [_press],
/// which is the only one that knows the bindings and contexts. what an action
/// does is set with [on], and keys of actions without a handler are left
/// alone
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

  static const _workspace = KeyContext({'Workspace'});
  static const _editor = KeyContext({'Workspace', 'Editor'});

  var _bindings = <Binding>[];
  final _handlers = <String, Future<void> Function()>{};
  Timer? _poll;

  /// the first stroke of a chord that has been pressed
  String? _pending;

  void on(String action, Future<void> Function() handler) {
    _handlers[action] = handler;
  }

  /// whether the editor has the focus, which says in which context a key is
  /// pressed; it reports its keys to flutter like any other widget
  bool Function()? _nativeFocus;

  /// every key comes to flutter, and [editorFocused] says which context it is
  /// pressed in
  Future<void> attachNative(bool Function() editorFocused) async {
    _nativeFocus = editorFocused;
    // the modifiers are followed before the strokes are looked at
    ModifierKeys.instance.start();
    HardwareKeyboard.instance.addHandler(_onKey);
    await _reload();
    _watchUserFile();
  }

  void _watchUserFile() {
    // the file is polled, since watching its folder takes the app down
    final file = _userFile;
    if (file != null) {
      var modified = file.statSync().modified;
      _poll = Timer.periodic(const Duration(seconds: 1), (_) {
        final now = file.statSync().modified;
        if (now != modified) {
          modified = now;
          unawaited(_reload());
        }
      });
    }
  }

  File? get _userFile {
    final appData = Platform.environment['APPDATA'];
    return appData == null ? null : File('$appData\\Nyaxis\\keymap.json');
  }

  /// creates the file with a template when it is missing, so it can be found
  Future<String?> _readUserKeymap() async {
    final file = _userFile;
    if (file == null) {
      debugPrint('Keymap: APPDATA unavailable, using the defaults');
      return null;
    }
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

  Future<void> _reload() async {
    final defaults = await rootBundle.loadString(_defaults);
    final user = await _readUserKeymap();
    try {
      _bindings = resolve([defaults, ?user]);
    } on FormatException catch (e) {
      debugPrint('Keymap: unreadable keymap.json ($e)');
      _bindings = resolve([defaults]);
    }
    _pending = null;
  }

  /// the actions bound in [context], by keys; of several bindings of the same
  /// keys the last applying one counts, even when it unbinds
  ///
  /// shortcut: a binding in a deeper context does not beat a later one in a
  /// wider context, as it does in zed; add that when contexts nest
  Map<String, String> _active(KeyContext context, {bool onlyHandled = true}) {
    final seen = <String>{};
    final actions = <String, String>{};
    for (final binding in _bindings.reversed) {
      if (binding.context?.matches(context) == false ||
          !seen.add(binding.keys)) {
        continue;
      }
      final action = binding.action;
      if (action != null && (!onlyHandled || _handlers.containsKey(action))) {
        actions[binding.keys] = action;
      }
    }
    return actions;
  }

  /// the keys that run [action] while the editor is focused, in [toKeys] form,
  /// or null when none do; the last binding of the action counts
  String? keysFor(String action) {
    for (final binding in _active(_editor, onlyHandled: false).entries) {
      if (binding.value == action) {
        return binding.key;
      }
    }
    return null;
  }

  /// [keys] as they are shown to the user, like `Ctrl-K Shift-Enter`
  static String formatKeys(String keys) {
    String capitalize(String name) => switch (name) {
      'pageup' => 'PageUp',
      'pagedown' => 'PageDown',
      _ => name[0].toUpperCase() + name.substring(1),
    };
    return [
      for (final stroke in keys.split(' '))
        _splitStroke(stroke).map(capitalize).join('-'),
    ].join(' ');
  }

  /// a stroke's modifiers followed by its key
  static List<String> _splitStroke(String stroke) {
    final parts = <String>[];
    var key = stroke;
    for (var dash = key.indexOf('-'); dash > 0; dash = key.indexOf('-')) {
      if (!_modifierOrder.contains(key.substring(0, dash))) {
        break;
      }
      parts.add(key.substring(0, dash));
      key = key.substring(dash + 1);
    }
    return [...parts, key];
  }

  /// whether the stroke was used, which is when its keys are bound or the
  /// start of a chord that is
  bool _press(String stroke, KeyContext context) {
    final keys = _pending == null ? stroke : '$_pending $stroke';
    _pending = null;
    final actions = _active(context);
    final action = actions[keys];
    if (action != null) {
      unawaited(_handlers[action]!());
      return true;
    }
    if (actions.keys.any((k) => k.startsWith('$keys '))) {
      _pending = keys;
      return true;
    }
    return false;
  }

  bool _onKey(KeyEvent event) {
    final editorFocused = _nativeFocus;
    final key = editorFocused == null || event is! KeyDownEvent
        ? null
        : _logicalName(event.logicalKey);
    if (key == null) {
      return false;
    }
    // the modifiers are the ones that are followed, which are not down after
    // the window was left with one down
    final followed = ModifierKeys.instance;
    return _press(
      [
        if (followed.isControlPressed) 'ctrl',
        if (followed.isAltPressed) 'alt',
        if (followed.isShiftPressed) 'shift',
        if (followed.isMetaPressed) 'win',
        key,
      ].join('-'),
      editorFocused!() ? _editor : _workspace,
    );
  }

  static final _logicalNames = {
    LogicalKeyboardKey.enter: 'enter',
    LogicalKeyboardKey.escape: 'escape',
    LogicalKeyboardKey.tab: 'tab',
    LogicalKeyboardKey.space: 'space',
    LogicalKeyboardKey.backspace: 'backspace',
    LogicalKeyboardKey.delete: 'delete',
    LogicalKeyboardKey.insert: 'insert',
    LogicalKeyboardKey.home: 'home',
    LogicalKeyboardKey.end: 'end',
    LogicalKeyboardKey.pageUp: 'pageup',
    LogicalKeyboardKey.pageDown: 'pagedown',
    LogicalKeyboardKey.arrowUp: 'up',
    LogicalKeyboardKey.arrowDown: 'down',
    LogicalKeyboardKey.arrowLeft: 'left',
    LogicalKeyboardKey.arrowRight: 'right',
    LogicalKeyboardKey.f1: 'f1',
    LogicalKeyboardKey.f2: 'f2',
    LogicalKeyboardKey.f3: 'f3',
    LogicalKeyboardKey.f4: 'f4',
    LogicalKeyboardKey.f5: 'f5',
    LogicalKeyboardKey.f6: 'f6',
    LogicalKeyboardKey.f7: 'f7',
    LogicalKeyboardKey.f8: 'f8',
    LogicalKeyboardKey.f9: 'f9',
    LogicalKeyboardKey.f10: 'f10',
    LogicalKeyboardKey.f11: 'f11',
    LogicalKeyboardKey.f12: 'f12',
  };

  /// the key's name in a keymap, or null for modifiers and keys without one;
  /// printable keys are named by their character
  static String? _logicalName(LogicalKeyboardKey key) {
    final id = key.keyId;
    return _logicalNames[key] ??
        (id > 0x20 && id < 0x7f ? String.fromCharCode(id).toLowerCase() : null);
  }

  /// the bindings of keymaps, in the order they apply
  static List<Binding> resolve(Iterable<String> keymaps) {
    final bindings = <Binding>[];
    for (final keymap in keymaps) {
      final sections = jsonDecode(_stripComments(keymap));
      if (sections is! List) {
        throw const FormatException('a keymap is a list of sections');
      }
      for (final section in sections) {
        if (section is! Map || section['bindings'] is! Map) {
          continue;
        }
        ContextExpression? context;
        try {
          final source = section['context'];
          context = source == null ? null : ContextExpression.parse('$source');
        } on FormatException catch (e) {
          debugPrint('Keymap: ignoring the context ${section['context']} ($e)');
          continue;
        }
        for (final binding in (section['bindings'] as Map).entries) {
          final keys = toKeys('${binding.key}');
          final action = binding.value;
          if (keys == null || (action != null && action is! String)) {
            debugPrint('Keymap: ignoring ${binding.key}: $action');
          } else {
            bindings.add(Binding(context, keys, action as String?));
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

  /// modifier names to the ones keys are written with
  static const _modifiers = {
    'ctrl': 'ctrl',
    'secondary': 'ctrl',
    'alt': 'alt',
    'shift': 'shift',
    'win': 'win',
    'cmd': 'win',
    'super': 'win',
  };

  /// the order modifiers are written in
  static const _modifierOrder = ['ctrl', 'alt', 'shift', 'win'];

  /// the names of keys that are not letters, digits or function keys
  static const _otherKeys = {
    'enter',
    'escape',
    'tab',
    'space',
    'backspace',
    'delete',
    'insert',
    'home',
    'end',
    'pageup',
    'pagedown',
    'up',
    'down',
    'left',
    'right',
    '-',
    '=',
    '+',
    ',',
    '.',
    '/',
    ';',
    "'",
    '[',
    ']',
    r'\',
    '`',
  };

  static final _plainKey = RegExp(r'^([a-z0-9]|f([1-9]|1[0-9]|2[0-4]))$');

  /// one keystroke like `ctrl-shift-p` or `ctrl--`, with its modifiers in a
  /// fixed order
  static String? _keystroke(String stroke) {
    final modifiers = <String>{};
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
    if (!_plainKey.hasMatch(key) && !_otherKeys.contains(key)) {
      return null;
    }
    return [
      for (final m in _modifierOrder)
        if (modifiers.contains(m)) m,
      key,
    ].join('-');
  }

  /// [keys] with their modifiers in order, one keystroke or a chord of two such
  /// as `ctrl-k ctrl-o`, or null when they are not understood
  static String? toKeys(String keys) {
    final strokes = [
      for (final s in keys.trim().split(RegExp(r'\s+'))) _keystroke(s),
    ];
    return strokes.length > 2 || strokes.contains(null)
        ? null
        : strokes.join(' ');
  }

  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _poll?.cancel();
  }
}
