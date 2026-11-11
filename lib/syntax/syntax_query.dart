import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'lua_pattern.dart';
import 'ts_bindings.dart';

/// a condition of a pattern of a query on the text of what it captured. the
/// library only reports them, so they are checked here
abstract class _Predicate {
  bool test(Map<int, List<String>> captured);
}

class _Equals implements _Predicate {
  _Equals(this.capture, {this.text, this.other, required this.negate});

  final int capture;
  final String? text;
  final int? other;
  final bool negate;

  @override
  bool test(Map<int, List<String>> captured) {
    final mine = captured[capture];
    if (mine == null) {
      return true;
    }
    final String? expected = text;
    final theirs = other == null ? null : captured[other];
    final result = mine.every(
      (value) => expected != null
          ? value == expected
          : theirs == null || theirs.contains(value),
    );
    return result != negate;
  }
}

class _Matches implements _Predicate {
  _Matches(this.capture, this.pattern, {required this.negate});

  final int capture;
  final RegExp? pattern;
  final bool negate;

  @override
  bool test(Map<int, List<String>> captured) {
    final mine = captured[capture];
    if (mine == null) {
      return true;
    }
    final regexp = pattern;
    if (regexp == null) {
      // a pattern that is not understood matches nothing
      return negate;
    }
    return mine.every((value) => regexp.hasMatch(value)) != negate;
  }
}

class _AnyOf implements _Predicate {
  _AnyOf(this.capture, this.values, {required this.negate});

  final int capture;
  final Set<String> values;
  final bool negate;

  @override
  bool test(Map<int, List<String>> captured) {
    final mine = captured[capture];
    if (mine == null) {
      return true;
    }
    return mine.every(values.contains) != negate;
  }
}

/// a compiled query of a grammar, with its predicates
class SyntaxQuery {
  SyntaxQuery._(this.ts, this.pointer, this.captureNames, this._predicates);

  final TreeSitter ts;
  final Pointer<Void> pointer;

  /// the name of each capture, by the index the library gives it
  final List<String> captureNames;
  final List<List<_Predicate>> _predicates;

  /// compiles [source], or returns null with the reason in [error]
  static SyntaxQuery? compile(
    TreeSitter ts,
    String source, {
    void Function(String error)? error,
  }) {
    final bytes = utf8.encode(source);
    final text = malloc<Uint8>(bytes.length);
    final errorOffset = malloc<Uint32>();
    final errorType = malloc<Int32>();
    try {
      text.asTypedList(bytes.length).setAll(0, bytes);
      final query = ts.queryNew(
        ts.luau,
        text,
        bytes.length,
        errorOffset,
        errorType,
      );
      if (query == nullptr) {
        error?.call(
          'error ${errorType.value} at byte ${errorOffset.value} of the query',
        );
        return null;
      }
      final names = <String>[
        for (var i = 0; i < ts.queryCaptureCount(query); i++)
          _string(ts.queryCaptureName, query, i),
      ];
      final predicates = <List<_Predicate>>[
        for (var i = 0; i < ts.queryPatternCount(query); i++)
          _predicatesOf(ts, query, i),
      ];
      return SyntaxQuery._(ts, query, names, predicates);
    } finally {
      malloc.free(text);
      malloc.free(errorOffset);
      malloc.free(errorType);
    }
  }

  static String _string(
    Pointer<Uint8> Function(Pointer<Void>, int, Pointer<Uint32>) lookup,
    Pointer<Void> query,
    int id,
  ) {
    final length = malloc<Uint32>();
    try {
      final text = lookup(query, id, length);
      return utf8.decode(text.asTypedList(length.value));
    } finally {
      malloc.free(length);
    }
  }

  static List<_Predicate> _predicatesOf(
    TreeSitter ts,
    Pointer<Void> query,
    int pattern,
  ) {
    final count = malloc<Uint32>();
    try {
      final steps = ts.queryPredicates(query, pattern, count);
      final result = <_Predicate>[];
      // each predicate is its operator and its arguments, then a done step
      var current = <({bool capture, int id})>[];
      for (var i = 0; i < count.value; i++) {
        final step = steps[i];
        if (step.type == tsPredicateStepDone) {
          final built = _build(ts, query, current);
          if (built != null) {
            result.add(built);
          }
          current = [];
        } else {
          current.add((
            capture: step.type == tsPredicateStepCapture,
            id: step.valueId,
          ));
        }
      }
      return result;
    } finally {
      malloc.free(count);
    }
  }

  static _Predicate? _build(
    TreeSitter ts,
    Pointer<Void> query,
    List<({bool capture, int id})> steps,
  ) {
    if (steps.isEmpty || steps.first.capture) {
      return null;
    }
    final operator = _string(ts.queryStringValue, query, steps.first.id);
    final args = steps.sublist(1);
    String stringOf(({bool capture, int id}) a) =>
        _string(ts.queryStringValue, query, a.id);
    if (args.isEmpty || !args.first.capture) {
      return null;
    }
    final capture = args.first.id;
    switch (operator) {
      case 'eq?':
      case 'not-eq?':
        if (args.length < 2) {
          return null;
        }
        final second = args[1];
        return _Equals(
          capture,
          text: second.capture ? null : stringOf(second),
          other: second.capture ? second.id : null,
          negate: operator == 'not-eq?',
        );
      case 'match?':
      case 'not-match?':
        if (args.length < 2 || args[1].capture) {
          return null;
        }
        RegExp? regexp;
        try {
          regexp = RegExp(stringOf(args[1]));
        } on FormatException {
          regexp = null;
        }
        return _Matches(capture, regexp, negate: operator == 'not-match?');
      case 'lua-match?':
      case 'not-lua-match?':
        if (args.length < 2 || args[1].capture) {
          return null;
        }
        return _Matches(
          capture,
          luaPatternToRegExp(stringOf(args[1])),
          negate: operator == 'not-lua-match?',
        );
      case 'any-of?':
      case 'not-any-of?':
        return _AnyOf(capture, {
          for (final a in args.skip(1))
            if (!a.capture) stringOf(a),
        }, negate: operator == 'not-any-of?');
    }
    // the others, such as set!, do not decide what matches
    return null;
  }

  /// whether the match of [pattern] holds, given the text of each capture
  bool holds(int pattern, Map<int, List<String>> captured) {
    for (final predicate in _predicates[pattern]) {
      if (!predicate.test(captured)) {
        return false;
      }
    }
    return true;
  }

  /// whether the pattern has predicates, which need the text of the captures
  bool needsText(int pattern) => _predicates[pattern].isNotEmpty;

  void dispose() => ts.queryDelete(pointer);
}
