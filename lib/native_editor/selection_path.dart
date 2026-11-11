import 'dart:math' as math;
import 'dart:ui';

/// the part of a row of the screen that a selection covers: from where it
/// starts to where it ends, as x positions
typedef SelectionLine = (double startX, double endX);

/// the shapes that cover [lines], one for each row from [startY] down, each
/// [lineHeight] high, with the corners rounded by [radius]. one shape when
/// they are joined, and two when the first row is after the end of the second
/// and the rows below, which leaves a gap between them.
List<Path> selectionPaths(
  double startY,
  List<SelectionLine> lines,
  double lineHeight,
  double radius,
) {
  if (lines.isEmpty) {
    return const [];
  }
  if (lines.length >= 2 && lines[0].$1 > lines[1].$2) {
    return [
      _shape(startY, lines.sublist(0, 1), lineHeight, radius),
      _shape(startY + lineHeight, lines.sublist(1), lineHeight, radius),
    ];
  }
  return [_shape(startY, lines, lineHeight, radius)];
}

Path _shape(
  double startY,
  List<SelectionLine> lines,
  double lineHeight,
  double radius,
) {
  final first = lines.first;
  final last = lines.last;
  final firstTopLeft = Offset(first.$1, startY);
  final firstTopRight = Offset(first.$2, startY);

  final curveHeight = Offset(0, radius);
  // how far along a corner goes, which is the radius, or half the way when
  // there is less room than that
  Offset curveWidth(double start, double end) =>
      Offset(math.min((end - start) / 2, radius), 0);

  final topCurveWidth = curveWidth(first.$1, first.$2);
  final path = Path();
  void curve(Offset control, Offset to) {
    if (radius > 0) {
      path.quadraticBezierTo(control.dx, control.dy, to.dx, to.dy);
    } else {
      path.lineTo(to.dx, to.dy);
    }
  }

  void line(Offset to) => path.lineTo(to.dx, to.dy);

  final start = firstTopRight - topCurveWidth;
  path.moveTo(start.dx, start.dy);
  curve(firstTopRight, firstTopRight + curveHeight);

  for (var i = 0; i < lines.length; i++) {
    final row = lines[i];
    final bottomRight = Offset(row.$2, startY + (i + 1) * lineHeight);
    if (i + 1 < lines.length) {
      final next = lines[i + 1];
      final nextTopRight = Offset(next.$2, bottomRight.dy);
      if (nextTopRight.dx == bottomRight.dx) {
        line(bottomRight);
      } else if (nextTopRight.dx < bottomRight.dx) {
        final width = curveWidth(nextTopRight.dx, bottomRight.dx);
        line(bottomRight - curveHeight);
        curve(bottomRight, bottomRight - width);
        line(nextTopRight + width);
        curve(nextTopRight, nextTopRight + curveHeight);
      } else {
        final width = curveWidth(bottomRight.dx, nextTopRight.dx);
        line(bottomRight - curveHeight);
        curve(bottomRight, bottomRight + width);
        line(nextTopRight - width);
        curve(nextTopRight, nextTopRight + curveHeight);
      }
    } else {
      final width = curveWidth(row.$1, row.$2);
      line(bottomRight - curveHeight);
      curve(bottomRight, bottomRight - width);
      final bottomLeft = Offset(row.$1, bottomRight.dy);
      line(bottomLeft + width);
      curve(bottomLeft, bottomLeft - curveHeight);
    }
  }

  if (first.$1 > last.$1) {
    final width = curveWidth(last.$1, first.$1);
    final secondTopLeft = Offset(last.$1, startY + lineHeight);
    line(secondTopLeft + curveHeight);
    curve(secondTopLeft, secondTopLeft + width);
    final firstBottomLeft = Offset(first.$1, secondTopLeft.dy);
    line(firstBottomLeft - width);
    curve(firstBottomLeft, firstBottomLeft - curveHeight);
  }

  line(firstTopLeft + curveHeight);
  curve(firstTopLeft, firstTopLeft + topCurveWidth);
  line(firstTopRight - topCurveWidth);
  path.close();
  return path;
}
