; The pairs that are lit while the cursor is in them or at an edge of them: the
; smallest one that holds the cursor. @open and @close are the two ends.

; Brackets
(arguments
  "(" @open
  ")" @close)

(parameters
  "(" @open
  ")" @close)

(parenthesized_expression
  "(" @open
  ")" @close)

(table_constructor
  "{" @open
  "}" @close)

(bracket_index_expression
  "[" @open
  "]" @close)

; Blocks
(function_declaration
  "function" @open
  "end" @close)

(function_definition
  "function" @open
  "end" @close)

(do_statement
  "do" @open
  "end" @close)

(while_statement
  "while" @open
  "end" @close)

(for_statement
  "for" @open
  "end" @close)

(if_statement
  "if" @open
  "end" @close)

(repeat_statement
  "repeat" @open
  "until" @close)
