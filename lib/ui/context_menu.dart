import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../editor/keymap.dart';
import '../theme/app_theme.dart';
import 'clickable.dart';
import 'elevation.dart';
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
    this.leading,
  });

  final String label;

  /// drawn between the check mark and the label, such as a preview of what
  /// the item chooses
  final Widget? leading;

  /// a check mark before the label when true; any value makes room for the
  /// mark, so the labels of a menu of choices line up
  final bool? checked;

  /// null greys the item out, and it does nothing when pressed
  final VoidCallback? onPressed;

  /// the keymap action that does the same, whose keys are shown beside the
  /// label
  final String? action;

  /// whether the item can be chosen, with the pointer or with the keys
  bool get selectable => onPressed != null;
}

/// a line between groups of items
class ContextMenuSeparator extends ContextMenuEntry {
  const ContextMenuSeparator();
}

/// how a menu looks: sizes in pixels, as the menus of the editor it follows
/// have them
class ContextMenuMetrics {
  const ContextMenuMetrics._();

  /// the least that a menu is wide
  static const double minWidth = 200;

  /// the most that a menu is high, as a share of the window; it scrolls when
  /// there is more
  static const double maxHeightShare = 0.75;

  /// above and below the items
  static const double listPadding = 4;

  /// between the menu's edge and where an item's fill starts
  static const double itemInset = 4;

  /// between an item's fill and what is in it
  static const double itemPadding = 6;

  /// between the parts of an item: the check mark, the preview and the label
  static const double itemGap = 6;
  static const double itemRadius = 4;
  static const double menuRadius = 8;

  /// the size of the text, and of a line of it, which is also what an item is
  /// high
  static const double fontSize = 14;
  static const double lineHeight = 1.618;
  static const double checkSize = 14;

  /// between the label and the keys of its action
  static const double keysGap = 16;

  /// above and below a separator, which is a line of one pixel
  static const double separatorMargin = 6;

  /// kept between the menu and the window's edge
  static const double windowEdge = 8;

  /// what an item is high
  static const double itemHeight = fontSize * lineHeight;
}

/// the fills that an item has, in the colors of the theme
class ContextMenuColors {
  const ContextMenuColors(this.theme);

  final AppTheme theme;

  /// the pointer is on the item
  Color get hover => theme.hover.withValues(alpha: 0x4D / 255);

  /// the item is pressed
  Color get pressed => theme.active.withValues(alpha: 0x99 / 255);

  /// the item is chosen with the keys
  Color get selected => theme.chosen.withValues(alpha: 0x66 / 255);
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
  // the page under the menu has focus already, so autofocus would not move it
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _measured = GlobalKey();
  late final List<GlobalKey> _itemKeys = [
    for (final _ in widget.entries) GlobalKey(),
  ];

  /// the item that the keys have chosen; the pointer going over an item takes
  /// it away
  int? _selected;

  /// how big the items are all together, once they have been laid out, which
  /// is what the menu is when it does not scroll
  Size? _natural;

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final size = _measured.currentContext?.size;
      if (mounted && size != null) {
        setState(() => _natural = size);
      }
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// switching to another window closes the menu without choosing anything
  @override
  void onWindowBlur() => widget.onClose();

  bool _selectable(int index) {
    final entry = widget.entries[index];
    return entry is ContextMenuItem && entry.selectable;
  }

  void _select(int? index) {
    if (index == _selected) {
      return;
    }
    setState(() => _selected = index);
    final context = index == null ? null : _itemKeys[index].currentContext;
    if (context != null && _scroll.hasClients) {
      Scrollable.ensureVisible(context);
    }
  }

  void _selectFirst() {
    for (var i = 0; i < widget.entries.length; i++) {
      if (_selectable(i)) {
        _select(i);
        return;
      }
    }
  }

  void _selectLast() {
    for (var i = widget.entries.length - 1; i >= 0; i--) {
      if (_selectable(i)) {
        _select(i);
        return;
      }
    }
  }

  /// the next item that can be chosen; from the last, or when none is chosen,
  /// the first
  void _selectNext() {
    final from = _selected;
    if (from != null) {
      for (var i = from + 1; i < widget.entries.length; i++) {
        if (_selectable(i)) {
          _select(i);
          return;
        }
      }
    }
    _selectFirst();
  }

  /// the previous one; from the first, or when none is chosen, the last
  void _selectPrevious() {
    final from = _selected;
    if (from != null) {
      for (var i = from - 1; i >= 0; i--) {
        if (_selectable(i)) {
          _select(i);
          return;
        }
      }
    }
    _selectLast();
  }

  /// runs the chosen item and closes the menu; with none chosen it only closes
  void _confirm() {
    final index = _selected;
    widget.onClose();
    if (index != null && _selectable(index)) {
      (widget.entries[index] as ContextMenuItem).onPressed!();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final control = keyboard.isControlPressed;
    final shift = keyboard.isShiftPressed;
    final first = event is KeyDownEvent;
    if (first &&
        (key == LogicalKeyboardKey.escape ||
            (control && key == LogicalKeyboardKey.keyC))) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        (control && key == LogicalKeyboardKey.keyP) ||
        (shift && key == LogicalKeyboardKey.tab)) {
      _selectPrevious();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        (control && key == LogicalKeyboardKey.keyN) ||
        key == LogicalKeyboardKey.tab) {
      _selectNext();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home || key == LogicalKeyboardKey.pageUp) {
      _selectFirst();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end || key == LogicalKeyboardKey.pageDown) {
      _selectLast();
      return KeyEventResult.handled;
    }
    if (first &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      _confirm();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _items() {
    final theme = widget.theme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: ContextMenuMetrics.listPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < widget.entries.length; i++)
            KeyedSubtree(
              key: _itemKeys[i],
              child: switch (widget.entries[i]) {
                ContextMenuSeparator() => Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(
                    vertical: ContextMenuMetrics.separatorMargin,
                  ),
                  color: theme.borderVariant,
                ),
                final ContextMenuItem item => _Item(
                  item: item,
                  theme: theme,
                  selected: _selected == i,
                  keys: switch (item.action) {
                    final action? => widget.keysFor?.call(action),
                    null => null,
                  },
                  onHover: () => _select(null),
                  onClose: widget.onClose,
                ),
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final maxHeight =
        MediaQuery.sizeOf(context).height * ContextMenuMetrics.maxHeightShare;
    // what the border takes is not for the items
    final inner = maxHeight - 2;
    final natural = _natural;
    final scrolls = natural != null && natural.height > inner;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          // anything outside the menu closes it, and is not passed on
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => widget.onClose(),
              onSecondaryTapDown: (_) => widget.onClose(),
            ),
          ),
          CustomSingleChildLayout(
            delegate: _MenuLayout(widget.position, measuring: natural == null),
            child: Material(
              type: MaterialType.transparency,
              child: DefaultTextStyle(
                style: TextStyle(
                  fontFamily: theme.fontFamily,
                  fontSize: ContextMenuMetrics.fontSize,
                  height: ContextMenuMetrics.lineHeight,
                  color: theme.textPrimary,
                ),
                // a container, so that the border takes room as it does in a box
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.surface,
                    borderRadius: BorderRadius.circular(
                      ContextMenuMetrics.menuRadius,
                    ),
                    border: Border.all(color: theme.borderVariant),
                    boxShadow: elevatedShadows(theme),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: ContextMenuMetrics.minWidth - 2,
                      maxHeight: natural == null ? double.infinity : inner,
                    ),
                    child: scrolls
                        ? SizedBox(
                            width: math.max(
                              natural.width,
                              ContextMenuMetrics.minWidth,
                            ),
                            child: SingleChildScrollView(
                              controller: _scroll,
                              child: _items(),
                            ),
                          )
                        : IntrinsicWidth(key: _measured, child: _items()),
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
  _MenuLayout(this.position, {required this.measuring});

  final Offset position;

  /// whether the menu is laid out to find how high its items are all together,
  /// which they are free to be then
  final bool measuring;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => measuring
      ? BoxConstraints(maxWidth: constraints.maxWidth)
      : constraints.loosen();

  double _fit(double at, double space, double child) {
    const edge = ContextMenuMetrics.windowEdge;
    final high = space - child - edge;
    return at.clamp(edge, high < edge ? edge : high).toDouble();
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    _fit(position.dx, size.width, childSize.width),
    _fit(position.dy, size.height, childSize.height),
  );

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      oldDelegate.position != position || oldDelegate.measuring != measuring;
}

class _Item extends StatefulWidget {
  const _Item({
    required this.item,
    required this.theme,
    required this.selected,
    required this.keys,
    required this.onHover,
    required this.onClose,
  });

  final ContextMenuItem item;
  final AppTheme theme;

  /// whether the keys have chosen it
  final bool selected;
  final String? keys;

  /// told when the pointer goes over it
  final VoidCallback onHover;
  final VoidCallback onClose;

  @override
  State<_Item> createState() => _ItemState();
}

class _ItemState extends State<_Item> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final item = widget.item;
    final onPressed = item.onPressed;
    final enabled = onPressed != null;
    final keys = widget.keys;
    final colors = ContextMenuColors(theme);
    final labelColor = enabled ? theme.textPrimary : theme.disabled;
    final keysColor = enabled ? theme.textDim : theme.disabled;
    final fill = !enabled
        ? Colors.transparent
        : _pressed && _hovered
        ? colors.pressed
        : _hovered
        ? colors.hover
        : widget.selected
        ? colors.selected
        : Colors.transparent;
    return Clickable(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: () {
        setState(() => _hovered = true);
        if (enabled) {
          widget.onHover();
        }
      },
      onExit: () => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: enabled
          ? () {
              widget.onClose();
              onPressed();
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ContextMenuMetrics.itemInset,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(ContextMenuMetrics.itemRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ContextMenuMetrics.itemPadding,
            ),
            child: Row(
              children: [
                if (item.checked != null) ...[
                  // the room is kept when there is no mark, so that the labels
                  // of a menu of choices line up
                  SizedBox(
                    width: ContextMenuMetrics.checkSize,
                    child: item.checked!
                        ? SkinnableIcon(
                            name: 'checkmark',
                            size: ContextMenuMetrics.checkSize,
                            color: enabled ? theme.accent : theme.disabled,
                          )
                        : null,
                  ),
                  const SizedBox(width: ContextMenuMetrics.itemGap),
                ],
                if (item.leading != null) ...[
                  item.leading!,
                  const SizedBox(width: ContextMenuMetrics.itemGap),
                ],
                Flexible(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: labelColor),
                  ),
                ),
                const Spacer(),
                if (keys != null)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: ContextMenuMetrics.keysGap,
                    ),
                    child: Text(
                      Keymap.formatKeys(keys),
                      style: TextStyle(color: keysColor),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
