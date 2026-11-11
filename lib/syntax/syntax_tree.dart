import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../editor_core/edit_patch.dart';
import '../editor_core/highlight.dart';
import '../editor_core/rope.dart';
import 'syntax_query.dart';
import 'ts_bindings.dart';

/// how the names that a query gives what it captures are drawn. a name that
/// the theme does not have is drawn as the longest start of it that it does,
/// split at the dots: `function.method.call` is drawn as `function.method`,
/// then as `function`, and not at all when there is none
class SyntaxTheme {
  SyntaxTheme(this.styles);

  final Map<String, HighlightStyle> styles;
  final Map<String, HighlightStyle?> _cache = {};

  HighlightStyle? styleFor(String name) {
    if (_cache.containsKey(name)) {
      return _cache[name];
    }
    var key = name;
    HighlightStyle? found;
    while (true) {
      found = styles[key];
      if (found != null) {
        break;
      }
      final dot = key.lastIndexOf('.');
      if (dot < 0) {
        break;
      }
      key = key.substring(0, dot);
    }
    return _cache[name] = found;
  }
}

class _Capture {
  _Capture(this.start, this.end, this.pattern, this.style);

  final int start;
  final int end;
  final int pattern;
  final HighlightStyle style;
}

/// the syntax tree of a text, kept up to date as the text changes, and what
/// its query says of the parts of it
class SyntaxTree {
  SyntaxTree._(this._ts, this._parser, this.query);

  final TreeSitter _ts;
  final Pointer<Void> _parser;
  final SyntaxQuery query;
  Pointer<Void> _tree = nullptr;
  Rope _text = Rope.empty;

  /// the text the tree is of
  Rope get text => _text;

  /// the tree of [text] with [queryText] as its highlight query, or null when
  /// the parser library is not there or the query does not compile
  static SyntaxTree? create(
    Rope text,
    String queryText, {
    void Function(String error)? error,
  }) {
    final ts = TreeSitter.instance;
    if (ts == null) {
      error?.call('the parser library is not there');
      return null;
    }
    final query = SyntaxQuery.compile(ts, queryText, error: error);
    if (query == null) {
      return null;
    }
    final parser = ts.parserNew();
    if (!ts.parserSetLanguage(parser, ts.luau)) {
      ts.parserDelete(parser);
      query.dispose();
      error?.call('the language does not fit the parser library');
      return null;
    }
    final tree = SyntaxTree._(ts, parser, query);
    tree._parse(text);
    return tree;
  }

  /// makes the tree the one of [text], which is [old] after the edits of
  /// [patch]
  void update(Rope old, Rope text, EditPatch patch) {
    if (_tree != nullptr) {
      final edit = malloc<TSInputEdit>();
      try {
        // from the last edit to the first, so that the places of the ones
        // before it stay the places they are in the old text
        for (final e in patch.edits.reversed) {
          final start = _point(old, e.oldStart);
          final oldEnd = _point(old, e.oldEnd);
          final newEnd = _advance(start, text.substring(e.newStart, e.newEnd));
          edit.ref
            ..startByte = e.oldStart * 2
            ..oldEndByte = e.oldEnd * 2
            ..newEndByte = (e.oldStart + (e.newEnd - e.newStart)) * 2;
          edit.ref.startPoint
            ..row = start.$1
            ..column = start.$2;
          edit.ref.oldEndPoint
            ..row = oldEnd.$1
            ..column = oldEnd.$2;
          edit.ref.newEndPoint
            ..row = newEnd.$1
            ..column = newEnd.$2;
          _ts.treeEdit(_tree, edit);
        }
      } finally {
        malloc.free(edit);
      }
    }
    _parse(text);
  }

  /// the row and the column in bytes of an offset
  (int, int) _point(Rope text, int offset) {
    final row = text.rowAt(offset);
    return (row, (offset - text.lineStart(row)) * 2);
  }

  /// where the end of [inserted] is, when it starts at [from]
  (int, int) _advance((int, int) from, String inserted) {
    var rows = 0;
    var lastBreak = -1;
    for (var i = 0; i < inserted.length; i++) {
      if (inserted.codeUnitAt(i) == 0x0a) {
        rows++;
        lastBreak = i;
      }
    }
    if (rows == 0) {
      return (from.$1, from.$2 + inserted.length * 2);
    }
    return (from.$1 + rows, (inserted.length - lastBreak - 1) * 2);
  }

  void _parse(Rope text) {
    final string = text.toString();
    final units = malloc<Uint16>(string.isEmpty ? 1 : string.length);
    try {
      final list = units.asTypedList(string.length);
      for (var i = 0; i < string.length; i++) {
        list[i] = string.codeUnitAt(i);
      }
      final tree = _ts.parse(
        _parser,
        _tree,
        units.cast<Uint8>(),
        string.length * 2,
        tsInputEncodingUtf16Le,
      );
      if (_tree != nullptr) {
        _ts.treeDelete(_tree);
      }
      _tree = tree;
      _text = text;
    } finally {
      malloc.free(units);
    }
  }

  static final SyntaxTheme _scopeTheme = SyntaxTheme({
    'comment': const HighlightStyle(color: 1),
    'string': const HighlightStyle(color: 2),
  });

  /// whether the place between the characters before and after [offset] is in
  /// a comment, or in a string, which is not so at the end of one
  ({bool comment, bool string}) scopeAt(int offset) {
    final length = _text.length;
    int kindOf(int from, int to) {
      if (from < 0 || to > length) {
        return 0;
      }
      final found = spans(from, to, _scopeTheme);
      return found.length == 1 &&
              found.first.start <= from &&
              found.first.end >= to
          ? found.first.style.color!
          : 0;
    }

    final before = kindOf(offset - 1, offset);
    final after = kindOf(offset, offset + 1);
    return (
      // a comment goes on to the end of its line
      comment:
          before == 1 &&
          (after == 1 || offset == length || _text.codeUnitAt(offset) == 0x0a),
      string: before == 2 && after == 2,
    );
  }

  /// whether the text has a part that does not follow the grammar
  bool get hasErrors => _ts.nodeHasError(_ts.treeRootNode(_tree));

  /// the parts of the text from [start] to [end] that [theme] draws, in
  /// order, each part with one style. where what is captured is nested, the
  /// inner one is drawn, and of those that cover the same text the one that
  /// is later in the query
  List<SyntaxSpan> spans(int start, int end, SyntaxTheme theme) {
    if (_tree == nullptr || start >= end) {
      return const [];
    }
    final captures = <_Capture>[];
    final cursor = _ts.cursorNew();
    final match = malloc<TSQueryMatch>();
    try {
      _ts.cursorSetByteRange(cursor, start * 2, end * 2);
      _ts.cursorExec(cursor, query.pointer, _ts.treeRootNode(_tree));
      while (_ts.cursorNextMatch(cursor, match)) {
        final pattern = match.ref.patternIndex;
        final count = match.ref.captureCount;
        final found = match.ref.captures;
        if (query.needsText(pattern)) {
          final texts = <int, List<String>>{};
          for (var i = 0; i < count; i++) {
            final c = found[i];
            texts
                .putIfAbsent(c.index, () => [])
                .add(
                  _text.substring(
                    _ts.nodeStartByte(c.node) ~/ 2,
                    _ts.nodeEndByte(c.node) ~/ 2,
                  ),
                );
          }
          if (!query.holds(pattern, texts)) {
            continue;
          }
        }
        for (var i = 0; i < count; i++) {
          final c = found[i];
          final style = theme.styleFor(query.captureNames[c.index]);
          if (style == null) {
            continue;
          }
          final from = _ts.nodeStartByte(c.node) ~/ 2;
          final to = _ts.nodeEndByte(c.node) ~/ 2;
          if (to > start && from < end && to > from) {
            captures.add(_Capture(from, to, pattern, style));
          }
        }
      }
    } finally {
      malloc.free(match);
      _ts.cursorDelete(cursor);
    }
    return _resolve(captures, start, end);
  }

  List<SyntaxSpan> _resolve(List<_Capture> captures, int start, int end) {
    if (captures.isEmpty) {
      return const [];
    }
    captures.sort(
      (a, b) => a.start != b.start ? a.start - b.start : b.end - a.end,
    );
    final points = <int>{start, end};
    for (final c in captures) {
      points.add(c.start < start ? start : c.start);
      points.add(c.end > end ? end : c.end);
    }
    final sorted = points.toList()..sort();
    final result = <SyntaxSpan>[];
    final active = <_Capture>[];
    var next = 0;
    for (var i = 0; i + 1 < sorted.length; i++) {
      final from = sorted[i];
      final to = sorted[i + 1];
      while (next < captures.length && captures[next].start <= from) {
        active.add(captures[next++]);
      }
      active.removeWhere((c) => c.end <= from);
      _Capture? best;
      for (final c in active) {
        if (best == null) {
          best = c;
          continue;
        }
        final length = c.end - c.start;
        final bestLength = best.end - best.start;
        if (length < bestLength ||
            (length == bestLength && c.pattern > best.pattern)) {
          best = c;
        }
      }
      if (best == null) {
        continue;
      }
      if (result.isNotEmpty &&
          result.last.end == from &&
          result.last.style == best.style) {
        final last = result.removeLast();
        result.add(SyntaxSpan(last.start, to, best.style));
      } else {
        result.add(SyntaxSpan(from, to, best.style));
      }
    }
    return result;
  }

  void dispose() {
    if (_tree != nullptr) {
      _ts.treeDelete(_tree);
      _tree = nullptr;
    }
    _ts.parserDelete(_parser);
    query.dispose();
  }
}
