/// a place in a text by line and column, both counted from 0. columns count
/// UTF-16 code units, which is how Dart strings and language servers count
class Point implements Comparable<Point> {
  const Point(this.row, this.column);

  static const zero = Point(0, 0);

  final int row;
  final int column;

  @override
  int compareTo(Point other) {
    final byRow = row.compareTo(other.row);
    return byRow != 0 ? byRow : column.compareTo(other.column);
  }

  bool operator <(Point other) => compareTo(other) < 0;
  bool operator <=(Point other) => compareTo(other) <= 0;
  bool operator >(Point other) => compareTo(other) > 0;
  bool operator >=(Point other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is Point && other.row == row && other.column == column;

  @override
  int get hashCode => Object.hash(row, column);

  @override
  String toString() => 'Point($row, $column)';
}
