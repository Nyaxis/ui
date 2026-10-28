import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_theme.dart';
import 'clickable.dart';
import 'skinnable_icon.dart';

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
      width: 540,
      items: items,
      hint: hint,
      onSelected: onSelected,
      onClose: close,
    ),
  );
}

/// opens a field at the top of the window, with a line under it that
/// [describe] writes for what is typed. enter runs [onSubmitted] with the
/// text, and escape or anything else closes it
void showInputPicker(
  BuildContext context, {
  required AppTheme theme,
  required String hint,
  required String Function(String text) describe,
  required ValueChanged<String> onSubmitted,
  double top = 0,
}) {
  _show(
    context,
    (close) => _Picker(
      theme: theme,
      top: top,
      width: 380,
      hint: hint,
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
  final String Function(String text)? describe;
  final ValueChanged<int>? onSelected;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClose;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> with WindowListener {
  static const _rowHeight = 30.0;
  static const _maxListHeight = 400.0;

  final _text = TextEditingController();
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

  void _move(int by) {
    final count = _shown.length;
    if (count == 0) {
      return;
    }
    setState(() => _highlight = (_highlight + by).clamp(0, count - 1));
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
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose?.call();
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
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
    final line = Container(height: theme.borderWidth, color: theme.border);
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
                    if (hint != null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: TextField(
                          controller: _text,
                          focusNode: _focus,
                          cursorColor: theme.accent,
                          style: theme.bodyStyle,
                          decoration: InputDecoration.collapsed(
                            hintText: hint,
                            hintStyle: theme.bodyStyle.copyWith(
                              color: theme.textDim.withValues(alpha: 0.6),
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
                        padding: const EdgeInsets.symmetric(vertical: 4),
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
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: highlighted
              ? theme.selection.withValues(alpha: 0.3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            if (item.icon != null) ...[
              SvgPicture.asset(item.icon!, width: 16, height: 16),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(item.label, style: theme.bodyStyle)),
            if (item.checked)
              SkinnableIcon(name: 'checkmark', size: 14, color: theme.textDim),
          ],
        ),
      ),
    );
  }
}
