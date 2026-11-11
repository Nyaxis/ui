cmake_minimum_required(VERSION 3.14)
project(nyaxis_syntax LANGUAGES C)

# the tree-sitter runtime and the Luau grammar in one library, which the editor
# loads to parse scripts and to find what to color in them
add_library(nyaxis_syntax SHARED
  runtime/src/alloc.c
  runtime/src/get_changed_ranges.c
  runtime/src/language.c
  runtime/src/lexer.c
  runtime/src/node.c
  runtime/src/parser.c
  runtime/src/point.c
  runtime/src/query.c
  runtime/src/stack.c
  runtime/src/subtree.c
  runtime/src/tree_cursor.c
  runtime/src/tree.c
  runtime/src/wasm_store.c
  luau/parser.c
  luau/scanner.c
)

target_include_directories(nyaxis_syntax PRIVATE
  runtime/src
  runtime/include
  luau
)

set_target_properties(nyaxis_syntax PROPERTIES
  C_STANDARD 11
  C_VISIBILITY_PRESET default
  WINDOWS_EXPORT_ALL_SYMBOLS ON
)

if(NOT MSVC)
  target_compile_definitions(nyaxis_syntax PRIVATE _POSIX_C_SOURCE=200112L _DEFAULT_SOURCE)
endif()
