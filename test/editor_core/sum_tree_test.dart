import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor_core/sum_tree.dart';

class _Summary {
  const _Summary(this.count, this.sum, this.containsEven, this.max);

  final int count;
  final int sum;
  final bool containsEven;
  final int max;
}

class _Ops extends SummaryOps<int, _Summary> {
  const _Ops();

  @override
  _Summary get zero => const _Summary(0, 0, false, 0);

  @override
  _Summary add(_Summary a, _Summary b) => _Summary(
    a.count + b.count,
    a.sum + b.sum,
    a.containsEven || b.containsEven,
    max(a.max, b.max),
  );

  @override
  _Summary summarize(int item) => _Summary(1, item, item.isEven, item);
}

class _Count extends Dimension<_Summary, int> {
  const _Count();

  @override
  int get zero => 0;

  @override
  int add(int position, _Summary summary) => position + summary.count;
}

class _Sum extends Dimension<_Summary, int> {
  const _Sum();

  @override
  int get zero => 0;

  @override
  int add(int position, _Summary summary) => position + summary.sum;
}

const _ops = _Ops();
const _count = _Count();
const _sum = _Sum();

SeekTarget<int> _at(int target) =>
    (position) => target.compareTo(position);

List<int> _randomItems(Random random, int count) =>
    List.generate(count, (_) => random.nextInt(256));

void main() {
  group('SumTree', () {
    test('trees are joined, whichever is the taller', () {
      final small = SumTree(_ops).extend(List.generate(20, (i) => i));
      final large = SumTree(_ops).extend(List.generate(500, (i) => 1000 + i));
      expect(small.append(large).items.toList(), [
        ...List.generate(20, (i) => i),
        ...List.generate(500, (i) => 1000 + i),
      ]);
      expect(large.append(small).items.toList(), [
        ...List.generate(500, (i) => 1000 + i),
        ...List.generate(20, (i) => i),
      ]);
      expect(small.append(SumTree(_ops)).items.length, 20);
      expect(SumTree(_ops).append(small).items.length, 20);
    });

    test('items pushed one by one are all there, with their summary', () {
      var tree = SumTree(_ops);
      for (var i = 0; i < 1000; i++) {
        tree = tree.push(i);
      }
      expect(tree.items.toList(), List.generate(1000, (i) => i));
      expect(tree.summary.count, 1000);
      expect(tree.summary.sum, 999 * 1000 ~/ 2);
      expect(tree.summary.max, 999);
      expect(tree.first, 0);
      expect(tree.last, 999);
      expect(tree.extent(_count), 1000);
    });

    test('an item is found by where it is, with where it starts and ends', () {
      final tree = SumTree(_ops).extend(List.generate(100, (i) => i * 2));
      expect(tree.find(_count, _at(10), Bias.right), (10, 11, 20));
      expect(tree.find(_count, _at(10), Bias.left), (9, 10, 18));
      expect(tree.find(_count, _at(100), Bias.right), (100, 100, null));
      expect(tree.find(_count, _at(100), Bias.left), (99, 100, 198));
      expect(tree.find(_count, _at(101), Bias.left), (100, 100, null));
      expect(SumTree(_ops).find(_count, _at(0), Bias.left), (0, 0, null));
    });

    test('a cursor on an empty tree is at nothing', () {
      final tree = SumTree(_ops);
      final cursor = tree.cursor(_count);
      expect(cursor.slice(_at(0), Bias.right).items, isEmpty);
      expect(cursor.item, isNull);
      expect(cursor.prevItem, isNull);
      expect(cursor.nextItem, isNull);
      cursor.prev();
      expect(cursor.item, isNull);
      cursor.next();
      expect(cursor.item, isNull);
      expect(cursor.start, 0);
    });

    test('a cursor on a tree of one item goes onto it and off it', () {
      final tree = SumTree(_ops).push(1);
      final cursor = tree.cursor(_sum);
      expect(cursor.slice(_at(0), Bias.right).items, isEmpty);
      expect(cursor.item, 1);
      expect(cursor.prevItem, isNull);
      expect(cursor.nextItem, isNull);
      expect(cursor.start, 0);
      cursor.next();
      expect(cursor.item, isNull);
      expect(cursor.prevItem, 1);
      expect(cursor.start, 1);
      cursor.prev();
      expect(cursor.item, 1);
      expect(cursor.start, 0);
      final again = tree.cursor(_sum);
      expect(again.suffix().items.toList(), [1]);
      expect(again.item, isNull);
      expect(again.prevItem, 1);
    });

    test('random trees are spliced, sought in and filtered like a list', () {
      for (var seed = 0; seed < 150; seed++) {
        final random = Random(seed);
        var tree = SumTree(_ops)
            .extend(_randomItems(random, random.nextInt(10)));
        for (var operation = 0; operation < 8; operation++) {
          final spliceEnd = random.nextInt(tree.extent(_count) + 1);
          final spliceStart = random.nextInt(spliceEnd + 1);
          final newItems = _randomItems(random, random.nextInt(40));
          final reference = tree.items.toList()
            ..replaceRange(spliceStart, spliceEnd, newItems);

          final splice = tree.cursor(_count);
          var newTree = splice.slice(_at(spliceStart), Bias.right);
          newTree = newTree.extend(newItems);
          splice.seek(_at(spliceEnd), Bias.right);
          tree = newTree.append(splice.suffix());

          expect(tree.items.toList(), reference, reason: 'seed $seed');
          expect(tree.summary.count, reference.length);
          expect(tree.summary.sum, reference.fold<int>(0, (a, b) => a + b));

          final filter = tree.filter(_count, (s) => s.containsEven);
          final evens = [
            for (var i = 0; i < reference.length; i++)
              if (reference[i].isEven) (i, reference[i]),
          ];
          var index = 0;
          if (random.nextBool()) {
            filter.next();
          } else {
            filter.prev();
            index = evens.isEmpty ? 0 : evens.length - 1;
          }
          while (index < evens.length) {
            expect(filter.item, evens[index].$2, reason: 'seed $seed');
            expect(filter.start, evens[index].$1);
            filter.next();
            index++;
            while (index > 0 && random.nextDouble() < 0.2) {
              filter.prev();
              index--;
              if (index == 0 && random.nextDouble() < 0.2) {
                filter.prev();
                expect(filter.item, isNull);
                expect(filter.start, 0);
                filter.next();
              }
            }
          }
          expect(filter.item, isNull);

          var beforeStart = false;
          final cursor = tree.cursor(_count);
          final startPos = random.nextInt(reference.length + 1);
          cursor.seek(_at(startPos), Bias.right);
          var pos = startPos + random.nextInt(reference.length - startPos + 1);
          cursor.seekForward(_at(pos), Bias.right);
          for (var i = 0; i < 10; i++) {
            expect(cursor.start, pos, reason: 'seed $seed');
            expect(cursor.prevItem, pos > 0 ? reference[pos - 1] : null);
            expect(
              cursor.item,
              pos < reference.length && !beforeStart ? reference[pos] : null,
            );
            if (beforeStart) {
              expect(
                cursor.nextItem,
                reference.isEmpty ? null : reference.first,
              );
            } else {
              expect(
                cursor.nextItem,
                pos + 1 < reference.length ? reference[pos + 1] : null,
              );
            }
            if (i < 5) {
              cursor.next();
              if (pos < reference.length) {
                pos++;
                beforeStart = false;
              }
            } else {
              cursor.prev();
              if (pos == 0) {
                beforeStart = true;
              }
              pos = max(0, pos - 1);
            }
          }
        }

        for (var i = 0; i < 10; i++) {
          final end = random.nextInt(tree.extent(_count) + 1);
          final start = random.nextInt(end + 1);
          final startBias = random.nextBool() ? Bias.left : Bias.right;
          final endBias = random.nextBool() ? Bias.left : Bias.right;
          final cursor = tree.cursor(_count);
          cursor.seek(_at(start), startBias);
          final slice = cursor.slice(_at(end), endBias);
          cursor.seek(_at(start), startBias);
          final summary = cursor.summary(_sum, _at(end), endBias);
          expect(summary, slice.summary.sum, reason: 'seed $seed');
        }
      }
    });

    test('a tree made at once and one made by pushing have the same items', () {
      final random = Random(1);
      for (final count in [0, 1, 11, 12, 13, 143, 144, 145, 5000]) {
        final items = _randomItems(random, count);
        final atOnce = SumTree.fromIterable(_ops, items);
        var pushed = SumTree(_ops);
        for (final item in items) {
          pushed = pushed.push(item);
        }
        expect(atOnce.items.toList(), items);
        expect(pushed.items.toList(), items);
        expect(atOnce.summary.sum, pushed.summary.sum);
      }
    });
  });
}
