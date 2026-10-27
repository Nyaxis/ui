import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/theme/app_theme.dart';
import 'package:ui/ui/sidebar.dart';

void main() {
  const theme = AppTheme();

  /// pumps a 200 wide panel docked to [onLeft] in a 600 wide window, and
  /// returns where it was asked to resize to and whether the drag ended
  Future<({List<double> widths, List<bool> ended})> open(
    WidgetTester tester, {
    required bool onLeft,
  }) async {
    final widths = <double>[];
    final ended = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: onLeft ? Alignment.centerLeft : Alignment.centerRight,
          child: SidebarPanel(
            theme: theme,
            width: 200,
            onLeft: onLeft,
            onResize: widths.add,
            onResizeEnd: () => ended.add(true),
          ),
        ),
      ),
    );
    return (widths: widths, ended: ended);
  }

  testWidgets(
    'dragging the inner edge of a left panel to the right widens it',
    (tester) async {
      final result = await open(tester, onLeft: true);
      await tester.dragFrom(const Offset(197, 300), const Offset(30, 0));
      expect(result.widths.last, 230);
      expect(result.ended, [true]);
    },
  );

  testWidgets(
    'dragging the inner edge of a right panel to the right narrows it',
    (tester) async {
      final result = await open(tester, onLeft: false);
      // the test window is 800 wide, so the panel is at 600 to 800
      await tester.dragFrom(const Offset(603, 300), const Offset(30, 0));
      expect(result.widths.last, 170);
      expect(result.ended, [true]);
    },
  );
}
