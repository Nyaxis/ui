import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/native_editor/scrollbar_layout.dart';

ScrollbarLayout _vertical({
  double height = 400,
  double viewport = 400,
  double range = 1600,
  double glyph = 20,
  double position = 0,
}) => ScrollbarLayout.compute(
  axis: ScrollbarAxis.vertical,
  track: Rect.fromLTWH(585, 0, 15, height),
  viewportSize: viewport,
  scrollRange: range,
  glyph: glyph,
  scrollPosition: position,
);

void main() {
  group('the thumb', () {
    test('is as long as the part that is shown, of the track', () {
      final layout = _vertical();
      // 20 rows are shown of 80
      expect(layout.thumb!.height, 100);
      expect(layout.thumb!.top, 0);
      expect(layout.thumb!.left, 585);
      expect(layout.thumb!.width, 15);
      expect(layout.visibleUnits, 20);
    });

    test('is not smaller than 25 pixels', () {
      final layout = _vertical(range: 400 * 100);
      expect(layout.thumb!.height, ScrollbarLayout.minThumbSize);
    });

    test('goes to the end of the track at the end of the text', () {
      // 80 rows of range, 20 shown: the last position is row 60
      final layout = _vertical(position: 60);
      expect(layout.thumb!.bottom, closeTo(400, 1e-9));
    });

    test('is not there when everything is shown', () {
      expect(_vertical(range: 400).thumb, isNull);
      expect(_vertical(range: 300).thumb, isNull);
    });

    test('moves by the same for each row in between', () {
      final a = _vertical(position: 10);
      final b = _vertical(position: 20);
      expect(b.thumb!.top - a.thumb!.top, closeTo(10 * a.unitSize, 1e-9));
      expect(a.unitSize, closeTo(300 / 60, 1e-9));
    });
  });

  group('the horizontal scrollbar', () {
    test('goes along the width, in columns', () {
      final layout = ScrollbarLayout.compute(
        axis: ScrollbarAxis.horizontal,
        track: const Rect.fromLTWH(0, 385, 585, 15),
        viewportSize: 500,
        scrollRange: 1000,
        glyph: 8,
        scrollPosition: 20,
      );
      expect(layout.thumb!.top, 385);
      expect(layout.thumb!.height, 15);
      expect(layout.thumb!.width, closeTo(585 * 0.5, 1e-9));
      expect(layout.visibleUnits, 62.5);
      expect(layout.thumb!.left, closeTo(20 * layout.unitSize, 1e-9));
    });
  });

  group('the mouse', () {
    test('a drag moves the text by what the thumb moved', () {
      final layout = _vertical(position: 10);
      final moved = layout.draggedPosition(2 * layout.unitSize);
      expect(moved, closeTo(12, 1e-9));
      expect(layout.draggedPosition(-1000), 0);
    });

    test('a press on the track puts what is shown around that place', () {
      final layout = _vertical();
      // 5 pixels of the track for a row, so 200 pixels down is row 40, and
      // half of the 20 rows that are shown come before it
      final position = layout.clickedPosition(const Offset(590, 200));
      expect(position, 30);
      // pressed at the very start, it is the start
      expect(layout.clickedPosition(const Offset(590, 0)), 0);
      // a place down the track is that row, less half of what is shown
      final far = layout.clickedPosition(const Offset(590, 300));
      expect(far, (300 / layout.unitSize).round() - 10);
    });

    test('the thumb knows when the pointer is on it', () {
      final layout = _vertical(position: 20);
      final thumb = layout.thumb!;
      expect(layout.thumbHovered(thumb.center), isTrue);
      expect(
        layout.thumbHovered(Offset(thumb.center.dx, thumb.top - 5)),
        isFalse,
      );
      expect(
        _vertical(range: 400).thumbHovered(const Offset(590, 10)),
        isFalse,
      );
    });
  });
}
