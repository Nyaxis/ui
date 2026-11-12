import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'scrollbar_layout.dart';

/// the width of the thumb, and the space around it
const double popoverThumbWidth = 6;
const double popoverThumbPadding = 4;

/// the thumb is never shorter than this
const double popoverMinThumbLength = 25;

/// how long the scrollbar stays when nothing moves it, and how long it takes
/// to go and to come
const Duration popoverScrollbarHideDelay = Duration(seconds: 1);
const Duration popoverScrollbarHideDuration = Duration(milliseconds: 400);
const Duration popoverScrollbarShowDuration = Duration(milliseconds: 50);

/// the opacity that the thumb has at most, unless the pointer is on it
const double popoverThumbOpacity = 0.7;

/// how the scrollbar shows: always, a moment after something moves it, or
/// never
enum PopoverScrollbarBehavior { always, autoHide, never }

/// what the setting for when to show scrollbars comes to; with system it is
/// what the system does
PopoverScrollbarBehavior popoverScrollbarBehavior(
  ScrollbarVisibility show, {
  required bool systemAutoHide,
}) => switch (show) {
  ScrollbarVisibility.never => PopoverScrollbarBehavior.never,
  ScrollbarVisibility.auto => PopoverScrollbarBehavior.autoHide,
  ScrollbarVisibility.always => PopoverScrollbarBehavior.always,
  ScrollbarVisibility.system =>
    systemAutoHide
        ? PopoverScrollbarBehavior.autoHide
        : PopoverScrollbarBehavior.always,
};

/// where the thumb is along [length], as the start and the length of it, for a
/// view of [viewport] of a content that goes [maxExtent] further and is
/// scrolled by [offset]; null when there is nothing to scroll
({double start, double length})? popoverThumb({
  required double viewport,
  required double maxExtent,
  required double offset,
  required double length,
}) {
  if (maxExtent <= 0 || viewport <= 0) {
    return null;
  }
  final content = viewport + maxExtent;
  final size = math.max(popoverMinThumbLength, viewport * (viewport / content));
  if (size > viewport) {
    return null;
  }
  final scrolled = offset.clamp(0.0, maxExtent);
  final start = scrolled / maxExtent * (viewport - size);
  // the part of the view, as a share of the room that there is for the thumb
  return (start: start / viewport * length, length: size / viewport * length);
}

/// the color of the thumb: [thumb] over [surface], which is only as opaque as
/// [popoverThumbOpacity] unless the pointer is [hovered]
Color popoverThumbColor({
  required Color thumb,
  required Color surface,
  required bool hovered,
}) {
  final base = hovered
      ? surface
      : surface.withValues(alpha: math.min(surface.a, popoverThumbOpacity));
  if (thumb.a >= 1) {
    return thumb;
  }
  if (thumb.a <= 0) {
    return base;
  }
  return Color.from(
    alpha: base.a,
    red: base.r * (1 - thumb.a) + thumb.r * thumb.a,
    green: base.g * (1 - thumb.a) + thumb.g * thumb.a,
    blue: base.b * (1 - thumb.a) + thumb.b * thumb.a,
  );
}

/// the ease of an animation that starts and ends slowly
double popoverEase(double delta) {
  if (delta < 0.5) {
    return 2 * delta * delta;
  }
  final x = -2 * delta + 2;
  return 1 - x * x / 2;
}

enum _Shown { visible, hidden, animating, disabled }

enum _ThumbState { inactive, hover, dragging }

/// a scrollbar that goes along the right edge of [child], over it, for the
/// text that [controller] scrolls: a thumb with no track, which goes a moment
/// after the text stops moving
class PopoverScrollbar extends StatefulWidget {
  const PopoverScrollbar({
    super.key,
    required this.controller,
    required this.behavior,
    required this.thumb,
    required this.thumbHover,
    required this.thumbActive,
    required this.surface,
    required this.child,
  });

  final ScrollController controller;
  final PopoverScrollbarBehavior behavior;

  /// the colors of the thumb, as it is, as the pointer is on it, and as it is
  /// dragged
  final Color thumb;
  final Color thumbHover;
  final Color thumbActive;

  /// what the thumb is blended with
  final Color surface;
  final Widget child;

  @override
  State<PopoverScrollbar> createState() => PopoverScrollbarState();
}

class PopoverScrollbarState extends State<PopoverScrollbar>
    with SingleTickerProviderStateMixin {
  _Shown _shown = _Shown.visible;

  /// while animating: whether it is coming, and how far the animation is
  bool _showing = true;
  double _delta = 0;
  _ThumbState _thumbState = _ThumbState.inactive;
  Timer? _hideTimer;
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  /// where the thumb was drawn last, which it is shown again for when it moves
  ({double start, double length})? _drawn;

  double _dragOffset = 0;

  /// whether the scrollbar is shown, even if it is fading
  @visibleForTesting
  bool get isShown => _shown != _Shown.hidden && _shown != _Shown.disabled;

  /// the opacity that the animation leaves, from 0 to 1
  @visibleForTesting
  double get opacity => _fade();

  @override
  void initState() {
    super.initState();
    _fromBehavior();
    if (_shown == _Shown.animating) {
      _ticker.start();
    }
    _restartAutoHide();
  }

  void _fromBehavior() {
    switch (widget.behavior) {
      case PopoverScrollbarBehavior.always:
        _shown = _Shown.visible;
      case PopoverScrollbarBehavior.never:
        _shown = _Shown.disabled;
      case PopoverScrollbarBehavior.autoHide:
        _showing = true;
        _delta = 0;
        _shown = _Shown.animating;
    }
  }

  @override
  void didUpdateWidget(PopoverScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.behavior != widget.behavior) {
      if (widget.behavior == PopoverScrollbarBehavior.autoHide && isShown) {
        // what is shown stays, and goes when it is time
      } else {
        _fromBehavior();
        if (_shown == _Shown.animating && !_ticker.isActive) {
          _last = Duration.zero;
          _ticker.start();
        }
      }
      _restartAutoHide();
    }
  }

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero ? Duration.zero : elapsed - _last;
    _last = elapsed;
    final span = _showing
        ? popoverScrollbarShowDuration
        : popoverScrollbarHideDuration;
    final next = math.min(
      1.0,
      _delta + dt.inMicroseconds / span.inMicroseconds,
    );
    setState(() {
      if (next >= 1) {
        _shown = _showing ? _Shown.visible : _Shown.hidden;
        _delta = 0;
        _ticker.stop();
        _last = Duration.zero;
      } else {
        _delta = next;
      }
    });
  }

  /// how much of the thumb's opacity is taken away
  double _fade() {
    if (_shown != _Shown.animating) {
      return 0;
    }
    return popoverEase(_showing ? 1 - _delta : _delta);
  }

  /// brings the scrollbar, or keeps it, and lets it go when the time comes
  void show() {
    if (!mounted) {
      return;
    }
    switch (_shown) {
      case _Shown.hidden:
        _showing = true;
        _delta = 0;
        _beginAnimating();
      case _Shown.animating when !_showing:
        _showing = true;
        _delta = 1 - _delta;
        _beginAnimating();
      case _Shown.animating:
      case _Shown.visible:
      case _Shown.disabled:
        break;
    }
    _restartAutoHide();
  }

  void _beginAnimating() {
    setState(() => _shown = _Shown.animating);
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _restartAutoHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _scheduleAutoHide();
  }

  void _scheduleAutoHide() {
    if (_hideTimer != null ||
        !isShown ||
        widget.behavior != PopoverScrollbarBehavior.autoHide) {
      return;
    }
    _hideTimer = Timer(popoverScrollbarHideDelay, () {
      _hideTimer = null;
      if (!mounted) {
        return;
      }
      if (_thumbState == _ThumbState.inactive) {
        _showing = false;
        _delta = 0;
        _beginAnimating();
      }
    });
  }

  void _setThumbState(_ThumbState state) {
    if (state == _thumbState) {
      return;
    }
    setState(() => _thumbState = state);
    if (state == _ThumbState.inactive) {
      _scheduleAutoHide();
    } else {
      _hideTimer?.cancel();
      _hideTimer = null;
      show();
      _hideTimer?.cancel();
      _hideTimer = null;
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _dragStart(DragStartDetails details, double top) {
    _dragOffset = details.localPosition.dy;
    _setThumbState(_ThumbState.dragging);
  }

  /// scrolls so that the thumb goes where the pointer is, as it was grabbed
  void _dragUpdate(DragUpdateDetails details, double top, double room) {
    final controller = widget.controller;
    if (!controller.hasClients) {
      return;
    }
    final position = controller.position;
    final thumb = popoverThumb(
      viewport: position.viewportDimension,
      maxExtent: position.maxScrollExtent,
      offset: position.pixels,
      length: room,
    );
    if (thumb == null) {
      return;
    }
    // the pointer, along the room that the thumb has
    final y = details.globalPosition.dy - top - _dragOffset;
    final start = y.clamp(0.0, math.max(0.0, room - thumb.length));
    final share = room > thumb.length ? start / (room - thumb.length) : 0.0;
    controller.jumpTo(share * position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => show(),
      child: Stack(
        children: [
          widget.child,
          // as big as the child, which has the size that the scrollbar goes by
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) => ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) => _content(constraints),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BoxConstraints constraints) {
    final controller = widget.controller;
    final height = constraints.maxHeight;
    final width = constraints.maxWidth;
    final room = math.max(0.0, height - 2 * popoverThumbPadding);
    ({double start, double length})? thumb;
    if (_shown != _Shown.disabled && controller.hasClients) {
      final position = controller.position;
      thumb = popoverThumb(
        viewport: position.viewportDimension,
        maxExtent: position.maxScrollExtent,
        offset: position.pixels,
        length: room,
      );
    }
    // a thumb that is somewhere else than it was shown the scrollbar again
    final before = _drawn;
    if (thumb != before &&
        (before == null ||
            thumb == null ||
            thumb.start != before.start ||
            thumb.length != before.length)) {
      _drawn = thumb;
      if (thumb != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => show());
      }
    }
    final children = <Widget>[];
    if (thumb != null && isShown) {
      final top = popoverThumbPadding + thumb.start;
      final colors = switch (_thumbState) {
        _ThumbState.dragging => (widget.thumbActive, false),
        _ThumbState.hover => (widget.thumbHover, true),
        _ThumbState.inactive => (widget.thumb, false),
      };
      var color = popoverThumbColor(
        thumb: colors.$1,
        surface: widget.surface,
        hovered: colors.$2,
      );
      final fade = _fade();
      if (!colors.$2 && fade > 0) {
        color = color.withValues(alpha: color.a * (1 - fade));
      }
      children.add(
        Positioned(
          left: width - popoverThumbPadding - popoverThumbWidth,
          top: top,
          width: popoverThumbWidth,
          height: thumb.length,
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            onEnter: (_) {
              if (_thumbState == _ThumbState.inactive) {
                _setThumbState(_ThumbState.hover);
              }
            },
            onExit: (_) {
              if (_thumbState == _ThumbState.hover) {
                _setThumbState(_ThumbState.inactive);
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (d) => _dragStart(d, top),
              onVerticalDragUpdate: (d) => _dragUpdate(
                d,
                (context.findRenderObject() as RenderBox)
                        .localToGlobal(Offset.zero)
                        .dy +
                    popoverThumbPadding,
                room,
              ),
              onVerticalDragEnd: (_) => _setThumbState(_ThumbState.inactive),
              onVerticalDragCancel: () => _setThumbState(_ThumbState.inactive),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(popoverThumbWidth / 2),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Stack(clipBehavior: Clip.none, children: children);
  }
}
