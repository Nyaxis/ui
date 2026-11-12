import '../editor_core/highlight.dart';
import '../editor_core/rope.dart';
import 'syntax_tree.dart';

/// the colors of a piece of code that is not in a buffer, such as the code in
/// what a language server says of a symbol: it is read with the query and the
/// theme that the buffers are, and what it found is kept for the next time
class CodeHighlighter {
  CodeHighlighter(this.queryText, this.theme);

  final String queryText;
  final SyntaxTheme theme;

  /// how many pieces of code are kept
  static const int cacheSize = 32;

  final Map<String, List<SyntaxSpan>> _cache = {};

  /// whether [language], which a fence of markdown names, is one that is read
  static bool reads(String? language) =>
      language == 'luau' || language == 'lua';

  /// the spans of [code], in order, or none when it cannot be read
  List<SyntaxSpan> spans(String code) {
    final kept = _cache.remove(code);
    if (kept != null) {
      // it is the newest of them now
      _cache[code] = kept;
      return kept;
    }
    final tree = SyntaxTree.create(Rope(code), queryText);
    final found = tree == null
        ? const <SyntaxSpan>[]
        : List<SyntaxSpan>.unmodifiable(tree.spans(0, code.length, theme));
    tree?.dispose();
    _cache[code] = found;
    if (_cache.length > cacheSize) {
      _cache.remove(_cache.keys.first);
    }
    return found;
  }
}
