import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'device_pixels.dart';
import 'direct_write.dart';
import 'skinnable_icon.dart';

/// how bright [color] is to the eye, by the weights that the correction below
/// uses: 0 for black, and 1 for white
double colorBrightness(Color color) =>
    0.30 * color.r + 0.59 * color.g + 0.11 * color.b;

/// the table of the gamma ratios, from gamma 1.0 to 2.2 in steps of a tenth,
/// each as four numbers that are divided by four
const _gammaTable = <List<double>>[
  [0.0000, 0.0000, 0.0000, 0.0000],
  [0.0166, -0.0807, 0.2227, -0.0751],
  [0.0350, -0.1760, 0.4325, -0.1370],
  [0.0543, -0.2821, 0.6302, -0.1876],
  [0.0739, -0.3963, 0.8167, -0.2287],
  [0.0933, -0.5161, 0.9926, -0.2616],
  [0.1121, -0.6395, 1.1588, -0.2877],
  [0.1300, -0.7649, 1.3159, -0.3080],
  [0.1469, -0.8911, 1.4644, -0.3234],
  [0.1627, -1.0170, 1.6051, -0.3347],
  [0.1773, -1.1420, 1.7385, -0.3426],
  [0.1908, -1.2652, 1.8650, -0.3476],
  [0.2031, -1.3864, 1.9851, -0.3501],
];

List<double> _gammaRatios(double gamma) {
  const norm13 = 65536 / (255 * 255) * 4;
  const norm24 = 256 / 255 * 4;
  final index = ((gamma * 10).round().clamp(10, 22)) - 10;
  final r = _gammaTable[index];
  return [
    r[0] / 4 * norm13,
    r[1] / 4 * norm24,
    r[2] / 4 * norm13,
    r[3] / 4 * norm24,
  ];
}

/// what a pixel that is covered by [coverage] of an icon that is [brightness]
/// bright is drawn with, once the contrast and the gamma of the screen are
/// taken into account. this is the correction that the text renderer of Windows
/// puts on the coverage of text, and that an icon is given too, for the edges:
/// they come out a little more covered when the icon is light, which makes them
/// softer.
double correctCoverage(
  double coverage,
  double brightness, {
  double gamma = 1.8,
  double enhancedContrast = 1.0,
}) {
  final multiplier = (4 * (0.75 - brightness)).clamp(0.0, 1.0);
  final k = enhancedContrast * multiplier;
  final contrasted = coverage * (k + 1) / (coverage * k + 1);
  final g = _gammaRatios(gamma);
  final adjustment = g[0] * brightness + g[1];
  final correction = adjustment * contrasted + (g[2] * brightness + g[3]);
  return contrasted + contrasted * (1 - contrasted) * correction;
}

/// the numbers of device pixels that the box of an icon of [size] logical
/// pixels can come to on a screen of [ratio] device pixels to a logical one:
/// its two edges are each put on a pixel, so it is the one below its size on
/// the screen or the one above it, or just the size when that is a whole number
Set<int> iconSides(double size, double ratio) {
  final exact = size * ratio;
  return {math.max(1, exact.floor()), math.max(1, exact.ceil())};
}

/// an icon that is an svg, the bundled ones and those that the theme has files
/// for, drawn with the correction of the edges above, which makes them soft.
/// the plain icon is shown until the corrected one is ready, and when it cannot
/// be made.
///
/// the icon is made for each number of device pixels that its box can have on
/// the screen, which is one of two when it does not come to a whole number, as
/// the two edges of the box are each put on a pixel; [SnappedImage] has the one
/// that fits where the box is
class GammaIcon extends StatefulWidget {
  const GammaIcon({
    super.key,
    required this.name,
    required this.size,
    required this.color,
  });

  final String name;
  final double size;
  final Color color;

  @override
  State<GammaIcon> createState() => _GammaIconState();
}

class _GammaIconState extends State<GammaIcon> {
  static final _cache = <String, ui.Image>{};

  Map<int, ui.Image>? _images;
  String? _key;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(GammaIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    unawaited(_load());
  }

  Future<void> _load() async {
    // the file that the theme has for the icon, which is drawn here when it is
    // an svg, and as it is when it is an image
    final file = SkinnableIcon.skinFile(widget.name);
    if (file != null && !SkinnableIcon.skinIsSvg(widget.name)) {
      return;
    }
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final sides = iconSides(widget.size, ratio).toList()..sort();
    final brightness = colorBrightness(widget.color);
    final bundled = widget.size >= 32 ? 32 : (widget.size >= 22 ? 22 : 16);
    // a file that is changed, or put in its place, is read again
    String source;
    if (file == null) {
      source = '$bundled';
    } else {
      try {
        source =
            '${file.path}@${file.lastModifiedSync().millisecondsSinceEpoch}'
            '/${file.lengthSync()}';
      } on FileSystemException {
        return;
      }
    }
    final prefix = '${widget.name}|$source|${brightness.toStringAsFixed(3)}';
    final key = '$prefix|${sides.join(',')}';
    if (key == _key) {
      return;
    }
    _key = key;
    final cached = {
      for (final side in sides)
        if (_cache['$prefix|$side'] != null) side: _cache['$prefix|$side']!,
    };
    if (cached.length == sides.length) {
      setState(() => _images = cached);
      return;
    }
    try {
      const theme = SvgTheme(currentColor: Color(0xFF000000));
      final BytesLoader loader = file == null
          ? SvgAssetLoader(
              'assets/icons/${widget.name}/${widget.name}-$bundled.svg',
              theme: theme,
            )
          // the text, and not the file: the loader of a file is kept by its
          // name, and would give the old drawing for a file that was changed
          : SvgStringLoader(await file.readAsString(), theme: theme);
      final info = await vg.loadPicture(loader, null);
      final made = <int, ui.Image>{};
      for (final side in sides) {
        final image = await _make(info, side, brightness);
        if (image == null) {
          return;
        }
        _cache['$prefix|$side'] = image;
        made[side] = image;
      }
      if (mounted && _key == key) {
        setState(() => _images = made);
      }
    } on Object {
      // the plain icon stays
    }
  }

  /// the icon of [pixels] by [pixels] device pixels: its mask is drawn at twice
  /// that, and each pixel is the mean of four of it, which is what the screen
  /// does by sampling between them, and the correction is put on that
  static Future<ui.Image?> _make(
    PictureInfo info,
    int pixels,
    double brightness,
  ) async {
    const smooth = 2;
    final large = pixels * smooth;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // the drawing is scaled by its width, in both directions
    final scale = large / info.size.width;
    canvas.scale(scale, scale);
    canvas.drawPicture(info.picture);
    final raw = await recorder.endRecording().toImage(large, large);
    final data = await raw.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    raw.dispose();
    if (data == null) {
      return null;
    }
    final bytes = data.buffer.asUint8List();
    final corrected = Uint8List(pixels * pixels * 4);
    // the gamma and the contrast that the system draws text with
    final rendering = TextRendering.system;
    for (var i = 0; i < corrected.length; i += 4) {
      final x = (i ~/ 4) % pixels;
      final y = (i ~/ 4) ~/ pixels;
      // the sample at the corner of four texels of the mask is their mean
      var sum = 0;
      for (var dy = 0; dy < smooth; dy++) {
        for (var dx = 0; dx < smooth; dx++) {
          final texel = (y * smooth + dy) * large + x * smooth + dx;
          sum += bytes[texel * 4 + 3];
        }
      }
      final coverage = sum / (smooth * smooth * 255);
      final alpha =
          (correctCoverage(
                    coverage,
                    brightness,
                    gamma: rendering.gamma,
                    enhancedContrast: rendering.grayscaleContrast,
                  ) *
                  255)
              .round()
              .clamp(0, 255);
      // white, as much as is covered: the color is put on when it is drawn
      corrected[i] = alpha;
      corrected[i + 1] = alpha;
      corrected[i + 2] = alpha;
      corrected[i + 3] = alpha;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      corrected,
      pixels,
      pixels,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final images = _images;
    // the plain icon is drawn until the corrected one is ready, and for an
    // image of the theme's own, which is not corrected
    final file = SkinnableIcon.skinFile(widget.name);
    if (images == null ||
        (file != null && !SkinnableIcon.skinIsSvg(widget.name))) {
      return SkinnableIcon(
        name: widget.name,
        size: widget.size,
        color: widget.color,
        plain: true,
      );
    }
    return SnappedImage(
      images: images,
      size: widget.size,
      color: widget.color,
      ratio: MediaQuery.devicePixelRatioOf(context),
    );
  }
}

/// an icon of whole device pixels, drawn on the pixels of the screen without
/// being scaled, the colors being its alpha in [color].
///
/// the box of the icon has its edges each on the pixel that it is nearest to,
/// and the icon is as many pixels as the box is wide, which is one of the
/// numbers that [images] has, by its side in pixels. it is square, as high as
/// it is wide, in the middle of the height of the box, and on the pixel nearest
/// to where that puts it. where the box is turned over it is turned over, and
/// where it is turned any other way, or scaled, it is drawn into the box
class SnappedImage extends LeafRenderObjectWidget {
  const SnappedImage({
    super.key,
    required this.images,
    required this.size,
    required this.color,
    required this.ratio,
  });

  /// the icon for each side in device pixels that it can have
  final Map<int, ui.Image> images;

  /// the side of the box, in logical pixels
  final double size;
  final Color color;
  final double ratio;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderSnappedImage(images, size, color, ratio);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSnappedImage renderObject,
  ) {
    renderObject
      ..images = images
      ..side = size
      ..color = color
      ..ratio = ratio;
  }
}

/// the render object of [SnappedImage]
class RenderSnappedImage extends RenderBox {
  RenderSnappedImage(this._images, this._side, this._color, this._ratio);

  Map<int, ui.Image> _images;
  double _side;
  Color _color;
  double _ratio;

  set images(Map<int, ui.Image> value) {
    if (identical(value, _images)) {
      return;
    }
    _images = value;
    markNeedsPaint();
  }

  set side(double value) {
    if (value == _side) {
      return;
    }
    _side = value;
    markNeedsLayout();
  }

  set color(Color value) {
    if (value == _color) {
      return;
    }
    _color = value;
    markNeedsPaint();
  }

  set ratio(double value) {
    if (value == _ratio) {
      return;
    }
    _ratio = value;
    markNeedsPaint();
  }

  @override
  void performLayout() {
    size = constraints.constrain(Size.square(_side));
  }

  /// the image for [side] device pixels, or the one nearest to it
  ui.Image _imageFor(int side) {
    final exact = _images[side];
    if (exact != null) {
      return exact;
    }
    final sides = _images.keys.toList()
      ..sort((a, b) => (a - side).abs().compareTo((b - side).abs()));
    return _images[sides.first]!;
  }

  /// where the box is on the window, and the sprite that goes in it, in
  /// device pixels: the corners of the box are put on pixels, the sprite is as
  /// wide as that, square, and in the middle of the height, put on the pixel
  /// nearest to that. null when the box is turned or scaled, which a pixel does
  /// not fit
  ({Rect box, Rect sprite})? snapped(Matrix4 toWindow) {
    final m = toWindow.storage;
    final upright =
        m[1] == 0 &&
        m[4] == 0 &&
        m[2] == 0 &&
        m[6] == 0 &&
        m[8] == 0 &&
        m[9] == 0 &&
        m[10] == 1 &&
        (m[0].abs() - 1).abs() < 1e-9 &&
        (m[5].abs() - 1).abs() < 1e-9;
    if (!upright) {
      return null;
    }
    final window = MatrixUtils.transformRect(toWindow, Offset.zero & size);
    final left = roundToDevicePixel(window.left, _ratio);
    final top = roundToDevicePixel(window.top, _ratio);
    final right = math.max(left, roundToDevicePixel(window.right, _ratio));
    final bottom = math.max(top, roundToDevicePixel(window.bottom, _ratio));
    final side = right - left;
    final spriteTop = roundHalfTowardZero(top + ((bottom - top) - side) / 2);
    return (
      box: Rect.fromLTRB(left, top, right, bottom),
      sprite: Rect.fromLTWH(left, spriteTop, side, side),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final paint = Paint()
      ..colorFilter = ColorFilter.mode(_color, BlendMode.srcIn);
    final toWindow = getTransformTo(null);
    final snap = snapped(toWindow);
    if (snap == null) {
      // the image nearest to the size, into the box
      final image = _imageFor((_side * _ratio).round());
      paint.filterQuality = FilterQuality.low;
      context.canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        offset & size,
        paint,
      );
      return;
    }
    final side = snap.sprite.width.toInt();
    if (side <= 0) {
      return;
    }
    final image = _imageFor(side);
    // the sprite, which is on pixels of the window, in the places of the box:
    // the box is on the window by [toWindow], which only moves it and turns it
    // over, and that is undone for the sprite
    final inverse = Matrix4.copy(toWindow)..invert();
    final inBox = MatrixUtils.transformRect(
      inverse,
      Rect.fromLTWH(
        snap.sprite.left / _ratio,
        snap.sprite.top / _ratio,
        snap.sprite.width / _ratio,
        snap.sprite.height / _ratio,
      ),
    );
    paint.filterQuality = FilterQuality.none;
    context.canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      inBox.shift(offset),
      paint,
    );
  }
}
