import 'package:flutter/material.dart';

/// what a palette looks like: a box in its background color, with a square
/// for each of its other colors. [colors] are in the order of
/// `ThemeController.paletteRoles`, and [border] outlines the box
class PalettePreview extends StatelessWidget {
  const PalettePreview({super.key, required this.colors, required this.border});

  static const _square = 8.0;
  static const _gap = 2.0;
  static const _padding = 2.0;
  static const _border = 1.0;

  /// the squares of each row, as indexes of the roles: the surfaces and lines
  /// first, then the text and the colors that stand out
  static const _rows = [
    [1, 2, 3, 10, 11, 8],
    [4, 5, 9, 6, 7],
  ];

  static const width = (_padding + _border) * 2 + _square * 6 + _gap * 5;
  static const height = (_padding + _border) * 2 + _square * 2 + _gap;

  final List<Color> colors;
  final Color border;

  @override
  Widget build(BuildContext context) {
    if (colors.length < 12) {
      return const SizedBox(width: width, height: height);
    }
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(_padding),
      decoration: BoxDecoration(
        color: colors[0],
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border, width: _border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final row in _rows)
            Row(
              children: [
                for (var i = 0; i < row.length; i++) ...[
                  if (i > 0) const SizedBox(width: _gap),
                  Container(
                    width: _square,
                    height: _square,
                    decoration: BoxDecoration(
                      color: colors[row[i]],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
