import 'dart:math' as math;

/// [value] to the nearest whole number, with the middle between two going to
/// the one nearer to zero
double roundHalfTowardZero(double value) {
  final rounded = (value.abs() - 0.5).ceilToDouble();
  return value < 0 ? -rounded : rounded;
}

/// the device pixel that a logical [value] is at, on a screen of [ratio] device
/// pixels for each logical one
double roundToDevicePixel(double value, double ratio) =>
    roundHalfTowardZero(value * ratio);

/// how many device pixels a stroke of [logical] pixels is: a whole number, and
/// not less than one unless it is none, so that a thin line does not go away
double snapStroke(double logical, double ratio) => logical == 0
    ? 0
    : math.max(1.0, roundToDevicePixel(math.max(0.0, logical), ratio));
