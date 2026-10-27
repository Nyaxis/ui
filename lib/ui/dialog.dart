import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// asks [message] in the middle of the window, with the lines of [details]
/// under it, and resolves to the index in [buttons] that was chosen, or null
/// for escape. the first button is the one enter chooses, and the arrow keys
/// move between them. nothing behind the dialog takes clicks while it is open
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
  static final _pad = String.fromCharCode(0x202f);

  late final FocusNode _focus;

  /// the button enter chooses
  var _highlight = 0;

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

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      return KeyEventResult.handled;
    }
    final key = event.logicalKey;
    final count = widget.buttons.length;
    if (key == LogicalKeyboardKey.escape) {
      widget.onChosen(null);
    } else if (key == LogicalKeyboardKey.enter) {
      widget.onChosen(_highlight);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      setState(() => _highlight = (_highlight + 1) % count);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      setState(() => _highlight = (_highlight + count - 1) % count);
    }
    // the editor behind must not see keys typed into the dialog
    return KeyEventResult.handled;
  }

  /// the text between backticks is drawn as code, without the backticks
  List<InlineSpan> _spans(String message) {
    final theme = widget.theme;
    final parts = message.split('`');
    return [
      for (var i = 0; i < parts.length; i++)
        if (parts[i].isNotEmpty)
          // an odd part is between two backticks, and an unmatched one stays
          // plain; a background has no padding, so the code is set between
          // narrow no-break spaces
          if (i.isOdd && i < parts.length - 1)
            TextSpan(
              text: '$_pad${parts[i]}$_pad',
              style: theme.headingStyle.copyWith(
                fontFamily: theme.monospaceFontFamily,
                backgroundColor: theme.hover.withValues(alpha: 0.5),
              ),
            )
          else
            TextSpan(text: parts[i]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Focus(
      focusNode: _focus,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              onSecondaryTap: () {},
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.4)),
            ),
          ),
          Center(
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                width: 420,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                decoration: BoxDecoration(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(theme.cornerRadius),
                  border: Border.all(
                    color: theme.border,
                    width: theme.borderWidth,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text.rich(
                      TextSpan(children: _spans(widget.message)),
                      style: theme.headingStyle,
                    ),
                    if (widget.details.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      for (final line in widget.details)
                        Text(
                          line,
                          style: theme.bodyStyle.copyWith(color: theme.textDim),
                        ),
                    ],
                    const SizedBox(height: 18),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < widget.buttons.length; i++)
                          _DialogButton(
                            label: widget.buttons[i],
                            theme: theme,
                            highlighted: i == _highlight,
                            onHover: () => setState(() => _highlight = i),
                            onTap: () => widget.onChosen(i),
                          ),
                      ],
                    ),
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

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.theme,
    required this.highlighted,
    required this.onHover,
    required this.onTap,
  });

  final String label;
  final AppTheme theme;
  final bool highlighted;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: highlighted ? theme.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(theme.cornerRadius / 2),
            border: Border.all(
              color: highlighted ? theme.accent : theme.border,
              width: theme.borderWidth,
            ),
          ),
          child: Text(label, style: theme.bodyStyle),
        ),
      ),
    );
  }
}
