import 'dart:async';

/// when the cursor is shown and when it is not: it goes on and off every
/// [interval] while the editor is focused, and where the user does something
/// with the selections, such as typing, moving, or clicking, even in the place
/// that the cursor is at, it is shown at once and stays shown for [interval],
/// and only then goes on blinking
class CursorBlink {
  CursorBlink({
    required this.show,
    required this.hide,
    this.interval = const Duration(milliseconds: 500),
  });

  /// how long the cursor is shown, and how long it is not, and how long it
  /// stays shown after the user did something
  final Duration interval;

  /// makes the cursor shown, and not shown
  final void Function() show;
  final void Function() hide;

  bool _enabled = false;
  bool _visible = true;
  Timer? _timer;

  /// whether the cursor is blinking, which it does while it is focused
  bool get enabled => _enabled;

  /// whether the cursor is shown now
  bool get visible => _visible;

  /// starts the blinking: the cursor is shown at once, and goes off after the
  /// interval
  void enable() {
    if (_enabled) {
      return;
    }
    _enabled = true;
    // it is not shown, and blinking turns it on
    _visible = false;
    _blink();
  }

  /// stops the blinking
  void disable() {
    _enabled = false;
    _timer?.cancel();
    _timer = null;
    _visible = false;
  }

  /// the user did something with the selections: the cursor is shown now, if it
  /// was not, and the blinking goes on after it has been shown for the interval
  void pause() {
    _showNow();
    if (!_enabled) {
      return;
    }
    _timer?.cancel();
    _timer = Timer(interval, _blink);
  }

  void _showNow() {
    if (!_visible) {
      _visible = true;
      show();
    }
  }

  void _blink() {
    if (!_enabled) {
      return;
    }
    _visible = !_visible;
    if (_visible) {
      show();
    } else {
      hide();
    }
    _timer?.cancel();
    _timer = Timer(interval, _blink);
  }

  void dispose() {
    _enabled = false;
    _timer?.cancel();
    _timer = null;
  }
}
