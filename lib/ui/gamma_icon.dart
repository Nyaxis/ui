import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
    if (SkinnableIcon.hasSkin(widget.name)) {
      return;
    }
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final pixels = (widget.size * ratio).round();
    final brightness = colorBrightness(widget.color);
    final bundled = widget.size >= 32 ? 32 : (widget.size >= 22 ? 22 : 16);
    final key =
        '${widget.name}|$bundled|$pixels|${brightness.toStringAsFixed(3)}';
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
      final loader = SvgAssetLoader(
        'assets/icons/${widget.name}/${widget.name}-$bundled.svg',
        theme: const SvgTheme(currentColor: Color(0xFF000000)),
      );
      final info = await vg.loadPicture(loader, null);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(pixels / info.size.width, pixels / info.size.height);
      canvas.drawPicture(info.picture);
      final raw = await recorder.endRecording().toImage(pixels, pixels);
      final data = await raw.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      raw.dispose();
      if (data == null) {
        return;
      }
      final bytes = data.buffer.asUint8List();
      final corrected = Uint8List(bytes.length);
      for (var i = 0; i < bytes.length; i += 4) {
        final coverage = bytes[i + 3] / 255;
        final alpha = (correctCoverage(coverage, brightness) * 255)
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
    if (image == null || SkinnableIcon.hasSkin(widget.name)) {
      return SkinnableIcon(
        name: widget.name,
        size: widget.size,
        color: widget.color,
      );
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RawImage(
        image: image,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.fill,
        color: widget.color,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.low,
      ),
    );
  }
}
