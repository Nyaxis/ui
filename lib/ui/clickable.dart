import 'package:flutter/widgets.dart';

/// what every button is built on: the pointer cursor while it can be pressed,
/// and the whole of [child] reacting, not only what it paints
class Clickable extends StatelessWidget {
  const Clickable({
    super.key,
    required this.child,
    required this.onTap,
    this.onTapDown,
    this.onTapUp,
    this.onTapCancel,
    this.onSecondaryTapUp,
    this.onEnter,
    this.onExit,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget child;

  /// the pointer, unless a button needs another; a disabled one passes
  /// [MouseCursor.defer] to keep the cursor of what is under it
  final MouseCursor cursor;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onTapDown;
  final GestureTapUpCallback? onTapUp;
  final VoidCallback? onTapCancel;
  final GestureTapUpCallback? onSecondaryTapUp;
  final VoidCallback? onEnter;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: cursor,
      onEnter: onEnter == null ? null : (_) => onEnter!(),
      onExit: onExit == null ? null : (_) => onExit!(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onTapDown: onTapDown,
        onTapUp: onTapUp,
        onTapCancel: onTapCancel,
        onSecondaryTapUp: onSecondaryTapUp,
        child: child,
      ),
    );
  }
}
