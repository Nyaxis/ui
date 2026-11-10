import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// which of shift, control, alt and the windows key are down, as the editor
/// sees it. flutter keeps a key down that went up while its window was not
/// looking, as alt does with alt tab, until it is pressed again, which made
/// every click add a cursor. here the keys are forgotten whenever the window
/// is not the one in front, so the next click is a plain one.
class ModifierKeys with WidgetsBindingObserver {
  ModifierKeys._();

  static final ModifierKeys instance = ModifierKeys._();

  final Set<LogicalKeyboardKey> _down = {};
  bool _observing = false;

  static final _shift = {
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
  };
  static final _control = {
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
  };
  static final _alt = {LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight};
  static final _meta = {
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };

  /// starts to follow the keys. it can be called again, which puts the
  /// handler back where it was dropped, as a test does between its runs
  void start() {
    final keyboard = HardwareKeyboard.instance;
    keyboard.removeHandler(_onKey);
    keyboard.addHandler(_onKey);
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
  }

  bool _onKey(KeyEvent event) {
    final key = event.logicalKey;
    if (_shift.contains(key) ||
        _control.contains(key) ||
        _alt.contains(key) ||
        _meta.contains(key)) {
      if (event is KeyUpEvent) {
        _down.remove(key);
      } else {
        _down.add(key);
      }
    }
    // it only looks
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      forget();
    }
  }

  /// takes every key as up
  void forget() => _down.clear();

  bool get isShiftPressed => _down.any(_shift.contains);
  bool get isControlPressed => _down.any(_control.contains);
  bool get isAltPressed => _down.any(_alt.contains);
  bool get isMetaPressed => _down.any(_meta.contains);
}
