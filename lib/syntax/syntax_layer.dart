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
    void Function(String error)? error,
  }) {
    final tree = SyntaxTree.create(buffer.text, queryText, error: error);
    return tree == null ? null : SyntaxLayer._(buffer, tree, theme);
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

  void dispose() {
    _buffer.removeListener(_onChange);
    _buffer.unsubscribe(_subscription);
    _tree.dispose();
  }
}
