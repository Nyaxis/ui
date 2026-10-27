import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/theme/app_theme.dart';
import 'package:ui/ui/context_menu.dart';

void main() {
  const theme = AppTheme();

  Future<void> open(
    WidgetTester tester,
    List<ContextMenuEntry> entries, {
    Offset position = const Offset(20, 20),
  }) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    showContextMenu(
      tester.element(find.byType(Scaffold)),
      position: position,
      entries: entries,
      theme: theme,
      keysFor: (action) => {'tab::Close': 'ctrl-k w'}[action],
    );
    await tester.pump();
  }

  testWidgets('an item runs and closes the menu', (tester) async {
    var closed = 0;
    await open(tester, [
      ContextMenuItem('Close', onPressed: () => closed++),
      const ContextMenuSeparator(),
      const ContextMenuItem('Pin Tab', onPressed: null),
    ]);

    await tester.tap(find.text('Close'));
    await tester.pump();

    expect(closed, 1);
    expect(find.text('Close'), findsNothing);
  });

  testWidgets('a greyed out item does nothing', (tester) async {
    await open(tester, [const ContextMenuItem('Pin Tab')]);

    await tester.tap(find.text('Pin Tab'));
    await tester.pump();

    expect(find.text('Pin Tab'), findsOneWidget);
  });

  testWidgets('pressing outside or escape closes it', (tester) async {
    await open(tester, [ContextMenuItem('Close', onPressed: () {})]);
    await tester.tapAt(const Offset(700, 500));
    await tester.pump();
    expect(find.text('Close'), findsNothing);

    showContextMenu(
      tester.element(find.byType(Scaffold)),
      position: Offset.zero,
      entries: [ContextMenuItem('Close', onPressed: () {})],
      theme: theme,
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Close'), findsNothing);
  });

  testWidgets('the keys of an item\'s action are shown beside it', (
    tester,
  ) async {
    await open(tester, [
      ContextMenuItem('Close', onPressed: () {}, action: 'tab::Close'),
      ContextMenuItem('Pin Tab', onPressed: () {}, action: 'tab::Pin'),
    ]);

    expect(find.text('Ctrl-K W'), findsOneWidget);
    // an action without keys shows nothing
    expect(find.byType(Text), findsNWidgets(3));
  });

  testWidgets('a menu opened at the edge stays inside the window', (
    tester,
  ) async {
    await open(tester, [
      ContextMenuItem('Close', onPressed: () {}),
    ], position: const Offset(100000, 100000));

    final box = tester.getRect(find.byType(DecoratedBox).last);
    const window = Rect.fromLTWH(0, 0, 800, 600);
    expect(window.contains(box.topLeft), isTrue);
    expect(window.contains(box.bottomRight - const Offset(1, 1)), isTrue);
  });
}
