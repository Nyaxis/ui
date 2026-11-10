// ignore_for_file: library_private_types_in_public_api

import 'dart:ffi';
import 'dart:io';

/// the parts of the tree-sitter C interface that the editor uses, as they are
/// in `api.h`. offsets are in bytes of the text that was parsed, which is
/// UTF-16, so two for each code unit.

final class TSPoint extends Struct {
  @Uint32()
  external int row;
  @Uint32()
  external int column;
}

final class TSNode extends Struct {
  @Array(4)
  external Array<Uint32> context;
  external Pointer<Void> id;
  external Pointer<Void> tree;
}

final class TSInputEdit extends Struct {
  @Uint32()
  external int startByte;
  @Uint32()
  external int oldEndByte;
  @Uint32()
  external int newEndByte;
  external TSPoint startPoint;
  external TSPoint oldEndPoint;
  external TSPoint newEndPoint;
}

final class TSQueryCapture extends Struct {
  external TSNode node;
  @Uint32()
  external int index;
}

final class TSQueryMatch extends Struct {
  @Uint32()
  external int id;
  @Uint16()
  external int patternIndex;
  @Uint16()
  external int captureCount;
  external Pointer<TSQueryCapture> captures;
}

final class TSQueryPredicateStep extends Struct {
  @Uint32()
  external int type;
  @Uint32()
  external int valueId;
}

const int tsInputEncodingUtf16Le = 1;
const int tsPredicateStepDone = 0;
const int tsPredicateStepCapture = 1;

typedef _New = Pointer<Void> Function();
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _Free = void Function(Pointer<Void>);
typedef _SetLanguageNative = Bool Function(Pointer<Void>, Pointer<Void>);
typedef _SetLanguage = bool Function(Pointer<Void>, Pointer<Void>);
typedef _ParseNative = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Uint8>,
  Uint32,
  Int32,
);
typedef _Parse = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Uint8>,
  int,
  int,
);
typedef _TreeEditNative = Void Function(Pointer<Void>, Pointer<TSInputEdit>);
typedef _TreeEdit = void Function(Pointer<Void>, Pointer<TSInputEdit>);
typedef _RootNode = TSNode Function(Pointer<Void>);
typedef _NodeBoolNative = Bool Function(TSNode);
typedef _NodeBool = bool Function(TSNode);
typedef _NodeByteNative = Uint32 Function(TSNode);
typedef _NodeByte = int Function(TSNode);
typedef _QueryNewNative = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Uint8>,
  Uint32,
  Pointer<Uint32>,
  Pointer<Int32>,
);
typedef _QueryNew = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Uint8>,
  int,
  Pointer<Uint32>,
  Pointer<Int32>,
);
typedef _CountNative = Uint32 Function(Pointer<Void>);
typedef _Count = int Function(Pointer<Void>);
typedef _QueryNameNative = Pointer<Uint8> Function(
  Pointer<Void>,
  Uint32,
  Pointer<Uint32>,
);
typedef _QueryName = Pointer<Uint8> Function(
  Pointer<Void>,
  int,
  Pointer<Uint32>,
);
typedef _QueryPredicatesNative = Pointer<TSQueryPredicateStep> Function(
  Pointer<Void>,
  Uint32,
  Pointer<Uint32>,
);
typedef _QueryPredicates = Pointer<TSQueryPredicateStep> Function(
  Pointer<Void>,
  int,
  Pointer<Uint32>,
);
typedef _CursorExecNative = Void Function(Pointer<Void>, Pointer<Void>, TSNode);
typedef _CursorExec = void Function(Pointer<Void>, Pointer<Void>, TSNode);
typedef _CursorRangeNative = Bool Function(Pointer<Void>, Uint32, Uint32);
typedef _CursorRange = bool Function(Pointer<Void>, int, int);
typedef _NextMatchNative = Bool Function(Pointer<Void>, Pointer<TSQueryMatch>);
typedef _NextMatch = bool Function(Pointer<Void>, Pointer<TSQueryMatch>);

/// the library with the parser and the grammar of Luau
class TreeSitter {
  TreeSitter._(DynamicLibrary lib)
    : parserNew = lib.lookupFunction<_New, _New>('ts_parser_new'),
      parserDelete = lib.lookupFunction<_FreeNative, _Free>('ts_parser_delete'),
      parserSetLanguage = lib.lookupFunction<_SetLanguageNative, _SetLanguage>(
        'ts_parser_set_language',
      ),
      parse = lib.lookupFunction<_ParseNative, _Parse>(
        'ts_parser_parse_string_encoding',
      ),
      treeDelete = lib.lookupFunction<_FreeNative, _Free>('ts_tree_delete'),
      treeEdit = lib.lookupFunction<_TreeEditNative, _TreeEdit>('ts_tree_edit'),
      treeRootNode = lib.lookupFunction<_RootNode, _RootNode>(
        'ts_tree_root_node',
      ),
      nodeHasError = lib.lookupFunction<_NodeBoolNative, _NodeBool>(
        'ts_node_has_error',
      ),
      nodeStartByte = lib.lookupFunction<_NodeByteNative, _NodeByte>(
        'ts_node_start_byte',
      ),
      nodeEndByte = lib.lookupFunction<_NodeByteNative, _NodeByte>(
        'ts_node_end_byte',
      ),
      queryNew = lib.lookupFunction<_QueryNewNative, _QueryNew>('ts_query_new'),
      queryDelete = lib.lookupFunction<_FreeNative, _Free>('ts_query_delete'),
      queryCaptureCount = lib.lookupFunction<_CountNative, _Count>(
        'ts_query_capture_count',
      ),
      queryPatternCount = lib.lookupFunction<_CountNative, _Count>(
        'ts_query_pattern_count',
      ),
      queryCaptureName = lib.lookupFunction<_QueryNameNative, _QueryName>(
        'ts_query_capture_name_for_id',
      ),
      queryStringValue = lib.lookupFunction<_QueryNameNative, _QueryName>(
        'ts_query_string_value_for_id',
      ),
      queryPredicates = lib
          .lookupFunction<_QueryPredicatesNative, _QueryPredicates>(
            'ts_query_predicates_for_pattern',
          ),
      cursorNew = lib.lookupFunction<_New, _New>('ts_query_cursor_new'),
      cursorDelete = lib.lookupFunction<_FreeNative, _Free>(
        'ts_query_cursor_delete',
      ),
      cursorExec = lib.lookupFunction<_CursorExecNative, _CursorExec>(
        'ts_query_cursor_exec',
      ),
      cursorSetByteRange = lib.lookupFunction<_CursorRangeNative, _CursorRange>(
        'ts_query_cursor_set_byte_range',
      ),
      cursorNextMatch = lib.lookupFunction<_NextMatchNative, _NextMatch>(
        'ts_query_cursor_next_match',
      ),
      luau = lib.lookupFunction<_New, _New>('tree_sitter_luau')();

  final _New parserNew;
  final _Free parserDelete;
  final _SetLanguage parserSetLanguage;
  final _Parse parse;
  final _Free treeDelete;
  final _TreeEdit treeEdit;
  final _RootNode treeRootNode;
  final _NodeBool nodeHasError;
  final _NodeByte nodeStartByte;
  final _NodeByte nodeEndByte;
  final _QueryNew queryNew;
  final _Free queryDelete;
  final _Count queryCaptureCount;
  final _Count queryPatternCount;
  final _QueryName queryCaptureName;
  final _QueryName queryStringValue;
  final _QueryPredicates queryPredicates;
  final _New cursorNew;
  final _Free cursorDelete;
  final _CursorExec cursorExec;
  final _CursorRange cursorSetByteRange;
  final _NextMatch cursorNextMatch;

  /// the language of Luau
  final Pointer<Void> luau;

  static TreeSitter? _instance;
  static bool _tried = false;

  /// the library, or null when it is not there, which is the case for a
  /// build that has not made it. the file can be named with the environment
  /// variable `NYAXIS_SYNTAX_LIBRARY`.
  static TreeSitter? get instance {
    if (!_tried) {
      _tried = true;
      try {
        _instance = TreeSitter._(_open());
      } on Object {
        _instance = null;
      }
    }
    return _instance;
  }

  static DynamicLibrary _open() {
    final named = Platform.environment['NYAXIS_SYNTAX_LIBRARY'];
    if (named != null && named.isNotEmpty) {
      return DynamicLibrary.open(named);
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('nyaxis_syntax.dll');
    }
    if (Platform.isMacOS) {
      return DynamicLibrary.open('libnyaxis_syntax.dylib');
    }
    return DynamicLibrary.open('libnyaxis_syntax.so');
  }
}
