import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor_core/patch.dart';

void main() {
  group('Patch', () {
    test('a position before the edits stays, and one after them moves', () {
      // 'abcdef' with 'cd' replaced by 'XYZ'
      const patch = Patch([Edit(2, 2, 3)]);
      expect(patch.mapOffset(0, Bias.left), 0);
      expect(patch.mapOffset(1, Bias.right), 1);
      expect(patch.mapOffset(5, Bias.left), 6);
      expect(patch.mapOffset(6, Bias.right), 7);
      expect(patch.delta, 1);
    });

    test(
      'a position in a replaced range goes to one end of what replaced it',
      () {
        const patch = Patch([Edit(2, 4, 1)]);
        expect(patch.mapOffset(3, Bias.left), 2);
        expect(patch.mapOffset(3, Bias.right), 3);
        expect(patch.mapOffset(2, Bias.left), 2);
        expect(patch.mapOffset(6, Bias.right), 3);
      },
    );

    test('text put in at a position leaves it before or after, as asked', () {
      const patch = Patch([Edit(4, 0, 5)]);
      expect(patch.mapOffset(4, Bias.left), 4);
      expect(patch.mapOffset(4, Bias.right), 9);
      expect(patch.mapOffset(3, Bias.right), 3);
      expect(patch.mapOffset(5, Bias.left), 10);
    });

    test('several edits are followed one after another', () {
      const patch = Patch([Edit(1, 1, 3), Edit(5, 2, 0), Edit(9, 0, 4)]);
      expect(patch.mapOffset(4, Bias.left), 6);
      // 3 more units from the first edit, 2 fewer from the second
      expect(patch.mapOffset(8, Bias.left), 8);
      expect(patch.mapOffset(9, Bias.left), 9);
      expect(patch.mapOffset(9, Bias.right), 9 + 4);
      expect(patch.mapOffset(12, Bias.left), 12 + 2 - 2 + 4);
      expect(patch.delta, 2 - 2 + 4);
    });

    test('nothing changes with no edits', () {
      expect(Patch.empty.isEmpty, isTrue);
      expect(Patch.empty.mapOffset(7, Bias.right), 7);
      expect(Patch.empty, const Patch([]));
    });
  });
}
