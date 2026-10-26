import 'dart:math';
import 'package:flutter/material.dart';

/// [ShapeBorder] whose corners follow a superellipse (Lamé curve) rather than
/// a circular arc; higher [power] values transition more smoothly into the
/// straight edges of the rectangle
class SuperellipseBorder extends ShapeBorder {
  const SuperellipseBorder({
    required this.radius,
    this.power = 2.0,
    this.side = BorderSide.none,
  });

  final double radius;

  /// 1.0 = chamfer, 2.0 = circle (default), 4.0 = squircle; clamped to [1, 10]
  final double power;

  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side == BorderSide.none) return;
    canvas.drawPath(_path(rect), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) => SuperellipseBorder(
    radius: radius * t,
    power: power,
    side: side.scale(t),
  );

  Path _path(Rect rect) {
    final r = radius.clamp(0.0, min(rect.width, rect.height) / 2);
    if (r == 0) return Path()..addRect(rect);

    final n = power.clamp(1.0, 10.0);
    const steps = 24;
    double se(double t) => pow(t, 2.0 / n).toDouble();

    final cxTl = rect.left + r,  cyTl = rect.top + r;
    final cxTr = rect.right - r, cyTr = rect.top + r;
    final cxBr = rect.right - r, cyBr = rect.bottom - r;
    final cxBl = rect.left + r,  cyBl = rect.bottom - r;

    final path = Path()..moveTo(cxTl, rect.top);

    path.lineTo(cxTr, rect.top);
    for (int i = 1; i <= steps; i++) {
      final t = i / steps * (pi / 2);
      path.lineTo(cxTr + r * se(sin(t)), cyTr - r * se(cos(t)));
    }

    path.lineTo(rect.right, cyBr);
    for (int i = 1; i <= steps; i++) {
      final t = i / steps * (pi / 2);
      path.lineTo(cxBr + r * se(cos(t)), cyBr + r * se(sin(t)));
    }

    path.lineTo(cxBl, rect.bottom);
    for (int i = 1; i <= steps; i++) {
      final t = i / steps * (pi / 2);
      path.lineTo(cxBl - r * se(sin(t)), cyBl + r * se(cos(t)));
    }

    path.lineTo(rect.left, cyTl);
    for (int i = 1; i <= steps; i++) {
      final t = i / steps * (pi / 2);
      path.lineTo(cxTl - r * se(cos(t)), cyTl - r * se(sin(t)));
    }

    return path..close();
  }
}
