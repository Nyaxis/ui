import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
                },
                onHorizontalDragUpdate: (details) {
                  final moved = details.globalPosition.dx - _startX;
                  widget.onResize(_startWidth + (onLeft ? moved : -moved));
                },
                onHorizontalDragEnd: (_) => widget.onResizeEnd(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
