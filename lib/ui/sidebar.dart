import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../editor/keymap.dart';
import '../theme/app_theme.dart';
import 'clickable.dart';
import 'skinnable_icon.dart';

/// a view that can be opened from the sidebar, with its icon on the left and
/// the keys that open it, when any are bound, on the right
class SidebarItem extends StatefulWidget {
  const SidebarItem({
    super.key,
    required this.theme,
    required this.icon,
    required this.label,
    required this.keys,
    required this.selected,
    required this.onTap,
  });

  /// the name of the icon in `assets/icons`
  final String icon;
  final AppTheme theme;
  final String label;

  /// in [Keymap.toKeys] form, null when none are bound
  final String? keys;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final keys = widget.keys;
    final color = widget.selected ? theme.textPrimary : theme.textDim;
    return Clickable(
      onEnter: () => setState(() => _hovered = true),
      onExit: () => setState(() => _hovered = false),
      onTap: widget.onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          // as the buttons of the bars are, and as Zed's borderless elements
          color: widget.selected
              ? theme.active.withValues(alpha: 0.6)
              : (_hovered ? theme.hover.withValues(alpha: 0.3) : null),
          borderRadius: BorderRadius.circular(theme.cornerRadius / 2),
        ),
        child: Row(
          children: [
            SkinnableIcon(name: widget.icon, size: 16, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.label,
                overflow: TextOverflow.ellipsis,
                style: theme.bodyStyle.copyWith(color: color),
              ),
            ),
            if (keys != null) ...[
              const SizedBox(width: 8),
              Text(Keymap.formatKeys(keys), style: theme.captionStyle),
            ],
          ],
        ),
      ),
    );
  }
}

/// a panel beside the editor, whose edge towards the editor is dragged to
/// resize it; [onResize] gets the width the drag asks for, and [onResizeEnd]
/// is called when it lets go
class SidebarPanel extends StatefulWidget {
  const SidebarPanel({
    super.key,
    required this.theme,
    required this.width,
    required this.onLeft,
    required this.onResize,
    required this.onResizeEnd,
    this.child,
  });

  static const minWidth = 160.0;
  static const maxWidth = 600.0;

  final AppTheme theme;
  final double width;

  /// the side of the window it is docked to
  final bool onLeft;
  final ValueChanged<double> onResize;
  final VoidCallback onResizeEnd;
  final Widget? child;

  @override
  State<SidebarPanel> createState() => _SidebarPanelState();
}

class _SidebarPanelState extends State<SidebarPanel> {
  /// the strip along the edge that takes the drag
  static const _grip = 6.0;

  /// where the pointer went down, and how wide the panel was then; the width
  /// is worked out from these and not from the last one, since events that
  /// arrive in one frame would each start from the same stale width
  var _startX = 0.0;
  var _startWidth = 0.0;

  /// the edge trails the pointer while it is dragged, so the cursor is kept
  /// by a layer over the whole window instead of by the strip alone
  OverlayEntry? _dragCursor;

  void _startDragCursor() {
    _dragCursor = OverlayEntry(
      builder: (_) => const Positioned.fill(
        child: MouseRegion(cursor: SystemMouseCursors.resizeColumn),
      ),
    );
    Overlay.of(context).insert(_dragCursor!);
  }

  void _endDragCursor() {
    _dragCursor?.remove();
    _dragCursor?.dispose();
    _dragCursor = null;
  }

  @override
  void dispose() {
    _endDragCursor();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final onLeft = widget.onLeft;
    final edge = BorderSide(color: theme.border, width: theme.borderWidth);
    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border(
          left: onLeft ? BorderSide.none : edge,
          right: onLeft ? edge : BorderSide.none,
        ),
      ),
      child: Stack(
        children: [
          if (widget.child != null) Positioned.fill(child: widget.child!),
          Positioned(
            top: 0,
            bottom: 0,
            left: onLeft ? null : 0,
            right: onLeft ? 0 : null,
            width: _grip,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // from the press, so the edge stays under the pointer instead
                // of trailing it by the distance the drag needs to start
                dragStartBehavior: DragStartBehavior.down,
                onHorizontalDragStart: (details) {
                  _startX = details.globalPosition.dx;
                  _startWidth = widget.width;
                  _startDragCursor();
                },
                onHorizontalDragUpdate: (details) {
                  final moved = details.globalPosition.dx - _startX;
                  widget.onResize(_startWidth + (onLeft ? moved : -moved));
                },
                onHorizontalDragEnd: (_) {
                  _endDragCursor();
                  widget.onResizeEnd();
                },
                onHorizontalDragCancel: _endDragCursor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
