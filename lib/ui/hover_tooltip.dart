import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../editor/keymap.dart';
import '../theme/app_theme.dart';
import 'elevation.dart';

/// how a tooltip looks and when it comes: what is in rems goes with the size of
/// the interface's text, which [AppTheme.rem] says
class TooltipMetrics {
  const TooltipMetrics(this.theme);

  final AppTheme theme;

  /// how long the pointer is on what has the tooltip before it is shown, from
  /// the first time that it moves there
  static const Duration showDelay = Duration(milliseconds: 500);

  /// between the pointer and the tooltip, in pixels, which has room of its own
  /// above and to the left so that it does not come up under the pointer
  static const double pointerGap = 1;
  double get roomLeft => theme.rem(8);
  double get roomTop => theme.rem(10);

  /// inside the panel
  double get paddingX => theme.rem(8);
  double get paddingY => theme.rem(4);

  /// the most that the title and the line under it are wide
  double get maxWidth => theme.rem(288);

  /// between the title and the keys
  double get keysGap => theme.rem(16);
  double get radius => theme.rem(8);
  double get fontSize => theme.rem(14);
  double get metaSize => theme.rem(12);
  static const double lineHeight = 1.618;
}

/// where a tooltip of [size] goes when the pointer is at [mouse] in a window of
/// [window]: just under and to the right of the pointer. when that is past the
/// right edge it goes to the left of the pointer, and when that is not room
/// either it is moved to the edge; the same under the bottom edge, and above
Offset placeTooltip(Offset mouse, Size size, Size window) {
  var x = mouse.dx + TooltipMetrics.pointerGap;
  var y = mouse.dy + TooltipMetrics.pointerGap;
  if (x + size.width > window.width) {
    final left = mouse.dx - size.width - TooltipMetrics.pointerGap;
    x = left >= 0 ? left : math.max(0.0, x - (x + size.width) - window.width);
  }
  if (y + size.height > window.height) {
    final above = mouse.dy - size.height - TooltipMetrics.pointerGap;
    y = above >= 0
        ? above
        : math.max(0.0, y - (y + size.height) - window.height);
  }
  return Offset(x, y);
}

class _TooltipPlacement extends SingleChildLayoutDelegate {
  const _TooltipPlacement(this.mouse);

  final Offset mouse;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      placeTooltip(mouse, childSize, size);

  @override
  bool shouldRelayout(_TooltipPlacement oldDelegate) =>
      oldDelegate.mouse != mouse;
}

/// what a tooltip says: a [title], the [keys] of what it names beside it, and a
/// line of [meta] under it
class TooltipPanel extends StatelessWidget {
  const TooltipPanel({
    super.key,
    required this.theme,
    required this.title,
    this.keys,
    this.meta,
  });

  final AppTheme theme;
  final String title;

  /// in [Keymap.toKeys] form
  final String? keys;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    TextStyle text(double size, Color color) => TextStyle(
      fontFamily: theme.fontFamily,
      fontSize: size,
      fontWeight: FontWeight.w400,
      height: TooltipMetrics.lineHeight,
      color: color,
      decoration: TextDecoration.none,
    );
    final keys = this.keys;
    final meta = this.meta;
    final metrics = TooltipMetrics(theme);
    return Padding(
      padding: EdgeInsets.only(left: metrics.roomLeft, top: metrics.roomTop),
      // a container, so that the border takes room as it does in a box
      child: Container(
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(metrics.radius),
          border: Border.all(color: theme.borderVariant),
          boxShadow: elevatedShadows(theme),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: metrics.paddingX,
            vertical: metrics.paddingY,
          ),
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: metrics.maxWidth),
                      child: Text(
                        title,
                        style: text(metrics.fontSize, theme.textPrimary),
                      ),
                    ),
                    if (keys != null) ...[
                      SizedBox(width: metrics.keysGap),
                      Text(
                        Keymap.formatKeys(keys),
                        style: text(metrics.fontSize, theme.textDim),
                      ),
                    ],
                  ],
                ),
                if (meta != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: metrics.maxWidth),
                    child: Text(
                      meta,
                      style: text(metrics.metaSize, theme.textDim),
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

/// names [child] when the pointer has been on it for half a second, in a panel
/// beside the pointer. it goes when the pointer leaves, is pressed, or the
/// wheel turns. nothing is shown while [enabled] is false
class HoverTooltip extends StatefulWidget {
  const HoverTooltip({
    super.key,
    required this.theme,
    required this.title,
    required this.child,
    this.keys,
    this.meta,
    this.enabled = true,
  });

  final AppTheme theme;
  final String title;

  /// the keys of what it names, in [Keymap.toKeys] form, shown beside the title
  final String? keys;
  final String? meta;
  final bool enabled;
  final Widget child;

  @override
  State<HoverTooltip> createState() => HoverTooltipState();
}

class HoverTooltipState extends State<HoverTooltip> {
  Timer? _timer;
  OverlayEntry? _entry;

  /// where the pointer was last seen, on the screen
  Offset _pointer = Offset.zero;

  /// whether a tooltip is shown
  @visibleForTesting
  bool get isShown => _entry != null;

  void _moved(PointerEvent event) {
    _pointer = event.position;
    // the time counts from the first move onto it, and the tooltip stays where
    // it was shown while the pointer moves on it
    if (_timer == null && _entry == null && widget.enabled) {
      _timer = Timer(TooltipMetrics.showDelay, _show);
    }
  }

  void _show() {
    _timer = null;
    if (!mounted || !widget.enabled) {
      return;
    }
    final mouse = _pointer;
    final theme = widget.theme;
    final entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: CustomSingleChildLayout(
          delegate: _TooltipPlacement(mouse),
          child: TooltipPanel(
            theme: theme,
            title: widget.title,
            keys: widget.keys,
            meta: widget.meta,
          ),
        ),
      ),
    );
    _entry = entry;
    Overlay.of(context).insert(entry);
  }

  /// takes the tooltip away, and the wait for one
  void _hide() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  @override
  void didUpdateWidget(HoverTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) {
      _hide();
    }
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: _moved,
      onExit: (_) => _hide(),
      child: Listener(
        // what is under it still gets what is pressed and scrolled
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _hide(),
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            _hide();
          }
        },
        child: widget.child,
      ),
    );
  }
}
