/// the most one part of a locator can be
const int _maxPart = 0x7FFFFFFFFFFFFFFF;

/// where something is in an ordered collection. one can always be made that
/// is between two others, so that things are put in before and after without
/// the ones that are there being numbered again.
class Locator implements Comparable<Locator> {
  const Locator._(this._parts);

  /// before every other
  static const min = Locator._([0]);

  /// after every other
  static const max = Locator._([_maxPart]);

  final List<int> _parts;

  int get length => _parts.length;

  /// a locator that is after [lhs] and before [rhs]
  static Locator between(Locator lhs, Locator rhs) {
    final parts = <int>[];
    for (var i = 0; ; i++) {
      final l = i < lhs._parts.length ? lhs._parts[i] : 0;
      final r = i < rhs._parts.length ? rhs._parts[i] : _maxPart;
      // the shift keeps what is typed in order near the left one, so that a
      // long run of typing does not make the locators long
      final mid = l + ((r > l ? r - l : 0) >> 47);
      parts.add(mid);
      if (mid > l) {
        break;
      }
    }
    return Locator._(parts);
  }

  @override
  int compareTo(Locator other) {
    final a = _parts;
    final b = other._parts;
    final shared = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < shared; i++) {
      if (a[i] != b[i]) {
        return a[i] < b[i] ? -1 : 1;
      }
    }
    return a.length.compareTo(b.length);
  }

  bool operator <(Locator other) => compareTo(other) < 0;
  bool operator <=(Locator other) => compareTo(other) <= 0;
  bool operator >(Locator other) => compareTo(other) > 0;
  bool operator >=(Locator other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) => other is Locator && compareTo(other) == 0;

  @override
  int get hashCode => Object.hashAll(_parts);

  @override
  String toString() => 'Locator($_parts)';
}
