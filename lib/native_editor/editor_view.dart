import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'editor_controller.dart';
import 'editor_keys.dart';
import 'editor_style.dart';
import 'editor_text_input.dart';
import 'input_debug.dart';
import 'render_editor.dart';

/// shows the text of an [EditorController], and takes what is typed, clicked
/// and dragged on it
class EditorView extends StatefulWidget {
  const EditorView({
    super.key,
    required this.controller,
    this.style = const EditorStyle(),
    this.softWrap = true,
    this.showLineNumbers = true,
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
    focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onControllerChange);
  }

  @override
  void didUpdateWidget(EditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    if (event is! KeyUpEvent) {
      inputLog(
        'key ${event.runtimeType} ${event.logicalKey.debugName} '
        'character ${event.character == null ? 'none' : 'length ${event.character!.length}'} '
        'input attached ${_input.attached}',
      );
    }
    if (widget.readOnly) {
      final keyboard = HardwareKeyboard.instance;
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
    final render = _render;
    if (render == null) {
      return;
    }
    focusNode.requestFocus();
    final controller = widget.controller;
    final offset = render.offsetForPosition(event.localPosition);
    final quick =
        event.timeStamp - _lastClickAt < const Duration(milliseconds: 400);
    final near = (event.localPosition - _lastClickPosition).distance < 5;
    _clicks = quick && near ? _clicks + 1 : 1;
    _lastClickAt = event.timeStamp;
    _lastClickPosition = event.localPosition;

    final keyboard = HardwareKeyboard.instance;
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

  void _onPointerMove(PointerMoveEvent event) {
    if (!_dragging) {
      return;
    }
    final render = _render;
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

  void _onPointerUp(PointerUpEvent event) => _dragging = false;

  void _onScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final controller = widget.controller;
    var dx = event.scrollDelta.dx;
    var dy = event.scrollDelta.dy;
    if (HardwareKeyboard.instance.isShiftPressed && dx == 0) {
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
        cursor: SystemMouseCursors.text,
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
  });

  final EditorController controller;
  final EditorStyle style;
  final bool softWrap;
  final bool showLineNumbers;

  @override
  RenderEditor createRenderObject(BuildContext context) => RenderEditor(
    controller: controller,
    style: style,
    softWrap: softWrap,
    showLineNumbers: showLineNumbers,
  );

  @override
  void updateRenderObject(BuildContext context, RenderEditor renderObject) {
    renderObject
      ..controller = controller
      ..style = style
      ..softWrap = softWrap
      ..showLineNumbers = showLineNumbers;
  }
}
