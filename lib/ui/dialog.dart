import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'clickable.dart';
import 'elevation.dart';

/// how a dialog looks: sizes in pixels
class DialogMetrics {
  const DialogMetrics._();

  static const double width = 320;

  /// around everything in it, and between the message, the lines under it and
  /// the buttons
  static const double padding = 16;
  static const double gap = 16;

  /// between the buttons, which are one under the other
  static const double buttonGap = 4;
  static const double buttonHeight = 22;
  static const double buttonPadding = 4;
  static const double buttonRadius = 4;
  static const double radius = 8;

  /// the size of the message, of what is under it, and of a button's label
  static const double messageSize = 16;
  static const double detailSize = 12;
  static const double labelSize = 14;
  static const double lineHeight = 1.618;

  /// how much of the window shows through what is behind the dialog
  static const double backdropOpacity = 0.2;

  /// the label of the button that escape chooses
  static const String cancelLabel = 'Cancel';
}

/// the fills and lines of a button, as the theme has them
class DialogButtonColors {
  const DialogButtonColors(this.theme);

  final AppTheme theme;

  bool get _light => theme.background.computeLuminance() > 0.5;

  /// a button at rest
  Color get fill => theme.titleBar;
  Color get line => theme.borderVariant;

  /// the pointer is on it
  Color get hoverFill => theme.hover.withValues(alpha: 0x4D / 255);
  Color get hoverLine => theme.border;

  /// it is pressed
  Color get pressedFill => theme.active.withValues(alpha: 0x4D / 255);

  /// the button that enter chooses, which has the color for information
  Color get tintFill => theme.info.withValues(alpha: 0x33 / 255);
  Color get tintLine => theme.info;

  /// the tinted button with the pointer on it, which is darker
  Color get tintHoverFill {
    final hsl = HSLColor.fromColor(tintFill);
    return hsl
        .withLightness((hsl.lightness - (_light ? 0.05 : 0.2)).clamp(0.0, 1.0))
        .toColor();
  }
}

/// asks [message] in the middle of the window, with the lines of [details]
/// under it, and resolves to the index in [buttons] that was chosen. the first
/// button is the one enter chooses; up and down move between them, and escape
/// chooses the one labeled Cancel, and does nothing when there is none.
/// nothing behind the dialog takes clicks while it is open
Future<int?> showConfirmDialog(
  BuildContext context, {
  required AppTheme theme,
  required String message,
  required List<String> buttons,
  List<String> details = const [],
}) {
  final completer = Completer<int?>();
  late final OverlayEntry overlay;
  overlay = OverlayEntry(
    builder: (_) => _Dialog(
      theme: theme,
      message: message,
      details: details,
      buttons: buttons,
      onChosen: (choice) {
        if (!completer.isCompleted) {
          overlay.remove();
          completer.complete(choice);
        }
      },
    ),
  );
  Overlay.of(context).insert(overlay);
  return completer.future;
}

class _Dialog extends StatefulWidget {
  const _Dialog({
    required this.theme,
    required this.message,
    required this.details,
    required this.buttons,
    required this.onChosen,
  });

  final AppTheme theme;
  final String message;
  final List<String> details;
  final List<String> buttons;
  final ValueChanged<int?> onChosen;

  @override
  State<_Dialog> createState() => _DialogState();
}

class _DialogState extends State<_Dialog> {
  late final FocusNode _focus;

  /// the button enter chooses
  var _active = 0;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode(onKeyEvent: _onKey);
    // the page under the dialog has focus already, so autofocus would not move it
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _next() =>
      setState(() => _active = (_active + 1) % widget.buttons.length);

  void _previous() => setState(
    () => _active = _active > 0 ? _active - 1 : widget.buttons.length - 1,
  );

  /// chooses the button labeled Cancel, if there is one
  void _cancel() {
    final index = widget.buttons.indexOf(DialogMetrics.cancelLabel);
    if (index >= 0) {
      widget.onChosen(index);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // the editor behind must not see keys typed into the dialog
    if (event is KeyUpEvent) {
      return KeyEventResult.handled;
    }
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final control = keyboard.isControlPressed;
    final shift = keyboard.isShiftPressed;
    final first = event is KeyDownEvent;
    if (first &&
        (key == LogicalKeyboardKey.escape ||
            (control && key == LogicalKeyboardKey.keyC))) {
      _cancel();
    } else if (first &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      widget.onChosen(_active);
    } else if (key == LogicalKeyboardKey.arrowDown ||
        (control && key == LogicalKeyboardKey.keyN) ||
        (key == LogicalKeyboardKey.tab && !shift)) {
      _next();
    } else if (key == LogicalKeyboardKey.arrowUp ||
        (control && key == LogicalKeyboardKey.keyP) ||
        (key == LogicalKeyboardKey.tab && shift)) {
      _previous();
    } else if (key == LogicalKeyboardKey.home ||
        key == LogicalKeyboardKey.pageUp) {
      // the buttons are in the order of how they are asked, and the one that
      // is chosen first is the last
      setState(() => _active = widget.buttons.length - 1);
    } else if (key == LogicalKeyboardKey.end ||
        key == LogicalKeyboardKey.pageDown) {
      setState(() => _active = 0);
    }
    return KeyEventResult.handled;
  }

  /// the message as it is shown: the text between two backticks is the text
  /// itself, and a backtick that has no other stays
  static String _plain(String message) {
    final parts = message.split('`');
    final out = StringBuffer();
    for (var i = 0; i < parts.length; i++) {
      if (i.isOdd && i == parts.length - 1) {
        out.write('`');
      }
      out.write(parts[i]);
    }
    return out.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    TextStyle text(double size, Color color) => TextStyle(
      fontFamily: theme.fontFamily,
      fontSize: size,
      fontWeight: FontWeight.w400,
      height: DialogMetrics.lineHeight,
      color: color,
    );
    return Focus(
      focusNode: _focus,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              onSecondaryTap: () {},
              child: ColoredBox(
                color: Colors.black.withValues(
                  alpha: DialogMetrics.backdropOpacity,
                ),
              ),
            ),
          ),
          Center(
            child: Material(
              type: MaterialType.transparency,
              // a container, so that the border takes room as it does in a box
              child: Container(
                width: DialogMetrics.width,
                padding: const EdgeInsets.all(DialogMetrics.padding),
                decoration: BoxDecoration(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(DialogMetrics.radius),
                  border: Border.all(color: theme.borderVariant),
                  boxShadow: modalShadows(theme),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _plain(widget.message),
                      style: text(DialogMetrics.messageSize, theme.textPrimary),
                    ),
                    if (widget.details.isNotEmpty) ...[
                      const SizedBox(height: DialogMetrics.gap),
                      for (final line in widget.details)
                        Text(
                          line,
                          style: text(DialogMetrics.detailSize, theme.textDim),
                        ),
                    ],
                    const SizedBox(height: DialogMetrics.gap),
                    for (var i = 0; i < widget.buttons.length; i++) ...[
                      if (i > 0)
                        const SizedBox(height: DialogMetrics.buttonGap),
                      _DialogButton(
                        label: widget.buttons[i],
                        theme: theme,
                        style: text(DialogMetrics.labelSize, theme.textPrimary),
                        active: i == _active,
                        onTap: () => widget.onChosen(i),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogButton extends StatefulWidget {
  const _DialogButton({
    required this.label,
    required this.theme,
    required this.style,
    required this.active,
    required this.onTap,
  });

  final String label;
  final AppTheme theme;
  final TextStyle style;

  /// whether it is the one that enter chooses
  final bool active;
  final VoidCallback onTap;

  @override
  State<_DialogButton> createState() => _DialogButtonState();
}

class _DialogButtonState extends State<_DialogButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = DialogButtonColors(widget.theme);
    final Color fill;
    final Color line;
    if (widget.active) {
      // a tinted button is not changed by a press
      fill = _hovered ? colors.tintHoverFill : colors.tintFill;
      line = colors.tintLine;
    } else if (_pressed) {
      fill = colors.pressedFill;
      line = colors.line;
    } else if (_hovered) {
      fill = colors.hoverFill;
      line = colors.hoverLine;
    } else {
      fill = colors.fill;
      line = colors.line;
    }
    return Clickable(
      onEnter: () => setState(() => _hovered = true),
      onExit: () => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: Container(
        height: DialogMetrics.buttonHeight,
        padding: const EdgeInsets.symmetric(
          horizontal: DialogMetrics.buttonPadding,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(DialogMetrics.buttonRadius),
          border: Border.all(color: line),
        ),
        child: Text(
          widget.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: widget.style,
        ),
      ),
    );
  }
}
