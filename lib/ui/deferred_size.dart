import 'dart:async';

import 'package:flutter/material.dart';

/// lays out [child] at the size its parent held until it has stopped changing
/// for [delay], so that a child that is expensive to resize, such as a
/// webview, is not resized on every frame of a window drag; meanwhile the
/// child is cropped when the parent shrinks and leaves a gap when it grows
class DeferredSize extends StatefulWidget {
  const DeferredSize({
    super.key,
    required this.child,
    this.delay = const Duration(milliseconds: 120),
  });

  final Widget child;
  final Duration delay;

  @override
  State<DeferredSize> createState() => _DeferredSizeState();
}

class _DeferredSizeState extends State<DeferredSize> {
  Size? _size;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final live = constraints.biggest;
        final size = _size ??= live;
        _timer?.cancel();
        if (live != size) {
          _timer = Timer(widget.delay, () {
            if (mounted) {
              setState(() => _size = live);
            }
          });
        }
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: size.width,
            maxWidth: size.width,
            minHeight: size.height,
            maxHeight: size.height,
            child: widget.child,
          ),
        );
      },
    );
  }
}
