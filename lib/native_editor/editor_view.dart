import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'diagnostic_hover.dart';
import 'editor_controller.dart';
import 'editor_keys.dart';
import 'editor_style.dart';
import 'editor_text_input.dart';
import 'modifier_keys.dart';
import 'render_editor.dart';
import 'scrollbar_layout.dart';

/// shows the text of an [EditorController], and takes what is typed, clicked
/// and dragged on it
class EditorView extends StatefulWidget {
  const EditorView({
    super.key,
    required this.controller,
    this.style = const EditorStyle(),
    this.softWrap = true,
    this.showLineNumbers = true,
    this.scrollbars = const ScrollbarSettings(),
    this.hover = const HoverSettings(),
    this.tooltip,
    this.mouseWheelZoom = false,
    this.onZoom,
    this.focusNode,
    this.autofocus = false,
    this.readOnly = false,
    this.onFocusChanged,
  });

  /// when what the language server found is shown for the text that the
  /// pointer rests on
  final HoverSettings hover;

  /// the tooltip of the buttons in what is shown for it
  final Widget Function(String message, Widget child)? tooltip;

  /// told when the editor gains or loses the focus
  final void Function(bool focused)? onFocusChanged;

  final EditorController controller;
  final EditorStyle style;
  final bool softWrap;
  final bool showLineNumbers;

  /// when the text has scrollbars, and what they mark
  final ScrollbarSettings scrollbars;

  /// whether the wheel with the control key down zooms, which is told to
  /// [onZoom] as a step of one for the wheel going up and minus one for down,
  /// and does not scroll
  final bool mouseWheelZoom;
  final ValueChanged<int>? onZoom;
  final FocusNode? focusNode;
  final bool autofocus;

  /// whether the text may not be changed
  final bool readOnly;

  @override
  State<EditorView> createState() => EditorViewState();
}

class EditorViewState extends State<EditorView> {
  final GlobalKey _renderKey = GlobalKey();
  Timer? _blink;
  late EditorTextInput _input;

  /// the connection to the input method
  @visibleForTesting
  EditorTextInput get input => _input;

  // clicks in a row, for the double and the triple click
  int _clicks = 0;
  Duration _lastClickAt = Duration.zero;
  Offset _lastClickPosition = Offset.zero;
  bool _dragging = false;

  FocusNode get focusNode => widget.focusNode ?? widget.controller.focusNode;

  // what the language server found, shown for the text that the pointer rests
  // on

  /// what is shown now
  DiagnosticDetail? _popover;
  final GlobalKey _popoverKey = GlobalKey();
  Timer? _showTimer;
  Timer? _hideTimer;

  /// how near the pointer has been to the popover, as it goes toward it
  double? _closest;

  /// where the selections were when the popover was shown, which it does not
  /// outlast
  int _selectionKey = 0;

  /// whether a popover is shown
  @visibleForTesting
  DiagnosticDetail? get popover => _popover;

  int _selectionsNow() => Object.hashAll([
    for (final s in widget.controller.selections.all) ...[s.start, s.end],
  ]);

  /// takes the popover away, and what was about to show one
  void _hideHover() {
    _showTimer?.cancel();
    _showTimer = null;
    _hideTimer?.cancel();
    _hideTimer = null;
    _closest = null;
    if (_popover == null) {
      return;
    }
    // a change of the editor can come while the frame is built, when a view
    // cannot be set
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _popover != null) {
          setState(() => _popover = null);
        }
      });
    } else {
      setState(() => _popover = null);
    }
  }

  /// the pointer is at [position] of the editor, and [global] on the screen;
  /// [position] is null when it is not on text
  void _updateHover(Offset? position, Offset? global) {
    final settings = widget.hover;
    if (!settings.enabled) {
      return;
    }
    final render = _render;
    final offset = position == null || render == null
        ? null
        : render.hoverOffsetAt(position);
    if (offset != null && (render!.scrollbarAt(position!) == null)) {
      _hideTimer?.cancel();
      _hideTimer = null;
      _closest = null;
      if (_popover != null) {
        return;
      }
      _showTimer?.cancel();
      _selectionKey = _selectionsNow();
      _showTimer = Timer(settings.delay, () => _showHover(offset));
      return;
    }
    _showTimer?.cancel();
    _showTimer = null;
    if (_popover == null) {
      return;
    }
    if (!settings.sticky) {
      _hideHover();
      return;
    }
    final closer = global != null && _gettingCloser(global);
    if (!closer && _hideTimer != null) {
      return;
    }
    _hideTimer?.cancel();
    _hideTimer = Timer(settings.hidingDelay, _hideHover);
  }

  void _showHover(int offset) {
    _showTimer = null;
    if (!mounted) {
      return;
    }
    final detail = widget.controller.diagnosticAt(offset);
    if (detail == null) {
      return;
    }
    _selectionKey = _selectionsNow();
    setState(() => _popover = detail);
  }

  /// whether the pointer at [global] is not further from the popover than it
  /// has been, by more than four pixels, as it is when it goes toward it
  bool _gettingCloser(Offset global) {
    final box = _popoverKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return false;
    }
    final bounds = box.localToGlobal(Offset.zero) & box.size;
    final dx = math.max(
      0.0,
      (global.dx - bounds.center.dx).abs() - bounds.width / 2,
    );
    final dy = math.max(
      0.0,
      (global.dy - bounds.center.dy).abs() - bounds.height / 2,
    );
    final distance = math.sqrt(dx * dx + dy * dy);
    final closest = _closest;
    if (closest != null && distance > closest + 4) {
      return false;
    }
    _closest = closest == null ? distance : math.min(distance, closest);
    return true;
  }

  /// the pointer is on the popover, which stays
  void _onPopoverPointer() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _closest = 0;
  }

  RenderEditor? get _render =>
      _renderKey.currentContext?.findRenderObject() as RenderEditor?;

  @override
  void initState() {
    super.initState();
    _input = EditorTextInput(widget.controller);
    ModifierKeys.instance.start();
    focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onControllerChange);
    widget.controller.scrollbarHeld = _scrollbarHeld;
    _scrollX = widget.controller.scrollX;
    _scrollY = widget.controller.scrollY;
  }

  double _scrollX = 0;
  double _scrollY = 0;
  bool _scrollCheck = false;

  // the scrollbars are shown for a moment when the text scrolls, or the pointer
  // is at one of them. whether they are shown, and when they go, is of the
  // editor and not of its view, which is made again when a tab is switched to

  bool _scrollbarHeld() => _scrollbarDrag != null;

  void _showScrollbars() => widget.controller.showScrollbars();

  @override
  void didUpdateWidget(EditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollbars.show != widget.scrollbars.show) {
      widget.controller.showScrollbars();
    }
    if (!widget.hover.enabled && oldWidget.hover.enabled) {
      _hideHover();
    }
    final oldNode = oldWidget.focusNode ?? oldWidget.controller.focusNode;
    if (oldNode != focusNode) {
      oldNode.removeListener(_onFocusChange);
      focusNode.addListener(_onFocusChange);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChange);
      oldWidget.controller.scrollbarHeld = null;
      widget.controller.scrollbarHeld = _scrollbarHeld;
      _input.detach();
      _input = EditorTextInput(widget.controller);
      widget.controller.addListener(_onControllerChange);
      if (focusNode.hasFocus) {
        _input.attach();
      }
    }
  }

  void _onFocusChange() {
    widget.controller.setFocus(focusNode.hasFocus);
    widget.onFocusChanged?.call(focusNode.hasFocus);
    _blink?.cancel();
    if (!focusNode.hasFocus) {
      _hideHover();
    }
    if (focusNode.hasFocus) {
      if (!widget.readOnly) {
        _input.attach();
      }
      _blink = Timer.periodic(const Duration(milliseconds: 530), (_) {
        widget.controller.setCursorVisible(!widget.controller.cursorVisible);
      });
    } else {
      _input.detach();
    }
  }

  void _onControllerChange() {
    final controller = widget.controller;
    // the popover does not outlast a change of where the selections are, which
    // is also what typing does
    if ((_popover != null || _showTimer != null) &&
        _selectionsNow() != _selectionKey) {
      _hideHover();
    }
    if (!_scrollCheck &&
        (controller.scrollX != _scrollX || controller.scrollY != _scrollY)) {
      // the layout puts the text back when it was asked to go past its ends,
      // which is not a scroll, so the scroll is looked at once it is laid out
      _scrollCheck = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollCheck = false;
        if (!mounted) {
          return;
        }
        final now = widget.controller;
        if (now.scrollX != _scrollX || now.scrollY != _scrollY) {
          _scrollX = now.scrollX;
          _scrollY = now.scrollY;
          _showScrollbars();
          _hideHover();
        }
      });
    }
    if (!_input.attached) {
      return;
    }
    _input.sync();
    // the position of the cursor is known once the view is laid out
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateGeometry());
  }

  void _updateGeometry() {
    final render = _render;
    if (!mounted || render == null || !render.attached || !_input.attached) {
      return;
    }
    final head = widget.controller.selections.newest.head;
    _input.updateGeometry(
      size: render.size,
      transform: render.getTransformTo(null),
      caret: render.caretRectForOffset(head),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_popover != null &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _hideHover();
      return KeyEventResult.handled;
    }
    if (widget.readOnly) {
      final keyboard = ModifierKeys.instance;
      final command = keyboard.isControlPressed || keyboard.isMetaPressed;
      if (!(command && event.logicalKey == LogicalKeyboardKey.keyC) &&
          !(command && event.logicalKey == LogicalKeyboardKey.keyA) &&
          event.logicalKey != LogicalKeyboardKey.arrowLeft &&
          event.logicalKey != LogicalKeyboardKey.arrowRight &&
          event.logicalKey != LogicalKeyboardKey.arrowUp &&
          event.logicalKey != LogicalKeyboardKey.arrowDown &&
          event.logicalKey != LogicalKeyboardKey.home &&
          event.logicalKey != LogicalKeyboardKey.end &&
          event.logicalKey != LogicalKeyboardKey.pageUp &&
          event.logicalKey != LogicalKeyboardKey.pageDown) {
        return KeyEventResult.ignored;
      }
    }
    return handleEditorKey(widget.controller, event);
  }

  // the mouse

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) {
      return;
    }
    _pointerDown(event);
  }

  void _pointerDown(PointerDownEvent event) {
    final render = _render;
    if (render == null) {
      return;
    }
    focusNode.requestFocus();
    if (_scrollbarDown(render, event.localPosition)) {
      return;
    }
    final controller = widget.controller;
    final offset = render.offsetForPosition(event.localPosition);
    final quick =
        event.timeStamp - _lastClickAt < const Duration(milliseconds: 400);
    final near = (event.localPosition - _lastClickPosition).distance < 5;
    _clicks = quick && near ? _clicks + 1 : 1;
    _lastClickAt = event.timeStamp;
    _lastClickPosition = event.localPosition;

    // the keys as the editor follows them: alt that was down when the window
    // was left, as with alt tab, is not down any more
    final keyboard = ModifierKeys.instance;
    final add = keyboard.isAltPressed;
    if (_clicks == 1) {
      controller.clickAt(offset, extend: keyboard.isShiftPressed, add: add);
    } else if (_clicks == 2) {
      controller.selectWordAt(offset, add: add);
    } else {
      controller.selectLineAt(offset, add: add);
    }
    _dragging = true;
  }

  // the scrollbars

  /// the scrollbar whose thumb is being dragged
  ScrollbarAxis? _scrollbarDrag;

  /// where the pointer was when it last moved in a drag of a thumb
  Offset _scrollbarPointer = Offset.zero;
  bool _overScrollbar = false;

  /// whether [position] is on a scrollbar, which then takes the press: on the
  /// thumb it starts a drag, and elsewhere on the track it scrolls to put what
  /// is shown around that place
  bool _scrollbarDown(RenderEditor render, Offset position) {
    final hit = render.scrollbarAt(position);
    if (hit == null) {
      return false;
    }
    _showScrollbars();
    final thumb = hit.thumb;
    if (thumb == null) {
      return true;
    }
    if (thumb.contains(position)) {
      _scrollbarDrag = hit.axis;
      _scrollbarPointer = position;
      render.setThumbState(hit.axis, ThumbState.dragging);
      setState(() {});
    } else {
      render.scrollToUnits(hit.axis, hit.clickedPosition(position));
    }
    return true;
  }

  void _dragScrollbar(RenderEditor render, Offset position) {
    final axis = _scrollbarDrag;
    final layout = axis == null ? null : render.scrollbar(axis);
    if (axis == null || layout == null) {
      return;
    }
    final vertical = axis == ScrollbarAxis.vertical;
    final before = vertical ? _scrollbarPointer.dy : _scrollbarPointer.dx;
    final now = vertical ? position.dy : position.dx;
    final start = vertical ? layout.track.top : layout.track.left;
    final end = vertical ? layout.track.bottom : layout.track.right;
    _showScrollbars();
    // a drag only scrolls while it was on the track before it moved
    if (before >= start && before <= end) {
      render.scrollToUnits(axis, layout.draggedPosition(now - before));
    }
    _scrollbarPointer = position;
  }

  void _endScrollbarDrag(Offset position) {
    final render = _render;
    final axis = _scrollbarDrag;
    if (render == null || axis == null) {
      return;
    }
    _scrollbarDrag = null;
    _hoverScrollbars(render, position);
    setState(() {});
  }

  /// the thumb the pointer is on is lit, and the pointer over a scrollbar is an
  /// arrow
  void _hoverScrollbars(RenderEditor render, Offset position) {
    final hit = render.scrollbarAt(position);
    for (final axis in ScrollbarAxis.values) {
      render.setThumbState(
        axis,
        hit != null && hit.axis == axis && hit.thumbHovered(position)
            ? ThumbState.hovered
            : ThumbState.idle,
      );
    }
    final over = hit != null;
    if (over) {
      _showScrollbars();
    }
    if (over != _overScrollbar) {
      setState(() => _overScrollbar = over);
    }
  }

  void _onHover(PointerHoverEvent event) {
    final render = _render;
    if (render != null && _scrollbarDrag == null) {
      _hoverScrollbars(render, event.localPosition);
      _updateHover(event.localPosition, event.position);
    }
  }

  void _onExit(PointerExitEvent event) {
    final render = _render;
    if (render != null && _scrollbarDrag == null) {
      for (final axis in ScrollbarAxis.values) {
        render.setThumbState(axis, ThumbState.idle);
      }
    }
    if (_overScrollbar) {
      setState(() => _overScrollbar = false);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    final render = _render;
    if (_scrollbarDrag != null) {
      if (render != null) {
        _dragScrollbar(render, event.localPosition);
      }
      return;
    }
    if (!_dragging) {
      return;
    }
    if (render == null) {
      return;
    }
    final offset = render.offsetForPosition(event.localPosition);
    final controller = widget.controller;
    if (_clicks <= 1) {
      controller.dragTo(offset);
    } else {
      // a drag after a double or triple click grows by words or lines
      final newest = controller.selections.newest;
      final (start, end) = _clicks == 2
          ? controller.wordRangeAt(offset)
          : _lineRange(controller, offset);
      final anchorStart = newest.start;
      final anchorEnd = newest.end;
      final from = start < anchorStart ? start : anchorStart;
      final to = end > anchorEnd ? end : anchorEnd;
      controller.selections.select([controller.selections.make(from, to)]);
      controller.requestRevealCursor();
    }
  }

  (int, int) _lineRange(EditorController controller, int offset) {
    final text = controller.buffer.text;
    final row = text.rowAt(offset);
    return (text.lineStart(row), text.lineEnd(row) + 1);
  }

  void _onPointerUp(PointerUpEvent event) {
    _dragging = false;
    _endScrollbarDrag(event.localPosition);
  }

  void _onScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final controller = widget.controller;
    var dx = event.scrollDelta.dx;
    var dy = event.scrollDelta.dy;
    final keys = ModifierKeys.instance;
    if (widget.mouseWheelZoom &&
        widget.onZoom != null &&
        (keys.isControlPressed || keys.isMetaPressed)) {
      // the wheel going up is a scroll up, which is a negative amount here
      if (dy != 0) {
        widget.onZoom!(dy < 0 ? 1 : -1);
      }
      return;
    }
    if (ModifierKeys.instance.isShiftPressed && dx == 0) {
      dx = dy;
      dy = 0;
    }
    controller.setScroll(
      x: widget.softWrap ? null : controller.scrollX + dx,
      y: controller.scrollY + dy,
    );
  }

  @override
  void dispose() {
    _blink?.cancel();
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _input.detach();
    widget.controller.scrollbarHeld = null;
    widget.controller.removeListener(_onControllerChange);
    focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  /// the popover, over the place that the diagnostic starts at, or null
  Widget? _popoverLayer() {
    final detail = _popover;
    final render = _render;
    if (detail == null || render == null || !render.hasSize) {
      return null;
    }
    final controller = widget.controller;
    final start = controller.buffer.snapshot.offsetForAnchor(
      detail.range.start,
    );
    var target = render.caretRectForOffset(start);
    // a place that is out of sight is at the nearest row that is in sight
    final top = target.top
        .clamp(0.0, math.max(0.0, render.size.height - render.lineHeight))
        .toDouble();
    target = Rect.fromLTWH(target.left, top, target.width, render.lineHeight);
    return PopoverLayer(
      target: target,
      child: KeyedSubtree(
        key: _popoverKey,
        child: DiagnosticPopover(
          key: ObjectKey(detail),
          detail: detail,
          colors: controller.diagnosticColors,
          style: widget.style,
          contentLimit: popoverContentLimit(
            area: render.size,
            charWidth: render.charWidth,
            lineHeight: render.lineHeight,
          ),
          onPointer: _onPopoverPointer,
          tooltip: widget.tooltip,
          scrollbarShow: widget.scrollbars.show,
          systemAutoHide: EditorController.systemHidesScrollbars,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final popover = _popoverLayer();
    return Stack(
      fit: StackFit.expand,
      children: [
        Focus(
          focusNode: focusNode,
          autofocus: widget.autofocus,
          onKeyEvent: _onKey,
          child: MouseRegion(
            cursor: _overScrollbar || _scrollbarDrag != null
                ? SystemMouseCursors.basic
                : SystemMouseCursors.text,
            onHover: _onHover,
            onExit: _onExit,
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerSignal: _onScroll,
              child: _EditorRenderWidget(
                key: _renderKey,
                controller: widget.controller,
                style: widget.style,
                softWrap: widget.softWrap,
                showLineNumbers: widget.showLineNumbers,
                scrollbars: widget.scrollbars,
              ),
            ),
          ),
        ),
        ?popover,
      ],
    );
  }
}

class _EditorRenderWidget extends LeafRenderObjectWidget {
  const _EditorRenderWidget({
    super.key,
    required this.controller,
    required this.style,
    required this.softWrap,
    required this.showLineNumbers,
    required this.scrollbars,
  });

  final EditorController controller;
  final EditorStyle style;
  final bool softWrap;
  final bool showLineNumbers;
  final ScrollbarSettings scrollbars;

  @override
  RenderEditor createRenderObject(BuildContext context) => RenderEditor(
    controller: controller,
    style: style,
    softWrap: softWrap,
    showLineNumbers: showLineNumbers,
    scrollbars: scrollbars,
  );

  @override
  void updateRenderObject(BuildContext context, RenderEditor renderObject) {
    renderObject
      ..controller = controller
      ..style = style
      ..softWrap = softWrap
      ..showLineNumbers = showLineNumbers
      ..scrollbars = scrollbars;
  }
}
