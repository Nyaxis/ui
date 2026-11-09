import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// a color as `#rrggbb`
String colorToHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// reads `#rgb` or `#rrggbb`, with or without the `#`; null for anything else
Color? parseHexColor(String text) {
  var hex = text.trim().replaceFirst('#', '');
  if (hex.length == 3) {
    hex = hex.split('').map((c) => '$c$c').join();
  }
  if (hex.length != 6 || !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) {
    return null;
  }
  return Color(0xFF000000 | int.parse(hex, radix: 16));
}

/// opens a picker for a color at [position], in the overlay's coordinates,
/// moved to stay inside it; [onChanged] hears of every color the pointer
/// passes over. anything pressed outside closes it
void showColorPicker(
  BuildContext context, {
  required AppTheme theme,
  required Offset position,
  required Color initial,
  required ValueChanged<Color> onChanged,
}) {
  late final OverlayEntry overlay;
  overlay = OverlayEntry(
    builder: (context) => _PickerLayer(
      theme: theme,
      position: position,
      initial: initial,
      onChanged: onChanged,
      onClose: overlay.remove,
    ),
  );
  Overlay.of(context).insert(overlay);
}

class _PickerLayer extends StatelessWidget {
  const _PickerLayer({
    required this.theme,
    required this.position,
    required this.initial,
    required this.onChanged,
    required this.onClose,
  });

  final AppTheme theme;
  final Offset position;
  final Color initial;
  final ValueChanged<Color> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    const width = HsvPicker.width + 24;
    const height = HsvPicker.height + 24;
    final left = position.dx.clamp(
      8.0,
      (size.width - width - 8).clamp(8.0, double.infinity),
    );
    final top = position.dy.clamp(
      8.0,
      (size.height - height - 8).clamp(8.0, double.infinity),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => onClose(),
            onSecondaryTapDown: (_) => onClose(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(theme.cornerRadius),
              border: Border.all(color: theme.border, width: theme.borderWidth),
              boxShadow: const [
                BoxShadow(color: Color(0x66000000), blurRadius: 16),
              ],
            ),
            child: HsvPicker(color: initial, onChanged: onChanged),
          ),
        ),
      ],
    );
  }
}

/// a square to choose how saturated and how bright, and a strip to choose the
/// hue
class HsvPicker extends StatefulWidget {
  const HsvPicker({super.key, required this.color, required this.onChanged});

  static const width = 220.0;
  static const _square = 150.0;
  static const _strip = 14.0;
  static const _gap = 10.0;
  static const height = _square + _gap + _strip;

  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  State<HsvPicker> createState() => _HsvPickerState();
}

class _HsvPickerState extends State<HsvPicker> {
  late HSVColor _hsv = HSVColor.fromColor(widget.color);

  void _set(HSVColor hsv) {
    setState(() => _hsv = hsv);
    widget.onChanged(hsv.toColor());
  }

  /// the position in a box of [size], kept inside it
  static Offset _inside(Offset local, Size size) =>
      Offset(local.dx.clamp(0.0, size.width), local.dy.clamp(0.0, size.height));

  void _square(Offset local) {
    final p = _inside(local, const Size(HsvPicker.width, HsvPicker._square));
    _set(
      _hsv
          .withSaturation(p.dx / HsvPicker.width)
          .withValue(1 - p.dy / HsvPicker._square),
    );
  }

  void _strip(Offset local) {
    final p = _inside(local, const Size(HsvPicker.width, HsvPicker._strip));
    _set(_hsv.withHue(p.dx / HsvPicker.width * 360));
  }

  @override
  Widget build(BuildContext context) {
    final hue = HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor();
    return SizedBox(
      width: HsvPicker.width,
      height: HsvPicker.height,
      child: Column(
        children: [
          GestureDetector(
            onPanDown: (d) => _square(d.localPosition),
            onPanUpdate: (d) => _square(d.localPosition),
            child: SizedBox(
              key: const ValueKey('hsv-square'),
              width: HsvPicker.width,
              height: HsvPicker._square,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [Colors.white, hue]),
                        ),
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x00000000), Colors.black],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _Thumb(
                    left: _hsv.saturation * HsvPicker.width,
                    top: (1 - _hsv.value) * HsvPicker._square,
                    color: _hsv.toColor(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: HsvPicker._gap),
          GestureDetector(
            onPanDown: (d) => _strip(d.localPosition),
            onPanUpdate: (d) => _strip(d.localPosition),
            child: SizedBox(
              key: const ValueKey('hsv-strip'),
              width: HsvPicker.width,
              height: HsvPicker._strip,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(HsvPicker._strip / 2),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              for (var h = 0; h <= 360; h += 60)
                                HSVColor.fromAHSV(
                                  1,
                                  h.toDouble(),
                                  1,
                                  1,
                                ).toColor(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _Thumb(
                    left: _hsv.hue / 360 * HsvPicker.width,
                    top: HsvPicker._strip / 2,
                    color: hue,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// a ring on the spot that is chosen, drawn on the color there
class _Thumb extends StatelessWidget {
  const _Thumb({required this.left, required this.top, required this.color});

  static const _size = 14.0;

  final double left;
  final double top;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left - _size / 2,
      top: top - _size / 2,
      child: IgnorePointer(
        child: Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Color(0x80000000), blurRadius: 3),
            ],
          ),
        ),
      ),
    );
  }
}
