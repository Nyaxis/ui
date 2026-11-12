import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/theme/app_theme.dart';
import 'package:ui/ui/settings_controls.dart';
import 'package:ui/ui/sidebar.dart';
import 'package:ui/ui/skinnable_icon.dart';

const _theme = AppTheme();

Color? _fillOf(WidgetTester tester, Finder inside) {
  final boxes = find.descendant(of: inside, matching: find.byType(Container));
  for (final box in tester.widgetList<Container>(boxes)) {
    final decoration = box.decoration;
    if (decoration is BoxDecoration && decoration.color != null) {
      return decoration.color;
    }
  }
  return null;
}

Future<TestGesture> _mouse(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: const Offset(-10, -10));
  addTearDown(gesture.removePointer);
  return gesture;
}

void main() {
  testWidgets('a row of the sidebar is filled as a row of a list is', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Column(
            children: [
              SidebarItem(
                theme: _theme,
                icon: 'settings',
                label: 'row',
                keys: null,
                selected: true,
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
    final row = find.byType(SidebarItem);
    // selected, the pointer away
    expect(_fillOf(tester, row), _theme.chosen.withValues(alpha: 0x66 / 255));
    final gesture = await _mouse(tester);
    await gesture.moveTo(tester.getCenter(row));
    await tester.pump();
    expect(_fillOf(tester, row), _theme.hover.withValues(alpha: 0x4D / 255));
    await gesture.down(tester.getCenter(row));
    await tester.pump();
    expect(_fillOf(tester, row), _theme.active.withValues(alpha: 0x99 / 255));
    await gesture.up();
  });

  testWidgets('a switch gets lighter while the pointer is on it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: SwitchControl(
              theme: _theme,
              value: false,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    final control = find.byType(SwitchControl);
    expect(_fillOf(tester, control), _theme.disabled);
    final gesture = await _mouse(tester);
    await gesture.moveTo(tester.getCenter(control));
    await tester.pumpAndSettle();
    expect(
      _fillOf(tester, control),
      Color.alphaBlend(
        _theme.textPrimary.withValues(alpha: 0.05),
        _theme.disabled,
      ),
    );
  });

  testWidgets('the check mark of a dropdown menu is after the label', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: DropdownControl<int>(
              theme: _theme,
              value: 2,
              options: const [(1, 'one'), (2, 'two')],
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(DropdownControl<int>));
    await tester.pump(const Duration(milliseconds: 300));
    // the label in the menu is the last of the two that say it
    final label = tester.getRect(find.text('two').last);
    final marks = find.byWidgetPredicate(
      (w) => w is SkinnableIcon && w.name == 'checkmark',
    );
    expect(marks, findsWidgets);
    for (final mark in marks.evaluate()) {
      final rect = tester.getRect(find.byElementPredicate((e) => e == mark));
      // the one in the menu is after the label; any other is in the button,
      // which is not a menu
      if (rect.top >= label.top - 1 && rect.bottom <= label.bottom + 1) {
        expect(rect.left, greaterThanOrEqualTo(label.right));
      }
    }
  });

  testWidgets('a dropdown is an outlined button of 28 rems', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: DropdownControl<int>(
              theme: _theme,
              value: 1,
              options: const [(1, 'one'), (2, 'two')],
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    final control = find.byType(DropdownControl<int>);
    expect(tester.getSize(control).height, _theme.rem(28));
    expect(_fillOf(tester, control), _theme.titleBar);
    final gesture = await _mouse(tester);
    await gesture.moveTo(tester.getCenter(control));
    await tester.pump();
    expect(
      _fillOf(tester, control),
      _theme.hover.withValues(alpha: 0x4D / 255),
    );
    await gesture.down(tester.getCenter(control));
    await tester.pump();
    expect(
      _fillOf(tester, control),
      _theme.active.withValues(alpha: 0x4D / 255),
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
