import 'patch.dart' show Bias;

/// the greatest time and offset, which only the anchor of the end has
const int anchorMax = 0x7FFFFFFFFFFFFFFF;

/// a place in a buffer that stays with the text it was made at as the buffer
/// is edited. it names the insertion that put the text there by its time, and
/// how far into what was inserted the place is; a buffer snapshot says where
/// that is at any later time.
class Anchor {
  const Anchor(this.timestamp, this.offset, this.bias);

  /// the start of the buffer, whatever is put there
  static const min = Anchor(0, 0, Bias.left);

  /// the end of the buffer, whatever is put there
  static const max = Anchor(anchorMax, anchorMax, Bias.right);

  /// the time of the insertion that the anchor is in the text of
  final int timestamp;

  /// how far into the text of that insertion the anchor is
  final int offset;

  /// whether the anchor stays with the character before it or the one after
  final Bias bias;

  bool get isMin => timestamp == 0 && offset == 0 && bias == Bias.left;

  bool get isMax =>
      timestamp == anchorMax && offset == anchorMax && bias == Bias.right;

  @override
  bool operator ==(Object other) =>
      other is Anchor &&
      other.timestamp == timestamp &&
      other.offset == offset &&
      other.bias == bias;

  @override
  int get hashCode => Object.hash(timestamp, offset, bias);

  @override
  String toString() {
    if (isMin) {
      return 'Anchor.min';
    }
    if (isMax) {
      return 'Anchor.max';
    }
    return 'Anchor($timestamp, $offset, ${bias.name})';
  }
}

/// two anchors, the first of which is not after the second
class AnchorRange {
  const AnchorRange(this.start, this.end);

  final Anchor start;
  final Anchor end;

  @override
  bool operator ==(Object other) =>
      other is AnchorRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '$start..$end';
}
