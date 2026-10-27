import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/theme/app_theme.dart';
import 'package:ui/ui/dialog.dart';

void main() {
  const theme = AppTheme();

  /// opens the dialog, and returns what it resolves to: empty while open
  Future<List<int?>> open(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final context = tester.element(find.byType(Scaffold));
    final chosen = <int?>[];
    showConfirmDialog(
      context,
      theme: theme,
      message: 'Save changes?',
      details: const ['a.luau', 'untitled'],
      buttons: const ['Save all', 'Discard all', 'Cancel'],
    ).then(chosen.add);
    await tester.pumpAndSettle();
    return chosen;
  }

  testWidgets('it shows the message, the files and the buttons', (
    tester,
  ) async {
    await open(tester);
    for (final text in [
      'Save changes?',
      'a.luau',
      'untitled',
      'Save all',
      'Discard all',
      'Cancel',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
  });

  testWidgets('a click chooses a button', (tester) async {
    final chosen = await open(tester);
    await tester.tap(find.text('Discard all'));
    await tester.pumpAndSettle();
    expect(chosen, [1]);
    expect(find.text('Save changes?'), findsNothing);
  });

  testWidgets('enter chooses the first button, the arrows move it', (
    tester,
  ) async {
    var chosen = await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(chosen, [0]);

    chosen = await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(chosen, [1]);
  });

  testWidgets('escape chooses nothing', (tester) async {
    final chosen = await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(chosen, [null]);
  });

  testWidgets('text between backticks is shown as code, without them', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    showConfirmDialog(
      tester.element(find.byType(Scaffold)),
      theme: theme,
      message: '`a.luau` has unsaved edits',
      buttons: const ['OK'],
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('`', findRichText: true), findsNothing);
    expect(
      find.textContaining(' a.luau  has unsaved edits', findRichText: true),
      findsOneWidget,
    );
  });
}
