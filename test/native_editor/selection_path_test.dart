import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/native_editor/selection_path.dart';

void main() {
  group('the shape of a selection', () {
    test('on one row it is a box with its corners cut away', () {
      final paths = selectionPaths(100, [(10.0, 50.0)], 20, 3);
      expect(paths, hasLength(1));
      final path = paths.single;
      expect(path.getBounds(), const Rect.fromLTRB(10, 100, 50, 120));
      expect(path.contains(const Offset(30, 110)), isTrue);
      // the very corner is not in it, and a little in from it is
      expect(path.contains(const Offset(10.2, 100.2)), isFalse);
      expect(path.contains(const Offset(50 - 0.2, 120 - 0.2)), isFalse);
      expect(path.contains(const Offset(14, 104)), isTrue);
    });

    test('with no radius it is the box', () {
      final path = selectionPaths(100, [(10.0, 50.0)], 20, 0).single;
      expect(path.getBounds(), const Rect.fromLTRB(10, 100, 50, 120));
      expect(path.contains(const Offset(10.2, 100.2)), isTrue);
      expect(path.contains(const Offset(49.8, 119.8)), isTrue);
    });

    test(
      'over rows it is one shape that follows where each starts and ends',
      () {
        // the first row from 30 on, the next two whole, the last to 40
        final paths = selectionPaths(
          0,
          [(30.0, 200.0), (0.0, 200.0), (0.0, 40.0)],
          20,
          3,
        );
        expect(paths, hasLength(1));
        final path = paths.single;
        expect(path.getBounds(), const Rect.fromLTRB(0, 0, 200, 60));
        // what is in it, and what is not: before the start of the first row,
        // and after the end of the last
        expect(path.contains(const Offset(100, 10)), isTrue);
        expect(path.contains(const Offset(10, 10)), isFalse);
        expect(path.contains(const Offset(10, 30)), isTrue);
        expect(path.contains(const Offset(20, 50)), isTrue);
        expect(path.contains(const Offset(100, 50)), isFalse);
      },
    );

    test('rows that do not touch are two shapes', () {
      // the first row starts after the end of the second
      final paths = selectionPaths(0, [(100.0, 150.0), (0.0, 50.0)], 20, 3);
      expect(paths, hasLength(2));
      expect(paths.first.getBounds(), const Rect.fromLTRB(100, 0, 150, 20));
      expect(paths.last.getBounds(), const Rect.fromLTRB(0, 20, 50, 40));
    });

    test('a row that is narrower than the corners is still a shape', () {
      final path = selectionPaths(0, [(10.0, 12.0)], 20, 3).single;
      expect(path.getBounds(), const Rect.fromLTRB(10, 0, 12, 20));
    });

    test('there is nothing for no rows', () {
      expect(selectionPaths(0, const [], 20, 3), isEmpty);
    });
  });
}
