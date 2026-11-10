import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;

import 'editor_controller.dart';

/// does what the key [event] asks of the editor, if it is one the editor has
/// a use for; text that is typed is not handled here, as it comes from the
/// input method
KeyEventResult handleEditorKey(EditorController controller, KeyEvent event) {
  if (event is KeyUpEvent) {
    return KeyEventResult.ignored;
  }
  final keyboard = HardwareKeyboard.instance;
  final handled = _handle(
    controller,
    event.logicalKey,
    shift: keyboard.isShiftPressed,
    command: keyboard.isControlPressed || keyboard.isMetaPressed,
    alt: keyboard.isAltPressed,
  );
  if (!handled) {
    // a key that makes a character types it. compositions of an input method
    // come without one, and still go through the input method
    final character = event.character;
    if (character != null &&
        _isPrintable(character) &&
        !keyboard.isMetaPressed &&
        keyboard.isControlPressed == keyboard.isAltPressed) {
      controller.replaceSelections(character);
      controller.setCursorVisible(true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
  controller.setCursorVisible(true);
  return KeyEventResult.handled;
}

bool _isPrintable(String text) {
  for (final unit in text.codeUnits) {
    if (unit < 0x20 || unit == 0x7f) {
      return false;
    }
  }
  return text.isNotEmpty;
}

bool _handle(
  EditorController controller,
  LogicalKeyboardKey key, {
  required bool shift,
  required bool command,
  required bool alt,
}) {
  final byWord = command || alt;
  if (key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight) {
    final forward = key == LogicalKeyboardKey.arrowRight;
    byWord
        ? controller.moveByWord(forward: forward, extend: shift)
        : controller.moveHorizontally(forward: forward, extend: shift);
  } else if (key == LogicalKeyboardKey.arrowUp) {
    controller.moveVertically(down: false, extend: shift);
  } else if (key == LogicalKeyboardKey.arrowDown) {
    controller.moveVertically(down: true, extend: shift);
  } else if (key == LogicalKeyboardKey.home) {
    command
        ? controller.moveToDocumentEdge(toEnd: false, extend: shift)
        : controller.moveToRowEdge(toEnd: false, extend: shift);
  } else if (key == LogicalKeyboardKey.end) {
    command
        ? controller.moveToDocumentEdge(toEnd: true, extend: shift)
        : controller.moveToRowEdge(toEnd: true, extend: shift);
  } else if (key == LogicalKeyboardKey.pageUp) {
    controller.moveByRows(-controller.viewportRows, extend: shift);
  } else if (key == LogicalKeyboardKey.pageDown) {
    controller.moveByRows(controller.viewportRows, extend: shift);
  } else if (key == LogicalKeyboardKey.backspace) {
    command ? controller.deleteWord(forward: false) : controller.backspace();
  } else if (key == LogicalKeyboardKey.delete) {
    command ? controller.deleteWord(forward: true) : controller.deleteForward();
  } else if (key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter) {
    controller.insertNewline();
  } else if (key == LogicalKeyboardKey.tab) {
    shift ? controller.indentLines(outdent: true) : controller.insertTab();
  } else if (key == LogicalKeyboardKey.escape) {
    final newest = controller.selections.newest;
    controller.selections.selectRanges([(newest.head, newest.head)]);
    controller.requestRevealCursor();
  } else if (command && key == LogicalKeyboardKey.keyA) {
    controller.selectAll();
  } else if (command && key == LogicalKeyboardKey.keyZ) {
    shift ? controller.redo() : controller.undo();
  } else if (command && key == LogicalKeyboardKey.keyY) {
    controller.redo();
  } else if (command && key == LogicalKeyboardKey.keyC) {
    controller.copy();
  } else if (command && key == LogicalKeyboardKey.keyX) {
    controller.cut();
  } else if (command && key == LogicalKeyboardKey.keyV) {
    controller.paste();
  } else {
    return false;
  }
  return true;
}
