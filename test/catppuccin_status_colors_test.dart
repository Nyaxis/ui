import 'package:flutter_test/flutter_test.dart';
import 'package:ui/theme/catppuccin.dart';

void main() {
  // the status colors of the Catppuccin themes: error, warning, info and hint
  const status = {
    'Catppuccin Latte': ['#d20f39', '#df8e1d', '#179299', '#acb0be'],
    'Catppuccin Frappé': ['#e78284', '#e5c890', '#81c8be', '#626880'],
    'Catppuccin Macchiato': ['#ed8796', '#eed49f', '#8bd5ca', '#5b6078'],
    'Catppuccin Mocha': ['#f38ba8', '#f9e2af', '#94e2d5', '#585b70'],
  };

  test('the palettes have the status colors of the Catppuccin themes', () {
    expect(catppuccinPalettes.keys, containsAll(status.keys));
    for (final entry in status.entries) {
      final palette = catppuccinPalettes[entry.key]!;
      expect(
        [palette['red'], palette['warning'], palette['info'], palette['hint']],
        entry.value,
        reason: entry.key,
      );
    }
  });

  // the subtle border, and the fill of an item that the keys have chosen
  const items = {
    'Catppuccin Latte': ['#e7e2f5', '#8f94a7'],
    'Catppuccin Frappé': ['#3c3c53', '#7c829a'],
    'Catppuccin Macchiato': ['#313148', '#737995'],
    'Catppuccin Mocha': ['#2c293d', '#6f728d'],
  };

  test('the palettes have the colors of the borders and chosen items', () {
    for (final entry in items.entries) {
      final palette = catppuccinPalettes[entry.key]!;
      expect(
        [palette['borderVariant'], palette['chosen']],
        entry.value,
        reason: entry.key,
      );
    }
  });
}
