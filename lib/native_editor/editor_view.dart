import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

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
    this.scrollbars = ScrollbarVisibility.always,
    this.focusNode,
    this.autofocus = false,
    this.readOnly = false,
    this.onFocusChanged,
  });

  /// told when the editor gains or loses the focus
  final void Function(bool focused)? onFocusChanged;

  final EditorController controller;
  final EditorStyle style;
  final bool softWrap;
  final bool showLineNumbers;

  /// when the text has scrollbars
  final ScrollbarVisibility scrollbars;
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

  RenderEditor? get _render =>
      _renderKey.currentContext?.findRenderObject() as RenderEditor?;

  @override
  void initState() {
    super.initState();
    _input = EditorTextInput(widget.controller);
    ModifierKeys.instance.start();
    focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onControllerChange);
    _scrollX = widget.controller.scrollX;
    _scrollY = widget.controller.scrollY;
  }

  // the scrollbars are shown for a moment when the text scrolls, or the pointer
  // is at one of them

  static const _scrollbarsShownFor = Duration(seconds: 1);
  Timer? _hideScrollbars;
  double _scrollX = 0;
  double _scrollY = 0;

  void _showScrollbars() {
    if (widget.scrollbars != ScrollbarVisibility.auto) {
      return;
    }
    _render?.scrollbarsShown = true;
    _hideScrollbars?.cancel();
    _hideScrollbars = Timer(_scrollbarsShownFor, () {
      // not while a thumb is being dragged
      if (_scrollbarDrag != null) {
        _showScrollbars();
      } else {
        _render?.scrollbarsShown = false;
      }
    });
  }

  @override
  void didUpdateWidget(EditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollbars != widget.scrollbars) {
      _hideScrollbars?.cancel();
      _render?.scrollbarsShown = true;
    }
    final oldNode = oldWidget.focusNode ?? oldWidget.controller.focusNode;
    if (oldNode != focusNode) {
      oldNode.removeListener(_onFocusChange);
      focusNode.addListener(_onFocusChange);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChange);
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
    if (controller.scrollX != _scrollX || controller.scrollY != _scrollY) {
      _scrollX = controller.scrollX;
      _scrollY = controller.scrollY;
      _showScrollbars();
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
    _hideScrollbars?.cancel();
    _input.detach();
    widget.controller.removeListener(_onControllerChange);
    focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
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
  final ScrollbarVisibility scrollbars;

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
