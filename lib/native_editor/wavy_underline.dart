import 'dart:math' as math;
import 'dart:ui';

/// the center line of a wavy underline of [width], with its left edge at the
/// origin and its bounds three times as high as the stroke: a sine of
/// 0.8 strokes in height, as long as nine strokes
Path wavyUnderlinePath(double width, {double thickness = 1}) {
  final center = thickness * 1.5;
  final amplitude = thickness * 0.8;
  final period = thickness * 9;
  double y(double x) => center + amplitude * math.sin(2 * math.pi * x / period);
  final path = Path()..moveTo(0, y(0));
  var x = 0.5;
  for (; x < width; x += 0.5) {
    path.lineTo(x, y(x));
  }
  return path..lineTo(width, y(width));
}

/// paints a wavy underline of [width] whose bounds start at [origin]
void paintWavyUnderline(
  Canvas canvas,
  Offset origin,
  double width,
  Color color, {
  double thickness = 1,
}) {
  if (width <= 0) {
    return;
  }
  canvas.save();
  canvas.translate(origin.dx, origin.dy);
  canvas.clipRect(Rect.fromLTWH(0, 0, width, thickness * 3));
  canvas.drawPath(
    wavyUnderlinePath(width, thickness: thickness),
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true,
  );
  canvas.restore();
}
