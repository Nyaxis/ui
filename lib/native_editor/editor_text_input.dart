import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../editor_core/buffer.dart' show Replacement;
import 'editor_controller.dart';

/// connects an [EditorController] to the input method of the system, which
/// is how text is typed, and how text of other scripts is composed.
///
/// the input method is told of the line the newest cursor is on, as a text
/// of its own, and says what to change in it; it is not told of the whole
/// text, which can be long.
class EditorTextInput implements DeltaTextInputClient {
  EditorTextInput(this.controller);

  final EditorController controller;
  TextInputConnection? _connection;

  /// where in the text the line that the input method is told of starts
  int _windowStart = 0;
  String _windowText = '';

  /// the range that is being composed, in the offsets of the text
  (int, int)? _composing;
  TextEditingValue? _sent;
  bool _applying = false;

  bool get attached => _connection?.attached ?? false;

  void attach() {
    if (attached) {
      return;
    }
    _connection = TextInput.attach(
      this,
      const TextInputConfiguration(
        inputType: TextInputType.multiline,
        inputAction: TextInputAction.newline,
        enableDeltaModel: true,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
      ),
    );
    _connection!.show();
    _sent = null;
    sync();
  }

  void detach() {
    _connection?.close();
    _connection = null;
    _composing = null;
    _sent = null;
  }

  /// tells the input method of what the controller has now, unless it is
  /// the reason for the change
  void sync() {
    final connection = _connection;
    if (connection == null || !connection.attached || _applying) {
      return;
    }
    final value = currentTextEditingValue;
    if (value != _sent) {
      _sent = value;
      connection.setEditingState(value);
    }
  }

  /// tells the input method where the cursor is on the screen, so that its
  /// window is put next to it
  void updateGeometry({
    required Size size,
    required Matrix4 transform,
    required Rect caret,
  }) {
    final connection = _connection;
    if (connection == null || !connection.attached) {
      return;
    }
    connection
      ..setEditableSizeAndTransform(size, transform)
      ..setCaretRect(caret)
      ..setComposingRect(caret);
  }

  // the text of the input method

  @override
  TextEditingValue get currentTextEditingValue {
    final selections = controller.selections;
    final newest = selections.newest;
    final text = controller.buffer.text;
    final row = text.rowAt(newest.head);
    _windowStart = text.lineStart(row);
    _windowText = text.lineText(row);
    int local(int offset) =>
        (offset - _windowStart).clamp(0, _windowText.length);
    final composing = _composing;
    return TextEditingValue(
      text: _windowText,
      selection: TextSelection(
        baseOffset: local(newest.tail),
        extentOffset: local(newest.head),
      ),
      composing: composing == null
          ? TextRange.empty
          : TextRange(start: local(composing.$1), end: local(composing.$2)),
    );
  }

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    // some platforms do not send deltas, and send the whole value of the line
    // instead; what changed in it is found by comparing it with what the
    // input method was told
    final old = _sent ?? currentTextEditingValue;
    updateEditingValueWithDeltas(_deltasBetween(old, value));
  }

  List<TextEditingDelta> _deltasBetween(
    TextEditingValue old,
    TextEditingValue now,
  ) {
    final before = old.text;
    final after = now.text;
    var start = 0;
    final shortest = math.min(before.length, after.length);
    while (start < shortest &&
        before.codeUnitAt(start) == after.codeUnitAt(start)) {
      start++;
    }
    var endBefore = before.length;
    var endAfter = after.length;
    while (endBefore > start &&
        endAfter > start &&
        before.codeUnitAt(endBefore - 1) == after.codeUnitAt(endAfter - 1)) {
      endBefore--;
      endAfter--;
    }
    if (start == endBefore && start == endAfter) {
      return [
        TextEditingDeltaNonTextUpdate(
          oldText: before,
          selection: now.selection,
          composing: now.composing,
        ),
      ];
    }
    return [
      TextEditingDelta.fromJSON({
        'oldText': before,
        'deltaText': after.substring(start, endAfter),
        'deltaStart': start,
        'deltaEnd': endBefore,
        'selectionBase': now.selection.baseOffset,
        'selectionExtent': now.selection.extentOffset,
        'selectionAffinity': 'TextAffinity.downstream',
        'selectionIsDirectional': false,
        'composingBase': now.composing.start,
        'composingExtent': now.composing.end,
      }),
    ];
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> deltas) {
    _applying = true;
    try {
      for (final delta in deltas) {
        _apply(delta);
      }
    } finally {
      _applying = false;
    }
    sync();
    controller.requestRevealCursor();
  }

  int _abs(int local) => _windowStart + local;

  void _apply(TextEditingDelta delta) {
    switch (delta) {
      case TextEditingDeltaInsertion():
        _edit(
          _abs(delta.insertionOffset),
          _abs(delta.insertionOffset),
          delta.textInserted,
          delta,
        );
      case TextEditingDeltaDeletion():
        _edit(
          _abs(delta.deletedRange.start),
          _abs(delta.deletedRange.end),
          '',
          delta,
        );
      case TextEditingDeltaReplacement():
        _edit(
          _abs(delta.replacedRange.start),
          _abs(delta.replacedRange.end),
          delta.replacementText,
          delta,
        );
      case TextEditingDeltaNonTextUpdate():
        _setSelection(delta);
    }
    final composing = delta.composing;
    _composing = composing.isValid && !composing.isCollapsed
        ? (_abs(composing.start), _abs(composing.end))
        : null;
  }

  /// makes the change a delta says to the text. text that is typed with
  /// several cursors goes in at each of them; a composition is only in the
  /// place of the newest.
  void _edit(int start, int end, String text, TextEditingDelta delta) {
    final composing = delta.composing;
    final isComposing = composing.isValid && !composing.isCollapsed;
    final multiple = controller.selections.length > 1;
    final newest = controller.selections.newest;
    final atCursor = start == end && start == newest.head && newest.isEmpty;
    final replacesSelection = start == newest.start && end == newest.end;
    if (!isComposing &&
        _composing == null &&
        multiple &&
        (atCursor || replacesSelection)) {
      if (text == '\n') {
        controller.insertNewline();
      } else if (text.isEmpty) {
        controller.backspace();
      } else {
        controller.replaceSelections(text);
      }
      return;
    }
    if (!isComposing && _composing == null && text == '\n' && atCursor) {
      controller.insertNewline();
      return;
    }
    controller.buffer.beginTransaction(controller.selections.anchors);
    controller.buffer.edit([Replacement(start, end, text)]);
    final cursor = start + text.length;
    final others = controller.selections.all.where((s) => s.id != newest.id);
    controller.selections.select([
      ...others,
      controller.selections.make(cursor, cursor),
    ]);
    controller.buffer.endTransaction(controller.selections.anchors);
    _setSelection(delta, cursorAfterEdit: cursor);
  }

  void _setSelection(TextEditingDelta delta, {int? cursorAfterEdit}) {
    final selection = delta.selection;
    if (!selection.isValid) {
      return;
    }
    final length = controller.buffer.length;
    final base = math.min(_abs(selection.baseOffset), length);
    final extent = math.min(_abs(selection.extentOffset), length);
    final newest = controller.selections.newest;
    final others = controller.selections.all.where((s) => s.id != newest.id);
    controller.selections.select([
      ...others,
      controller.selections.make(base, extent),
    ]);
  }

  @override
  void performAction(TextInputAction action) {
    if (action == TextInputAction.newline) {
      controller.insertNewline();
    }
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void insertContent(KeyboardInsertedContent content) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void showToolbar() {}

  @override
  void connectionClosed() {
    _connection = null;
    _composing = null;
    _sent = null;
  }

  @override
  void didChangeInputControl(
    TextInputControl? oldControl,
    TextInputControl? newControl,
  ) {}

  @override
  void performSelector(String selectorName) {}

  @override
  void insertTextPlaceholder(Size size) {}

  @override
  void removeTextPlaceholder() {}

  @override
  bool onFocusReceived() => false;
}
