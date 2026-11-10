import 'sum_tree.dart';

class _LastOps<T> extends SummaryOps<T, T?> {
  const _LastOps();

  @override
  T? get zero => null;

  @override
  T? add(T? a, T? b) => b ?? a;

  @override
  T? summarize(T item) => item;
}

/// items kept in the order of [compare], in a tree that never changes: what
/// puts items in makes a new tree that shares what it can with the old one.
/// two items that compare the same are one item, and the later replaces the
/// earlier.
class OrderedTree<T extends Object> {
  OrderedTree(this.compare) : _tree = SumTree(_LastOps<T>());

  OrderedTree._(this.compare, this._tree);

  final int Function(T a, T b) compare;
  final SumTree<T, T?> _tree;

  bool get isEmpty => _tree.isEmpty;
  T? get first => _tree.first;
  T? get last => _tree.last;
  Iterable<T> get items => _tree.items;

  SeekTarget<T?> _target(T key) =>
      (position) => position == null ? 1 : compare(key, position);

  Cursor<T, T?, T?> _cursor() =>
      _tree.cursor(SummaryDimension<T, T?>(_tree.ops));

  /// this tree with each of [items] put in, in place of the one that compares
  /// the same as it when there is one
  OrderedTree<T> insertAll(Iterable<T> items) {
    final sorted = List.of(items)..sort(compare);
    if (sorted.isEmpty) {
      return this;
    }
    final cursor = _cursor();
    var tree = SumTree<T, T?>(_tree.ops);
    final buffered = <T>[];
    cursor.next();
    for (final item in sorted) {
      var old = cursor.item;
      if (old != null && compare(old, item) < 0) {
        tree = tree.extend(buffered);
        buffered.clear();
        tree = tree.append(cursor.slice(_target(item), Bias.left));
        old = cursor.item;
      }
      if (old != null && compare(old, item) == 0) {
        cursor.next();
      }
      if (buffered.isNotEmpty && compare(buffered.last, item) == 0) {
        buffered.removeLast();
      }
      buffered.add(item);
    }
    tree = tree.extend(buffered).append(cursor.suffix());
    return OrderedTree._(compare, tree);
  }

  /// the first item that is not before [key], and the item before that one.
  /// with [Bias.right], the first item that is after [key].
  (T? previous, T? item) findWithPrevious(T key, Bias bias) {
    final cursor = _cursor()..seek(_target(key), bias);
    return (cursor.prevItem, cursor.item);
  }

  /// the items from the first that is not before [key], in order
  Iterable<T> from(T key) sync* {
    final cursor = _cursor()..seek(_target(key), Bias.left);
    while (true) {
      final item = cursor.item;
      if (item == null) {
        return;
      }
      yield item;
      cursor.next();
    }
  }
}
