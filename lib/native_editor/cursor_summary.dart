import '../editor_core/rope.dart';
import '../editor_core/selection.dart';

/// what the status bar says of the cursor: the line and the column of the
/// newest selection's end, as `3:5`, and after it what is selected, as
/// `3:5 (2 lines, 14 characters)`. columns count characters, from 1.
String cursorSummary(Rope text, List<Selection> selections, Selection newest) {
  final row = text.rowAt(newest.head);
  final column = text.substring(text.lineStart(row), newest.head).runes.length;
  final summary = StringBuffer('${row + 1}:${column + 1}');

  var characters = 0;
  var lines = 0;
  for (final selection in selections) {
    if (selection.isEmpty) {
      continue;
    }
    characters += text.substring(selection.start, selection.end).runes.length;
    final first = text.rowAt(selection.start);
    final last = text.rowAt(selection.end);
    lines += last - first;
    if (selection.end != text.lineStart(last)) {
      lines += 1;
    }
  }

  final parts = <String>[
    if (selections.length > 1) '${selections.length} selections',
    if (lines > 1) '$lines lines',
    if (characters > 0) '$characters character${characters > 1 ? 's' : ''}',
  ];
  if (parts.isNotEmpty) {
    summary.write(' (${parts.join(', ')})');
  }
  return summary.toString();
}
