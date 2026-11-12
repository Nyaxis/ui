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
/// taken into account. this is the correction that the renderer of Zed puts on
/// the coverage of text and icons on Windows, for the edges of what is drawn:
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

/// an icon of the bundled ones, drawn with the correction of the edges above,
/// which makes it look as it does in Zed. the plain icon is shown until the
/// corrected one is ready, and when it cannot be made, and an icon that the
/// theme has its own file for is left as the theme has it.
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

  ui.Image? _image;
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
    // the box of the icon on the screen is of whole device pixels
    final pixels = math.max(1, roundToDevicePixel(widget.size, ratio).toInt());
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
    final key =
        '${widget.name}|$source|$pixels|${brightness.toStringAsFixed(3)}';
    if (key == _key) {
      return;
    }
    _key = key;
    final cached = _cache[key];
    if (cached != null) {
      setState(() => _image = cached);
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
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      // Zed draws the mask of an icon at twice its size and has the screen
      // take it down by sampling, which is what makes the edges soft
      const smooth = 2;
      final large = pixels * smooth;
      canvas.scale(large / info.size.width, large / info.size.height);
      canvas.drawPicture(info.picture);
      final raw = await recorder.endRecording().toImage(large, large);
      final data = await raw.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      raw.dispose();
      if (data == null) {
        return;
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
      final image = await completer.future;
      _cache[key] = image;
      if (mounted && _key == key) {
        setState(() => _image = image);
      }
    } on Object {
      // the plain icon stays
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    // the plain icon is drawn until the corrected one is ready, and for an
    // image of the theme's own, which is not corrected
    final file = SkinnableIcon.skinFile(widget.name);
    if (image == null ||
        (file != null && !SkinnableIcon.skinIsSvg(widget.name))) {
      return SkinnableIcon(
        name: widget.name,
        size: widget.size,
        color: widget.color,
        plain: true,
      );
    }
    return SnappedImage(
      image: image,
      size: widget.size,
      color: widget.color,
      ratio: MediaQuery.devicePixelRatioOf(context),
    );
  }
}

/// an image of whole device pixels, drawn on the pixels of the screen without
/// being scaled, with its corner on the pixel that the corner of its box is
/// nearest to; the colors are its alpha, in [color]. where it is turned over, or
/// not on the screen as it is, it is drawn into its box
class SnappedImage extends LeafRenderObjectWidget {
  const SnappedImage({
    super.key,
    required this.image,
    required this.size,
    required this.color,
    required this.ratio,
  });

  final ui.Image image;

  /// the side of the box, in logical pixels
  final double size;
  final Color color;
  final double ratio;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderSnappedImage(image, size, color, ratio);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSnappedImage renderObject,
  ) {
    renderObject
      ..image = image
      ..side = size
      ..color = color
      ..ratio = ratio;
  }
}

/// the render object of [SnappedImage]
class RenderSnappedImage extends RenderBox {
  RenderSnappedImage(this._image, this._side, this._color, this._ratio);

  ui.Image _image;
  double _side;
  Color _color;
  double _ratio;

  set image(ui.Image value) {
    if (identical(value, _image)) {
      return;
    }
    _image = value;
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

  @override
  void paint(PaintingContext context, Offset offset) {
    final source = Rect.fromLTWH(
      0,
      0,
      _image.width.toDouble(),
      _image.height.toDouble(),
    );
    final paint = Paint()
      ..colorFilter = ColorFilter.mode(_color, BlendMode.srcIn);
    final m = getTransformTo(null).storage;
    final moved =
        m[0] == 1 &&
        m[5] == 1 &&
        m[1] == 0 &&
        m[4] == 0 &&
        m[2] == 0 &&
        m[6] == 0;
    if (!moved) {
      paint.filterQuality = FilterQuality.low;
      context.canvas.drawImageRect(_image, source, offset & size, paint);
      return;
    }
    // the corner of the box is on the window at (m[12], m[13]); the sprite goes
    // to the pixel nearest to it, and is as many pixels as the image has
    final global = Offset(m[12], m[13]);
    final snapped = Offset(
      roundToDevicePixel(global.dx, _ratio) / _ratio,
      roundToDevicePixel(global.dy, _ratio) / _ratio,
    );
    final at = offset + (snapped - global);
    paint.filterQuality = FilterQuality.none;
    context.canvas.drawImageRect(
      _image,
      source,
      Rect.fromLTWH(
        at.dx,
        at.dy,
        _image.width / _ratio,
        _image.height / _ratio,
      ),
      paint,
    );
  }
}
