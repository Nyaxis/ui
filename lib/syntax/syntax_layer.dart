import '../editor_core/buffer.dart';
import '../editor_core/highlight.dart';
import '../editor_core/rope.dart';
import 'syntax_tree.dart';

/// the syntax of a buffer, which is kept up to date as the buffer is edited,
/// and says how the parts of its text are drawn
class SyntaxLayer implements SyntaxHighlights {
  SyntaxLayer._(this._buffer, this._tree, this.theme)
    : _subscription = _buffer.subscribe(),
      _last = _buffer.text {
    _buffer.addListener(_onChange);
  }

  final TextBuffer _buffer;
  final SyntaxTree _tree;
  final Subscription _subscription;
  Rope _last;

  /// how names are drawn, which is another when the palette changes
  SyntaxTheme theme;

  /// the layer for [buffer], or null when the parser is not available
  static SyntaxLayer? attach(
    TextBuffer buffer,
    SyntaxTheme theme,
    String queryText, {
    String? bracketsText,
    void Function(String error)? error,
  }) {
    final tree = SyntaxTree.create(
      buffer.text,
      queryText,
      bracketsText: bracketsText,
      error: error,
    );
    return tree == null ? null : SyntaxLayer._(buffer, tree, theme);
  }

  /// whether the layer is of the text of [buffer] now, which it is not for a
  /// moment after an edit, before it has been told of it
  bool isOf(BufferSnapshot buffer) => identical(buffer.text, _tree.text);

  /// the ends of the smallest pair that has the text from [head] to [tail] in
  /// it or at its edges, which is none when the layer is not of the text of
  /// [buffer] now
  ({int openStart, int openEnd, int closeStart, int closeEnd})?
  enclosingBrackets(BufferSnapshot buffer, int head, int tail) {
    if (!identical(buffer.text, _tree.text)) {
      return null;
    }
    return _tree.enclosingBrackets(head, tail);
  }

  void _onChange(BufferChange _) {
    final patch = _subscription.consume();
    final text = _buffer.text;
    if (identical(text, _last)) {
      return;
    }
    _tree.update(_last, text, patch);
    _last = text;
  }

  @override
  List<SyntaxSpan> spans(BufferSnapshot buffer, int start, int end) {
    // a snapshot of other text than the tree is of is drawn plain for now
    if (!identical(buffer.text, _tree.text)) {
      return const [];
    }
    return _tree.spans(start, end, theme);
  }

  /// whether [offset] is in a comment or a string, which it is not when the
  /// layer is not of the text of [buffer] now
  ({bool comment, bool string}) scopeAt(BufferSnapshot buffer, int offset) {
    if (!identical(buffer.text, _tree.text)) {
      return (comment: false, string: false);
    }
    return _tree.scopeAt(offset);
  }

  void dispose() {
    _buffer.removeListener(_onChange);
    _buffer.unsubscribe(_subscription);
    _tree.dispose();
  }
}
