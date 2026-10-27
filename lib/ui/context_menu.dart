import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../editor/keymap.dart';
import '../theme/app_theme.dart';
import 'skinnable_icon.dart';

sealed class ContextMenuEntry {
  const ContextMenuEntry();
}

/// a line that does something when it is chosen
class ContextMenuItem extends ContextMenuEntry {
  const ContextMenuItem(
    this.label, {
    this.onPressed,
    this.action,
    this.checked,
  });

  final String label;

  /// a check mark before the label when true; any value makes room for the
  /// mark, so the labels of a menu of choices line up
  final bool? checked;

  /// null greys the item out, and it does nothing when pressed
  final VoidCallback? onPressed;

  /// the keymap action that does the same, whose keys are shown beside the
  /// label
  final String? action;
}

/// a line between groups of items
class ContextMenuSeparator extends ContextMenuEntry {
  const ContextMenuSeparator();
}

/// opens a menu of [entries] with its corner at [position], in the overlay's
/// coordinates, moved to stay inside it. the menu closes when an item is chosen
/// or anything else is pressed. [keysFor] finds the keys of an item's action,
/// such as [Keymap.keysFor]. [onClosed] runs once the menu is gone
void showContextMenu(
  BuildContext context, {
  required Offset position,
  required List<ContextMenuEntry> entries,
  required AppTheme theme,
  String? Function(String action)? keysFor,
  VoidCallback? onClosed,
}) {
  late final OverlayEntry overlay;
  overlay = OverlayEntry(
    builder: (context) => _MenuLayer(
      position: position,
      entries: entries,
      theme: theme,
      keysFor: keysFor,
      onClose: () {
        overlay.remove();
        onClosed?.call();
      },
    ),
  );
  Overlay.of(context).insert(overlay);
}

class _MenuLayer extends StatefulWidget {
  const _MenuLayer({
    required this.position,
    required this.entries,
    required this.theme,
    required this.keysFor,
    required this.onClose,
  });

  final Offset position;
  final List<ContextMenuEntry> entries;
  final AppTheme theme;
  final String? Function(String action)? keysFor;
  final VoidCallback onClose;

  @override
  State<_MenuLayer> createState() => _MenuLayerState();
}

class _MenuLayerState extends State<_MenuLayer> with WindowListener {
  static const _padding = 5.0;
  static const _minWidth = 180.0;

  // the page under the menu has focus already, so autofocus would not move it
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _focus.dispose();
    super.dispose();
  }

  /// switching to another window closes the menu without choosing anything
  @override
  void onWindowBlur() => widget.onClose();

  @override
  Widget build(BuildContext context) {
    final position = widget.position;
    final entries = widget.entries;
    final theme = widget.theme;
    final keysFor = widget.keysFor;
    final onClose = widget.onClose;
    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          // anything outside the menu closes it, and is not passed on
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => onClose(),
              onSecondaryTapDown: (_) => onClose(),
            ),
          ),
          CustomSingleChildLayout(
            delegate: _MenuLayout(position),
            child: Material(
              type: MaterialType.transparency,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(theme.cornerRadius),
                  border: Border.all(
                    color: theme.border,
                    width: theme.borderWidth,
                  ),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: _minWidth),
                  child: IntrinsicWidth(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: _padding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final entry in entries)
                            switch (entry) {
                              ContextMenuSeparator() => Container(
                                height: theme.borderWidth,
                                margin: const EdgeInsets.symmetric(
                                  vertical: _padding,
                                ),
                                color: theme.border,
                              ),
                              ContextMenuItem() => _Item(
                                item: entry,
                                theme: theme,
                                keys: switch (entry.action) {
                                  final action? => keysFor?.call(action),
                                  null => null,
                                },
                                onClose: onClose,
                              ),
                            },
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// puts the menu's corner at the position, or as close as keeps it inside and
/// off the window's edge
class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout(this.position);

  final Offset position;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  /// space kept between the menu and the window's edge
  static const _edge = 8.0;

  double _fit(double at, double space, double child) {
    final high = space - child - _edge;
    return at.clamp(_edge, high < _edge ? _edge : high).toDouble();
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    _fit(position.dx, size.width, childSize.width),
    _fit(position.dy, size.height, childSize.height),
  );

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      oldDelegate.position != position;
}

class _Item extends StatefulWidget {
  const _Item({
    required this.item,
    required this.theme,
    required this.keys,
    required this.onClose,
  });

  final ContextMenuItem item;
  final AppTheme theme;
  final String? keys;
  final VoidCallback onClose;

  @override
  State<_Item> createState() => _ItemState();
}

class _ItemState extends State<_Item> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final onPressed = widget.item.onPressed;
    final enabled = onPressed != null;
    final keys = widget.keys;
    final color = enabled
        ? theme.textPrimary
        : theme.textDim.withValues(alpha: 0.5);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                widget.onClose();
                onPressed();
              }
            : null,
        child: Container(
          height: 26,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          // the check mark's column starts at the fill's edge, so the mark is
          // centered between the edge and the label
          padding: EdgeInsets.only(
            left: widget.item.checked == null ? 8 : 0,
            right: 8,
          ),
          decoration: BoxDecoration(
            color: enabled && _hovered
                ? theme.hover.withValues(alpha: 0.3)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              if (widget.item.checked != null)
                SizedBox(
                  width: 25,
                  child: widget.item.checked!
                      ? Center(
                          child: SkinnableIcon(
                            name: 'checkmark',
                            size: 14,
                            color: theme.accent.withValues(
                              alpha: enabled ? 1 : 0.5,
                            ),
                          ),
                        )
                      : null,
                ),
              Text(
                widget.item.label,
                style: theme.bodyStyle.copyWith(color: color),
              ),
              const SizedBox(width: 24),
              const Spacer(),
              if (keys != null)
                Text(
                  Keymap.formatKeys(keys),
                  style: theme.bodyStyle.copyWith(
                    color: theme.textDim.withValues(alpha: enabled ? 1 : 0.5),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
