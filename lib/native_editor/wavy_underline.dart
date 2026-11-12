import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../ui/device_pixels.dart';

/// how much of each pixel a wavy underline covers, row by row, for a line that
/// is [width] device pixels long and [thickness] device pixels thick, in
/// bounds that are three times as high as it is thick.
///
/// each pixel is looked at in its middle, and the distance from there to the
/// edge of the stroke gives its coverage: all of it up to half a pixel inside,
/// and none from half a pixel outside. the stroke follows a sine as long as
/// nine strokes, which is 0.8 of a stroke high
Float64List wavyUnderlineCoverage(int width, int thickness) {
  const waveFrequency = 2.0;
  const waveHeightRatio = 0.8;
  final height = thickness * 3;
  final size = height.toDouble();
  final frequency = math.pi * waveFrequency * thickness / size;
  final amplitude = thickness * waveHeightRatio / size;
  final halfThickness = thickness * 0.5;
  final coverage = Float64List(width * height);
  for (var y = 0; y < height; y++) {
    final sy = (y + 0.5) / size - 0.5;
    for (var x = 0; x < width; x++) {
      final sx = (x + 0.5) / size;
      final sine = math.sin(sx * frequency) * amplitude;
      final slope = math.cos(sx * frequency) * amplitude * frequency;
      final distance = (sy - sine) / math.sqrt(1 + slope * slope) * size;
      final fromTop = distance - halfThickness;
      final fromBottom = distance + halfThickness;
      coverage[y * width + x] = (0.5 - math.max(-fromBottom, fromTop)).clamp(
        0.0,
        1.0,
      );
    }
  }
  return coverage;
}

/// the pictures of the underlines that were drawn, in device pixels; they are
/// the same for the same size and color, and are made again when too many
final Map<({int width, int thickness, int color}), Picture> _pictures = {};
const int _picturesKept = 256;

Picture _wavyPicture(int width, int thickness, Color color) {
  final key = (width: width, thickness: thickness, color: color.toARGB32());
  final kept = _pictures[key];
  if (kept != null) {
    return kept;
  }
  if (_pictures.length >= _picturesKept) {
    for (final picture in _pictures.values) {
      picture.dispose();
    }
    _pictures.clear();
  }
  final coverage = wavyUnderlineCoverage(width, thickness);
  final height = thickness * 3;
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()..isAntiAlias = false;
  for (var y = 0; y < height; y++) {
    // a run of pixels with the same coverage is one rectangle
    var x = 0;
    while (x < width) {
      final alpha = coverage[y * width + x];
      var end = x + 1;
      while (end < width && coverage[y * width + end] == alpha) {
        end++;
      }
      if (alpha > 0) {
        paint.color = color.withValues(alpha: color.a * alpha);
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), (end - x).toDouble(), 1),
          paint,
        );
      }
      x = end;
    }
  }
  return _pictures[key] = recorder.endRecording();
}

/// paints a wavy underline of [width] whose bounds start at [origin], as
/// whole device pixels: the start is put on a pixel, the thickness and the
/// width are whole numbers of them, and the wave is as long as nine thick.
///
/// [globalOrigin] is where the canvas has its origin on the window, and [ratio]
/// is how many device pixels a logical one is, which the places of pixels are
/// known by
void paintWavyUnderline(
  Canvas canvas,
  Offset origin,
  double width,
  Color color, {
  double thickness = 1,
  double ratio = 1,
  Offset globalOrigin = Offset.zero,
}) {
  if (width <= 0) {
    return;
  }
  final strokeWidth = snapStroke(width, ratio).toInt();
  final strokeThickness = snapStroke(thickness, ratio).toInt();
  if (strokeWidth <= 0 || strokeThickness <= 0) {
    return;
  }
  // the pixel that the start is on, and from there back to the canvas
  final startX = roundToDevicePixel(globalOrigin.dx + origin.dx, ratio);
  final startY = roundToDevicePixel(globalOrigin.dy + origin.dy, ratio);
  canvas.save();
  canvas.translate(
    startX / ratio - globalOrigin.dx,
    startY / ratio - globalOrigin.dy,
  );
  canvas.scale(1 / ratio);
  canvas.drawPicture(_wavyPicture(strokeWidth, strokeThickness, color));
  canvas.restore();
}
