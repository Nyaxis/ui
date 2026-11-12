import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_theme.dart';
import 'clickable.dart';
import 'elevation.dart';
import 'skinnable_icon.dart';

/// how a picker looks: sizes in pixels
class PickerMetrics {
  const PickerMetrics._();

  /// a picker of a list is 34 rems wide, and one of a line of text 24
  static const double listWidth = 544;
  static const double inputWidth = 384;

  /// the most that the list is high, which is 24 rems
  static const double maxListHeight = 384;

  /// the field, and the room at its sides
  static const double fieldHeight = 36;
  static const double fieldPadding = 10;

  /// above and below the rows, and at the sides of what a row fills
  static const double listPadding = 4;
  static const double rowInset = 4;

  /// between a row's fill and what is in it
  static const double rowPadding = 6;

  /// the text of a row, which has four pixels of room above and below it
  static const double fontSize = 14;
  static const double lineHeight = 1.618;
  static const double rowHeight = fontSize * lineHeight + 8;
  static const double rowRadius = 4;
  static const double radius = 8;
}

/// a line of a list picker
class PickerItem {
  const PickerItem(this.label, {this.checked = false, this.icon});

  final String label;

  /// the svg asset drawn before the label
  final String? icon;

  /// marks the current choice
  final bool checked;
}

/// opens a picker of [items] at the top of the window, with a field to filter
/// them by when [hint] is given. the arrow keys move the highlight, enter runs
/// [onSelected] with the index in [items], and escape or anything else closes
/// it
void showListPicker(
  BuildContext context, {
  required AppTheme theme,
  required List<PickerItem> items,
  required ValueChanged<int> onSelected,
  String? hint,
  double top = 0,
}) {
  _show(
    context,
    (close) => _Picker(
      theme: theme,
      top: top,
      width: PickerMetrics.listWidth,
      items: items,
      hint: hint,
      onSelected: onSelected,
      onClose: close,
    ),
  );
}

/// opens a field at the top of the window, with a line under it that
/// [describe] writes for what is typed. enter runs [onSubmitted] with the
/// text, and escape or anything else closes it. [initialText] is in the field
/// at first, and selected
void showInputPicker(
  BuildContext context, {
  required AppTheme theme,
  required String hint,
  required String Function(String text) describe,
  required ValueChanged<String> onSubmitted,
  String initialText = '',
  double top = 0,
}) {
  _show(
    context,
    (close) => _Picker(
      theme: theme,
      top: top,
      width: PickerMetrics.inputWidth,
      hint: hint,
      initialText: initialText,
      describe: describe,
      onSubmitted: onSubmitted,
      onClose: close,
    ),
  );
}

void _show(BuildContext context, _Picker Function(VoidCallback close) build) {
  late final OverlayEntry overlay;
  overlay = OverlayEntry(builder: (_) => build(overlay.remove));
  Overlay.of(context).insert(overlay);
}

class _Picker extends StatefulWidget {
  const _Picker({
    required this.theme,
    required this.top,
    required this.width,
    this.items,
    this.hint,
    this.initialText = '',
    this.describe,
    this.onSelected,
    this.onSubmitted,
    this.onClose,
  });

  final AppTheme theme;
  final double top;
  final double width;
  final List<PickerItem>? items;
  final String? hint;
  final String initialText;
  final String Function(String text)? describe;
  final ValueChanged<int>? onSelected;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClose;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> with WindowListener {
  static const _rowHeight = PickerMetrics.rowHeight;
  static const _maxListHeight = PickerMetrics.maxListHeight;

  late final _text = TextEditingController(text: widget.initialText);
  final _scroll = ScrollController();
  late final FocusNode _focus;

  /// the index in the filtered list that is highlighted
  late int _highlight;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode(onKeyEvent: _onKey);
    final current = widget.items?.indexWhere((i) => i.checked) ?? -1;
    _highlight = current < 0 ? 0 : current;
    // the page under the picker has focus already, so autofocus would not move it
    _focus.requestFocus();
    _text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _text.text.length,
    );
    _text.addListener(() => setState(() => _highlight = 0));
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _focus.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// switching to another window closes the picker without choosing anything
  @override
  void onWindowBlur() => widget.onClose?.call();

  /// the indexes in [PickerItem]s of the items the text matches
  List<int> get _shown {
    final items = widget.items;
    if (items == null) {
      return const [];
    }
    final query = _text.text.toLowerCase();
    return [
      for (var i = 0; i < items.length; i++)
        if (items[i].label.toLowerCase().contains(query)) i,
    ];
  }

  void _choose(int index) {
    widget.onClose?.call();
    widget.onSelected?.call(index);
  }

  /// goes [by] rows down, or up for a negative number, and round the ends
  void _move(int by) {
    final count = _shown.length;
    if (count == 0) {
      return;
    }
    _goTo((_highlight + by) % count);
  }

  /// highlights the row [index] of those that are shown
  void _goTo(int index) {
    final count = _shown.length;
    if (count == 0) {
      return;
    }
    setState(() => _highlight = index.clamp(0, count - 1));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) {
        return;
      }
      final top = _highlight * _rowHeight;
      final view = _scroll.position.viewportDimension;
      if (top < _scroll.offset) {
        _scroll.jumpTo(top);
      } else if (top + _rowHeight > _scroll.offset + view) {
        _scroll.jumpTo(top + _rowHeight - view);
      }
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final control = keyboard.isControlPressed;
    final shift = keyboard.isShiftPressed;
    // a field keeps home and end for the cursor in it
    final hasField = widget.hint != null;
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose?.call();
    } else if (key == LogicalKeyboardKey.arrowDown ||
        (control && key == LogicalKeyboardKey.keyN) ||
        (key == LogicalKeyboardKey.tab && !shift)) {
      _move(1);
    } else if (key == LogicalKeyboardKey.arrowUp ||
        (control && key == LogicalKeyboardKey.keyP) ||
        (key == LogicalKeyboardKey.tab && shift)) {
      _move(-1);
    } else if (key == LogicalKeyboardKey.pageUp ||
        (!hasField && key == LogicalKeyboardKey.home)) {
      _goTo(0);
    } else if (key == LogicalKeyboardKey.pageDown ||
        (!hasField && key == LogicalKeyboardKey.end)) {
      _goTo(_shown.length - 1);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (widget.items != null) {
        final shown = _shown;
        if (shown.isNotEmpty) {
          _choose(shown[_highlight.clamp(0, shown.length - 1)]);
        }
      } else {
        widget.onClose?.call();
        widget.onSubmitted?.call(_text.text);
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final items = widget.items;
    final shown = _shown;
    final hint = widget.hint;
    final describe = widget.describe;
    final line = Container(height: 1, color: theme.borderVariant);
    return Stack(
      children: [
        // anything outside the picker closes it, and is not passed on
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => widget.onClose?.call(),
            onSecondaryTapDown: (_) => widget.onClose?.call(),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: widget.top),
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                width: widget.width,
                decoration: BoxDecoration(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(PickerMetrics.radius),
                  border: Border.all(color: theme.borderVariant),
                  boxShadow: modalShadows(theme),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hint != null) ...[
                      SizedBox(
                        height: PickerMetrics.fieldHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: PickerMetrics.fieldPadding,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextField(
                              controller: _text,
                              focusNode: _focus,
                              cursorColor: theme.accent,
                              style: theme.bodyStyle,
                              decoration: InputDecoration.collapsed(
                                hintText: hint,
                                hintStyle: theme.bodyStyle.copyWith(
                                  color: theme.active,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (items != null || describe != null) line,
                    ] else
                      // a picker without a field still takes the keys
                      Focus(focusNode: _focus, child: const SizedBox.shrink()),
                    if (items != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: PickerMetrics.listPadding,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: _maxListHeight,
                            // a list of few items is as tall as they are
                            minHeight: 0,
                          ),
                          child: ListView.builder(
                            controller: _scroll,
                            shrinkWrap: true,
                            itemExtent: _rowHeight,
                            itemCount: shown.length,
                            itemBuilder: (context, i) => _Row(
                              item: items[shown[i]],
                              theme: theme,
                              highlighted: i == _highlight,
                              onHover: () => setState(() => _highlight = i),
                              onTap: () => _choose(shown[i]),
                            ),
                          ),
                        ),
                      ),
                    if (describe != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Text(
                          describe(_text.text),
                          style: theme.bodyStyle.copyWith(color: theme.textDim),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.item,
    required this.theme,
    required this.highlighted,
    required this.onHover,
    required this.onTap,
  });

  final PickerItem item;
  final AppTheme theme;
  final bool highlighted;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Clickable(
      onEnter: onHover,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: PickerMetrics.rowInset),
        padding: const EdgeInsets.symmetric(
          horizontal: PickerMetrics.rowPadding,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          // the row that the pointer is on is the one that is chosen
          color: highlighted
              ? theme.chosen.withValues(alpha: 0x66 / 255)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(PickerMetrics.rowRadius),
        ),
        child: Row(
          children: [
            if (item.icon != null) ...[
              SvgPicture.asset(item.icon!, width: 16, height: 16),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: theme.fontFamily,
                  fontSize: PickerMetrics.fontSize,
                  fontWeight: FontWeight.w400,
                  height: PickerMetrics.lineHeight,
                  color: theme.textPrimary,
                ),
              ),
            ),
            if (item.checked)
              SkinnableIcon(name: 'checkmark', size: 14, color: theme.accent),
          ],
        ),
      ),
    );
  }
}
