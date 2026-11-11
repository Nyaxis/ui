import 'patch.dart' show Bias;

export 'patch.dart' show Bias;

/// a node has from this many children to twice as many, but for the root
const int treeBase = 6;

/// how the items of a tree are summed up: what one item comes to, and how two
/// sums are put together, which must not matter how they are grouped
abstract class SummaryOps<T, S> {
  const SummaryOps();

  S get zero;
  S add(S a, S b);
  S summarize(T item);
}

/// something counted along a tree from its start, which a cursor can be at:
/// the sum of the summaries before it, seen one way
abstract class Dimension<S, D> {
  const Dimension();

  D get zero;
  D add(D position, S summary);
}

/// the summary itself as what is counted
class SummaryDimension<T, S> extends Dimension<S, S> {
  const SummaryDimension(this.ops);

  final SummaryOps<T, S> ops;

  @override
  S get zero => ops.zero;

  @override
  S add(S position, S summary) => ops.add(position, summary);
}

/// what is looked for, compared to a place: less than zero when it is before
/// the place, zero when it is at it, and more when it is after
typedef SeekTarget<D> = int Function(D position);

sealed class _Node<T, S> {
  S get summary;
  int get height;
  List<S> get childSummaries;
}

class _Leaf<T, S> implements _Node<T, S> {
  _Leaf(this.summary, this.items, this.itemSummaries);

  @override
  final S summary;
  final List<T> items;
  final List<S> itemSummaries;

  @override
  int get height => 0;

  @override
  List<S> get childSummaries => itemSummaries;
}

class _Internal<T, S> implements _Node<T, S> {
  _Internal(this.height, this.summary, this.childSummaries, this.childTrees);

  @override
  final int height;

  @override
  final S summary;

  @override
  final List<S> childSummaries;
  final List<_Node<T, S>> childTrees;
}

/// a B+ tree in which each leaf has items and the summary of each, and each
/// node above has the summary of all below it. a tree never changes: what
/// adds to one makes a new one that shares what it can with the old.
///
/// anything that the summaries can be seen as, a [Dimension], can be used to
/// find a place in the tree with a [Cursor].
class SumTree<T, S> {
  SumTree._(this.ops, this._root);

  factory SumTree(SummaryOps<T, S> ops) =>
      SumTree._(ops, _Leaf(ops.zero, const [], const []));

  factory SumTree.fromItem(SummaryOps<T, S> ops, T item) =>
      SumTree(ops).push(item);

  factory SumTree.fromIterable(SummaryOps<T, S> ops, Iterable<T> items) {
    var nodes = <_Node<T, S>>[];
    final iterator = items.iterator;
    var more = iterator.moveNext();
    while (more) {
      final leafItems = <T>[];
      final summaries = <S>[];
      while (more && leafItems.length < 2 * treeBase) {
        leafItems.add(iterator.current);
        summaries.add(ops.summarize(iterator.current));
        more = iterator.moveNext();
      }
      nodes.add(_Leaf(_sum(ops, summaries), leafItems, summaries));
    }
    var height = 0;
    while (nodes.length > 1) {
      height++;
      final parents = <_Node<T, S>>[];
      for (var i = 0; i < nodes.length; i += 2 * treeBase) {
        final end = i + 2 * treeBase < nodes.length
            ? i + 2 * treeBase
            : nodes.length;
        final children = nodes.sublist(i, end);
        parents.add(_internal(ops, height, children));
      }
      nodes = parents;
    }
    return nodes.isEmpty ? SumTree(ops) : SumTree._(ops, nodes.single);
  }

  final SummaryOps<T, S> ops;
  final _Node<T, S> _root;

  S get summary => _root.summary;

  bool get isEmpty {
    final root = _root;
    return root is _Leaf<T, S> && root.items.isEmpty;
  }

  T? get first => isEmpty ? null : _leftmostLeaf(_root).items.first;
  T? get last => isEmpty ? null : _rightmostLeaf(_root).items.last;

  /// how far the whole tree goes in [dimension]
  D extent<D>(Dimension<S, D> dimension) =>
      dimension.add(dimension.zero, summary);

  /// every item, in order
  Iterable<T> get items sync* {
    final stack = <_Node<T, S>>[_root];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      switch (node) {
        case _Leaf<T, S>():
          yield* node.items;
        case _Internal<T, S>():
          for (var i = node.childTrees.length - 1; i >= 0; i--) {
            stack.add(node.childTrees[i]);
          }
      }
    }
  }

  Cursor<T, S, D> cursor<D>(Dimension<S, D> dimension) =>
      Cursor._(this, dimension);

  /// a cursor that only stops at items whose summary, or that of a node they
  /// are under, [filter] lets through
  FilterCursor<T, S, D> filter<D>(
    Dimension<S, D> dimension,
    bool Function(S summary) filter,
  ) => FilterCursor._(Cursor._(this, dimension), filter);

  /// the item that [target] is in, with where it starts and ends; quicker
  /// than a cursor that is made, sought with and read. the item is null when
  /// the target is past the end.
  (D start, D end, T? item) find<D>(
    Dimension<S, D> dimension,
    SeekTarget<D> target,
    Bias bias,
  ) {
    final treeEnd = dimension.add(dimension.zero, summary);
    final comparison = target(treeEnd);
    if (comparison > 0 || (comparison == 0 && bias == Bias.right)) {
      return (treeEnd, treeEnd, null);
    }
    var position = dimension.zero;
    var node = _root;
    descend:
    while (true) {
      final current = node;
      switch (current) {
        case _Internal<T, S>():
          for (var i = 0; i < current.childTrees.length; i++) {
            final childEnd = dimension.add(position, current.childSummaries[i]);
            final c = target(childEnd);
            if (c < 0 || (c == 0 && bias == Bias.left)) {
              node = current.childTrees[i];
              continue descend;
            }
            position = childEnd;
          }
        case _Leaf<T, S>():
          for (var i = 0; i < current.items.length; i++) {
            final childEnd = dimension.add(position, current.itemSummaries[i]);
            final c = target(childEnd);
            if (c < 0 || (c == 0 && bias == Bias.left)) {
              return (position, childEnd, current.items[i]);
            }
            position = childEnd;
          }
      }
      return (position, position, null);
    }
  }

  /// this tree with its last item changed by [update]
  SumTree<T, S> updateLast(T Function(T item) update) =>
      isEmpty ? this : SumTree._(ops, _updateLast(_root, update));

  _Node<T, S> _updateLast(_Node<T, S> node, T Function(T item) update) {
    switch (node) {
      case _Internal<T, S>():
        final summaries = List.of(node.childSummaries);
        final trees = List.of(node.childTrees);
        final last = _updateLast(trees.last, update);
        trees[trees.length - 1] = last;
        summaries[summaries.length - 1] = last.summary;
        return _internalWith(node.height, summaries, trees);
      case _Leaf<T, S>():
        final items = List.of(node.items);
        final summaries = List.of(node.itemSummaries);
        final item = update(items.last);
        items[items.length - 1] = item;
        summaries[summaries.length - 1] = ops.summarize(item);
        return _leafWith(items, summaries);
    }
  }

  SumTree<T, S> push(T item) {
    final summary = ops.summarize(item);
    return append(SumTree._(ops, _Leaf(summary, [item], [summary])));
  }

  SumTree<T, S> extend(Iterable<T> items) =>
      append(SumTree.fromIterable(ops, items));

  /// this tree with the items of [other] after its own
  SumTree<T, S> append(SumTree<T, S> other) {
    if (isEmpty) {
      return other;
    }
    if (other.isEmpty) {
      return this;
    }
    if (_root.height < other._root.height) {
      final (large, leftover) = _appendLarge(_root, other._root);
      return SumTree._(
        ops,
        leftover == null ? large : _fromChildTrees(leftover, large),
      );
    }
    final (node, split) = _pushTreeRecursive(_root, other._root);
    return SumTree._(ops, split == null ? node : _fromChildTrees(node, split));
  }

  /// [node] with [other], which is no taller, after it; and the node that is
  /// to follow it when the two do not fit in one
  (_Node<T, S>, _Node<T, S>?) _pushTreeRecursive(
    _Node<T, S> node,
    _Node<T, S> other,
  ) {
    switch (node) {
      case _Internal<T, S>():
        final summaries = List.of(node.childSummaries);
        final trees = List.of(node.childTrees);
        final heightDelta = node.height - other.height;
        if (heightDelta == 0) {
          final o = other as _Internal<T, S>;
          summaries.addAll(o.childSummaries);
          trees.addAll(o.childTrees);
        } else if (heightDelta == 1 && !_isUnderflowing(other)) {
          summaries.add(other.summary);
          trees.add(other);
        } else {
          final (last, split) = _pushTreeRecursive(trees.last, other);
          trees[trees.length - 1] = last;
          summaries[summaries.length - 1] = last.summary;
          if (split != null) {
            summaries.add(split.summary);
            trees.add(split);
          }
        }
        final count = trees.length;
        if (count > 2 * treeBase) {
          final midpoint = (count + count % 2) ~/ 2;
          return (
            _internalWith(
              node.height,
              summaries.sublist(0, midpoint),
              trees.sublist(0, midpoint),
            ),
            _internalWith(
              node.height,
              summaries.sublist(midpoint),
              trees.sublist(midpoint),
            ),
          );
        }
        return (_internalWith(node.height, summaries, trees), null);
      case _Leaf<T, S>():
        final o = other as _Leaf<T, S>;
        final items = [...node.items, ...o.items];
        final summaries = [...node.itemSummaries, ...o.itemSummaries];
        final count = items.length;
        if (count > 2 * treeBase) {
          final midpoint = (count + count % 2) ~/ 2;
          return (
            _leafWith(
              items.sublist(0, midpoint),
              summaries.sublist(0, midpoint),
            ),
            _leafWith(items.sublist(midpoint), summaries.sublist(midpoint)),
          );
        }
        return (
          _Leaf(ops.add(node.summary, o.summary), items, summaries),
          null,
        );
    }
  }

  /// [large] with [small], which is no taller, before it; and the node that
  /// is to come before it when the two do not fit in one
  (_Node<T, S>, _Node<T, S>?) _appendLarge(
    _Node<T, S> small,
    _Node<T, S> large,
  ) {
    if (small.height == large.height) {
      return _isUnderflowing(small)
          ? _mergeIntoRight(small, large)
          : (large, small);
    }
    final l = large as _Internal<T, S>;
    final summaries = List.of(l.childSummaries);
    final trees = List.of(l.childTrees);
    final (first, leftover) = _appendLarge(small, trees.first);
    trees[0] = first;
    summaries[0] = first.summary;
    if (leftover == null) {
      return (_internalWith(l.height, summaries, trees), null);
    }
    if (trees.length < 2 * treeBase) {
      summaries.insert(0, leftover.summary);
      trees.insert(0, leftover);
      return (_internalWith(l.height, summaries, trees), null);
    }
    return (
      _internalWith(
        l.height,
        summaries.sublist(treeBase),
        trees.sublist(treeBase),
      ),
      _internalWith(
        l.height,
        [leftover.summary, ...summaries.sublist(0, treeBase)],
        [leftover, ...trees.sublist(0, treeBase)],
      ),
    );
  }

  /// [large] with what is in [small], of the same height, before its own; and
  /// a node of the first half when the two do not fit in one
  (_Node<T, S>, _Node<T, S>?) _mergeIntoRight(
    _Node<T, S> small,
    _Node<T, S> large,
  ) {
    switch ((small, large)) {
      case (_Internal<T, S> s, _Internal<T, S> l):
        final summaries = [...s.childSummaries, ...l.childSummaries];
        final trees = [...s.childTrees, ...l.childTrees];
        if (trees.length <= 2 * treeBase) {
          return (_internalWith(l.height, summaries, trees), null);
        }
        final midpoint = (trees.length + 1) ~/ 2;
        return (
          _internalWith(
            l.height,
            summaries.sublist(midpoint),
            trees.sublist(midpoint),
          ),
          _internalWith(
            l.height,
            summaries.sublist(0, midpoint),
            trees.sublist(0, midpoint),
          ),
        );
      case (_Leaf<T, S> s, _Leaf<T, S> l):
        final items = [...s.items, ...l.items];
        final summaries = [...s.itemSummaries, ...l.itemSummaries];
        if (items.length <= 2 * treeBase) {
          return (_Leaf(ops.add(s.summary, l.summary), items, summaries), null);
        }
        final midpoint = (items.length + 1) ~/ 2;
        return (
          _leafWith(items.sublist(midpoint), summaries.sublist(midpoint)),
          _leafWith(items.sublist(0, midpoint), summaries.sublist(0, midpoint)),
        );
      default:
        throw StateError('nodes of different heights');
    }
  }

  _Node<T, S> _fromChildTrees(_Node<T, S> left, _Node<T, S> right) =>
      _internalWith(
        left.height + 1,
        [left.summary, right.summary],
        [left, right],
      );

  _Node<T, S> _internalWith(
    int height,
    List<S> summaries,
    List<_Node<T, S>> trees,
  ) => _Internal(height, _sum(ops, summaries), summaries, trees);

  _Node<T, S> _leafWith(List<T> items, List<S> summaries) =>
      _Leaf(_sum(ops, summaries), items, summaries);

  static bool _isUnderflowing<T, S>(_Node<T, S> node) =>
      node.childSummaries.length < treeBase;

  static _Leaf<T, S> _leftmostLeaf<T, S>(_Node<T, S> node) {
    var n = node;
    while (n is _Internal<T, S>) {
      n = n.childTrees.first;
    }
    return n as _Leaf<T, S>;
  }

  static _Leaf<T, S> _rightmostLeaf<T, S>(_Node<T, S> node) {
    var n = node;
    while (n is _Internal<T, S>) {
      n = n.childTrees.last;
    }
    return n as _Leaf<T, S>;
  }

  static _Node<T, S> _internal<T, S>(
    SummaryOps<T, S> ops,
    int height,
    List<_Node<T, S>> children,
  ) {
    final summaries = [for (final child in children) child.summary];
    return _Internal(height, _sum(ops, summaries), summaries, children);
  }

  static S _sum<T, S>(SummaryOps<T, S> ops, List<S> summaries) {
    var sum = ops.zero;
    for (final summary in summaries) {
      sum = ops.add(sum, summary);
    }
    return sum;
  }
}

class _Entry<T, S, D> {
  _Entry(this.tree, this.index, this.position);

  final _Node<T, S> tree;
  int index;
  D position;
}

/// what a seek gathers of what it goes over
abstract class _Aggregate<T, S> {
  void endLeaf();
  void pushItem(T item, S summary);
  void pushTree(_Node<T, S> tree, S summary);
}

class _SliceAggregate<T, S> implements _Aggregate<T, S> {
  _SliceAggregate(this.tree);

  SumTree<T, S> tree;
  List<T> _items = [];
  List<S> _summaries = [];

  @override
  void endLeaf() {
    if (_items.isEmpty) {
      return;
    }
    final ops = tree.ops;
    tree = tree.append(
      SumTree._(ops, _Leaf(SumTree._sum(ops, _summaries), _items, _summaries)),
    );
    _items = [];
    _summaries = [];
  }

  @override
  void pushItem(T item, S summary) {
    _items.add(item);
    _summaries.add(summary);
  }

  @override
  void pushTree(_Node<T, S> node, S summary) {
    tree = tree.append(SumTree._(tree.ops, node));
  }
}

class _SummaryAggregate<T, S, O> implements _Aggregate<T, S> {
  _SummaryAggregate(this.dimension) : value = dimension.zero;

  final Dimension<S, O> dimension;
  O value;

  @override
  void endLeaf() {}

  @override
  void pushItem(T item, S summary) => value = dimension.add(value, summary);

  @override
  void pushTree(_Node<T, S> tree, S summary) =>
      value = dimension.add(value, summary);
}

/// a place in a tree, between two items, with how far it is in the dimension
/// [D]. it moves forward by seeking, and to the items next to it.
class Cursor<T, S, D> {
  Cursor._(this.tree, this.dimension)
    : _position = dimension.zero,
      _atEnd = tree.isEmpty;

  final SumTree<T, S> tree;
  final Dimension<S, D> dimension;
  final List<_Entry<T, S, D>> _stack = [];
  D _position;
  bool _didSeek = false;
  bool _atEnd;

  void reset() {
    _didSeek = false;
    _atEnd = tree.isEmpty;
    _stack.clear();
    _position = dimension.zero;
  }

  bool get didSeek => _didSeek;

  /// where the item the cursor is at starts
  D get start => _position;

  /// where the item the cursor is at ends, or [start] when it is at none
  D get end {
    final summary = itemSummary;
    return summary == null ? _position : dimension.add(_position, summary);
  }

  /// the item the cursor is at, which is none at the end of the tree
  T? get item {
    _assertDidSeek();
    if (_stack.isEmpty) {
      return null;
    }
    final entry = _stack.last;
    final leaf = entry.tree as _Leaf<T, S>;
    return entry.index == leaf.items.length ? null : leaf.items[entry.index];
  }

  S? get itemSummary {
    _assertDidSeek();
    if (_stack.isEmpty) {
      return null;
    }
    final entry = _stack.last;
    final leaf = entry.tree as _Leaf<T, S>;
    return entry.index == leaf.itemSummaries.length
        ? null
        : leaf.itemSummaries[entry.index];
  }

  T? get nextItem {
    _assertDidSeek();
    if (_stack.isNotEmpty) {
      final entry = _stack.last;
      final leaf = entry.tree as _Leaf<T, S>;
      if (entry.index >= leaf.items.length - 1) {
        return _nextLeaf()?.items.first;
      }
      return leaf.items[entry.index + 1];
    }
    return _atEnd ? null : tree.first;
  }

  _Leaf<T, S>? _nextLeaf() {
    for (var i = _stack.length - 2; i >= 0; i--) {
      final entry = _stack[i];
      final node = entry.tree as _Internal<T, S>;
      if (entry.index < node.childTrees.length - 1) {
        return SumTree._leftmostLeaf(node.childTrees[entry.index + 1]);
      }
    }
    return null;
  }

  T? get prevItem {
    _assertDidSeek();
    if (_stack.isNotEmpty) {
      final entry = _stack.last;
      if (entry.index == 0) {
        return _prevLeaf()?.items.last;
      }
      return (entry.tree as _Leaf<T, S>).items[entry.index - 1];
    }
    return _atEnd ? tree.last : null;
  }

  _Leaf<T, S>? _prevLeaf() {
    for (var i = _stack.length - 2; i >= 0; i--) {
      final entry = _stack[i];
      if (entry.index != 0) {
        final node = entry.tree as _Internal<T, S>;
        return SumTree._rightmostLeaf(node.childTrees[entry.index - 1]);
      }
    }
    return null;
  }

  void prev() => _searchBackward((_) => true);

  void _searchBackward(bool Function(S summary) filter) {
    if (!_didSeek) {
      _didSeek = true;
      _atEnd = true;
    }
    if (_atEnd) {
      _position = dimension.zero;
      _atEnd = tree.isEmpty;
      if (!tree.isEmpty) {
        _stack.add(
          _Entry(
            tree._root,
            tree._root.childSummaries.length,
            dimension.add(dimension.zero, tree.summary),
          ),
        );
      }
    }
    var descending = false;
    while (_stack.isNotEmpty) {
      _position = _stack.length >= 2
          ? _stack[_stack.length - 2].position
          : dimension.zero;
      final entry = _stack.last;
      if (!descending) {
        if (entry.index == 0) {
          _stack.removeLast();
          continue;
        }
        entry.index--;
      }
      final summaries = entry.tree.childSummaries;
      for (var i = 0; i < entry.index; i++) {
        _position = dimension.add(_position, summaries[i]);
      }
      entry.position = _position;
      descending = filter(summaries[entry.index]);
      final node = entry.tree;
      if (node is _Internal<T, S>) {
        if (descending) {
          final child = node.childTrees[entry.index];
          _stack.add(
            _Entry(child, child.childSummaries.length - 1, dimension.zero),
          );
        }
      } else if (descending) {
        break;
      }
    }
  }

  void next() => _searchForward((_) => true);

  void _searchForward(bool Function(S summary) filter) {
    var descend = false;
    if (_stack.isEmpty) {
      if (!_atEnd) {
        _stack.add(_Entry(tree._root, 0, dimension.zero));
        descend = true;
      }
      _didSeek = true;
    }
    while (_stack.isNotEmpty) {
      final entry = _stack.last;
      final node = entry.tree;
      _Node<T, S>? subtree;
      switch (node) {
        case _Internal<T, S>():
          if (!descend) {
            entry.index++;
            entry.position = _position;
          }
          while (entry.index < node.childSummaries.length) {
            final summary = node.childSummaries[entry.index];
            if (filter(summary)) {
              break;
            }
            entry.index++;
            entry.position = dimension.add(entry.position, summary);
            _position = dimension.add(_position, summary);
          }
          subtree = entry.index < node.childTrees.length
              ? node.childTrees[entry.index]
              : null;
        case _Leaf<T, S>():
          if (!descend) {
            final summary = node.itemSummaries[entry.index];
            entry.index++;
            entry.position = dimension.add(entry.position, summary);
            _position = dimension.add(_position, summary);
          }
          while (entry.index < node.itemSummaries.length) {
            final summary = node.itemSummaries[entry.index];
            if (filter(summary)) {
              return;
            }
            entry.index++;
            entry.position = dimension.add(entry.position, summary);
            _position = dimension.add(_position, summary);
          }
      }
      if (subtree != null) {
        descend = true;
        _stack.add(_Entry(subtree, 0, _position));
      } else {
        descend = false;
        _stack.removeLast();
      }
    }
    _atEnd = _stack.isEmpty;
  }

  /// moves to [target] from the start of the tree, and says whether an item
  /// starts or ends just there. with [Bias.left] the cursor stops at the first
  /// item that ends at or after the target, and with [Bias.right] at the first
  /// that ends after it.
  bool seek(SeekTarget<D> target, Bias bias) {
    reset();
    return _seekInternal(target, bias, null);
  }

  /// [seek] from where the cursor is, which the target may not be before
  bool seekForward(SeekTarget<D> target, Bias bias) =>
      _seekInternal(target, bias, null);

  /// moves to [end], and gives the items gone over as a tree
  SumTree<T, S> slice(SeekTarget<D> end, Bias bias) {
    final aggregate = _SliceAggregate<T, S>(SumTree(tree.ops));
    _seekInternal(end, bias, aggregate);
    return aggregate.tree;
  }

  /// moves to the end, and gives the items gone over as a tree
  SumTree<T, S> suffix() => slice((_) => 1, Bias.right);

  /// moves to [end], and gives how far that was in [output]
  O summary<O>(Dimension<S, O> output, SeekTarget<D> end, Bias bias) {
    final aggregate = _SummaryAggregate<T, S, O>(output);
    _seekInternal(end, bias, aggregate);
    return aggregate.value;
  }

  bool _seekInternal(
    SeekTarget<D> target,
    Bias bias,
    _Aggregate<T, S>? aggregate,
  ) {
    assert(target(_position) >= 0, 'cannot seek backward');
    if (!_didSeek) {
      _didSeek = true;
      _stack.add(_Entry(tree._root, 0, dimension.zero));
    }
    var ascending = false;
    outer:
    while (_stack.isNotEmpty) {
      final entry = _stack.last;
      final node = entry.tree;
      switch (node) {
        case _Internal<T, S>():
          if (ascending) {
            entry.index++;
            entry.position = _position;
          }
          while (entry.index < node.childTrees.length) {
            final summary = node.childSummaries[entry.index];
            final childEnd = dimension.add(_position, summary);
            final comparison = target(childEnd);
            if (comparison > 0 || (comparison == 0 && bias == Bias.right)) {
              _position = childEnd;
              aggregate?.pushTree(node.childTrees[entry.index], summary);
              entry.index++;
              entry.position = _position;
            } else {
              _stack.add(_Entry(node.childTrees[entry.index], 0, _position));
              ascending = false;
              continue outer;
            }
          }
        case _Leaf<T, S>():
          while (entry.index < node.items.length) {
            final summary = node.itemSummaries[entry.index];
            final childEnd = dimension.add(_position, summary);
            final comparison = target(childEnd);
            if (comparison > 0 || (comparison == 0 && bias == Bias.right)) {
              _position = childEnd;
              aggregate?.pushItem(node.items[entry.index], summary);
              entry.index++;
            } else {
              aggregate?.endLeaf();
              break outer;
            }
          }
          aggregate?.endLeaf();
      }
      _stack.removeLast();
      ascending = true;
    }
    _atEnd = _stack.isEmpty;
    var end = _position;
    if (bias == Bias.left) {
      final summary = itemSummary;
      if (summary != null) {
        end = dimension.add(end, summary);
      }
    }
    return target(end) == 0;
  }

  void _assertDidSeek() {
    assert(_didSeek, 'seek, next or prev comes before this');
  }
}

/// a cursor that goes over only the items that a filter lets through
class FilterCursor<T, S, D> {
  FilterCursor._(this._cursor, this._filter);

  final Cursor<T, S, D> _cursor;
  final bool Function(S summary) _filter;

  D get start => _cursor.start;
  D get end => _cursor.end;
  T? get item => _cursor.item;
  S? get itemSummary => _cursor.itemSummary;

  void next() => _cursor._searchForward(_filter);
  void prev() => _cursor._searchBackward(_filter);
}
