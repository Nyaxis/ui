import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'clickable.dart';
import 'color_picker.dart';
import 'context_menu.dart';

/// a titled group of rows, divided by lines
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.theme,
    required this.title,
    required this.rows,
  });

  final AppTheme theme;
  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final line = BorderSide(color: theme.border, width: theme.borderWidth);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.headingStyle),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(theme.cornerRadius),
            border: Border.fromBorderSide(line),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    border: i == 0 ? null : Border(top: line),
                  ),
                  child: rows[i],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// the name of a setting, what it does under it when that is not obvious,
/// and the [control] that changes it
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.theme,
    required this.label,
    required this.control,
    this.description,
  });

  final AppTheme theme;
  final String label;
  final String? description;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      // a control is as wide as it wants up to most of the row, which lets the
      // parts of it that can shrink, such as a slider, do so in a narrow one
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.bodyStyle),
                  if (description != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(description!, style: theme.captionStyle),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth * 0.75,
              ),
              child: control,
            ),
          ],
        ),
      ),
    );
  }
}

/// an on and off switch
class SwitchControl extends StatefulWidget {
  const SwitchControl({
    super.key,
    required this.theme,
    required this.value,
    required this.onChanged,
  });

  static const _width = 36.0;
  static const _height = 20.0;
  static const _knob = 14.0;

  final AppTheme theme;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<SwitchControl> createState() => _SwitchControlState();
}

class _SwitchControlState extends State<SwitchControl> {
  static const _width = SwitchControl._width;
  static const _height = SwitchControl._height;
  static const _knob = SwitchControl._knob;

  bool _hovered = false;

  AppTheme get theme => widget.theme;
  bool get value => widget.value;

  /// the track, with the text color over it while the pointer is on it: a
  /// twentieth of it when the switch is off, and a sixth when it is on, and
  /// one and a half times that in a light theme
  Color get _track {
    final track = value ? theme.accent : theme.disabled;
    if (!_hovered) {
      return track;
    }
    final light = theme.background.computeLuminance() >= 0.5;
    final share = (value ? 0.16 : 0.05) * (light ? 1.5 : 1.0);
    return Color.alphaBlend(theme.textPrimary.withValues(alpha: share), track);
  }

  @override
  Widget build(BuildContext context) {
    return Clickable(
      onEnter: () => setState(() => _hovered = true),
      onExit: () => setState(() => _hovered = false),
      onTap: () => widget.onChanged(!value),
      child: Semantics(
        toggled: value,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: _width,
          height: _height,
          padding: const EdgeInsets.all((_height - _knob) / 2),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: _track,
            borderRadius: BorderRadius.circular(_height / 2),
          ),
          child: Container(
            width: _knob,
            height: _knob,
            decoration: BoxDecoration(
              color: value
                  ? theme.titleBar
                  : theme.textPrimary.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// a slider over a range in [divisions] equal steps; it only reports when the
/// value moves to another step
class SliderSpec {
  const SliderSpec({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
}

/// a number that moves by one step each way; a null callback disables that
/// side. a [slider] goes beside the buttons, and does not replace them
class StepperControl extends StatelessWidget {
  const StepperControl({
    super.key,
    required this.theme,
    required this.text,
    required this.onMinus,
    required this.onPlus,
    this.slider,
  });

  static const sliderWidth = 150.0;

  final AppTheme theme;
  final String text;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final SliderSpec? slider;

  @override
  Widget build(BuildContext context) {
    final spec = slider;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (spec != null) ...[
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: sliderWidth),
              child: _SteppedSlider(theme: theme, spec: spec),
            ),
          ),
          const SizedBox(width: 10),
        ],
        _StepButton(theme: theme, label: '−', onTap: onMinus),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: theme.bodyStyle,
          ),
        ),
        _StepButton(theme: theme, label: '+', onTap: onPlus),
      ],
    );
  }
}

/// a slider whose thumb stays under the pointer, wherever the setting is. the
/// setting moves in steps, and is told only when the pointer crosses into
/// another one, so a drag does not change it, and rebuild everything that
/// shows it, at every pixel
class _SteppedSlider extends StatefulWidget {
  const _SteppedSlider({required this.theme, required this.spec});

  final AppTheme theme;
  final SliderSpec spec;

  @override
  State<_SteppedSlider> createState() => _SteppedSliderState();
}

class _SteppedSliderState extends State<_SteppedSlider> {
  /// where the thumb is while it is dragged, which is not on a step; null
  /// when it is not, and the thumb is on the setting's own value
  double? _drag;

  /// the step the setting was last told to move to by this drag
  double? _reported;

  double _snap(double value) {
    final spec = widget.spec;
    final step = (spec.max - spec.min) / spec.divisions;
    final snapped = spec.min + ((value - spec.min) / step).round() * step;
    return snapped.clamp(spec.min, spec.max);
  }

  void _move(double value) {
    setState(() => _drag = value);
    final snapped = _snap(value);
    if (snapped != _reported) {
      _reported = snapped;
      widget.spec.onChanged(snapped);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final theme = widget.theme;
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: theme.accent,
        inactiveTrackColor: theme.active,
        thumbColor: theme.accent,
        overlayColor: theme.accent.withValues(alpha: 0.15),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        showValueIndicator: ShowValueIndicator.never,
      ),
      child: Slider(
        value: (_drag ?? spec.value).clamp(spec.min, spec.max),
        min: spec.min,
        max: spec.max,
        onChangeStart: (_) => _reported = spec.value,
        onChanged: _move,
        onChangeEnd: (_) => setState(() {
          _drag = null;
          _reported = null;
        }),
      ),
    );
  }
}

class _StepButton extends StatefulWidget {
  const _StepButton({
    required this.theme,
    required this.label,
    required this.onTap,
  });

  final AppTheme theme;
  final String label;
  final VoidCallback? onTap;

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final enabled = widget.onTap != null;
    return Clickable(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: () => setState(() => _hovered = true),
      onExit: () => setState(() => _hovered = false),
      onTap: widget.onTap,
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // on the surface, with the faint border, and the color of a hovered
          // element, which in the palettes is the one of the line
          color: enabled && _hovered ? theme.border : theme.surface,
          borderRadius: BorderRadius.circular(theme.cornerRadius / 2),
          border: Border.all(
            color: theme.borderVariant,
            width: theme.borderWidth,
          ),
        ),
        child: Text(
          widget.label,
          style: theme.bodyStyle.copyWith(
            color: enabled ? theme.textPrimary : theme.textDim,
          ),
        ),
      ),
    );
  }
}

/// one option chosen from a list, which is a dropdown, as it is for settings
/// that have a few values
class ChoiceControl<T> extends StatelessWidget {
  const ChoiceControl({
    super.key,
    required this.theme,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final AppTheme theme;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownControl<T>(
      theme: theme,
      value: value,
      options: options,
      onChanged: onChanged,
    );
  }
}

/// text that can be pressed, underlined while hovered; a null [onTap] greys it
/// out
class LinkButton extends StatefulWidget {
  const LinkButton({
    super.key,
    required this.theme,
    required this.label,
    required this.onTap,
  });

  final AppTheme theme;
  final String label;
  final VoidCallback? onTap;

  @override
  State<LinkButton> createState() => _LinkButtonState();
}

class _LinkButtonState extends State<LinkButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final enabled = widget.onTap != null;
    return Clickable(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: () => setState(() => _hovered = true),
      onExit: () => setState(() => _hovered = false),
      onTap: widget.onTap,
      child: Text(
        widget.label,
        style: theme.captionStyle.copyWith(
          color: enabled ? theme.accent : theme.textDim.withValues(alpha: 0.5),
          decoration: enabled && _hovered ? TextDecoration.underline : null,
          decorationColor: theme.accent,
        ),
      ),
    );
  }
}

/// one option chosen from a menu that opens under the button; the current
/// one is checked
class DropdownControl<T> extends StatefulWidget {
  const DropdownControl({
    super.key,
    required this.theme,
    required this.value,
    required this.options,
    required this.onChanged,
    this.width = 180,
    this.leadingFor,
  });

  final AppTheme theme;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final double width;

  /// what goes before the name of an option, in the menu and, for the one
  /// chosen, in the button; null for none
  final Widget? Function(T option)? leadingFor;

  @override
  State<DropdownControl<T>> createState() => _DropdownControlState<T>();
}

class _DropdownControlState<T> extends State<DropdownControl<T>> {
  bool _hovered = false;
  bool _pressed = false;

  String get _label {
    for (final (option, label) in widget.options) {
      if (option == widget.value) {
        return label;
      }
    }
    return '${widget.value}';
  }

  void _open() {
    final box = context.findRenderObject() as RenderBox;
    showContextMenu(
      context,
      position: box.localToGlobal(Offset(0, box.size.height + 4)),
      theme: widget.theme,
      entries: [
        for (final (option, label) in widget.options)
          ContextMenuItem(
            label,
            checked: option == widget.value,
            checkAtEnd: true,
            leading: widget.leadingFor?.call(option),
            onPressed: () => widget.onChanged(option),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = widget.width.clamp(0.0, constraints.maxWidth);
        // in a narrow button the preview would leave no room for the name
        final leading = width >= _minWidthForLeading
            ? widget.leadingFor?.call(widget.value)
            : null;
        // an outlined button of 28 rems: on the color of an element, with the
        // faint border; hovered it is the fill of a ghost element and the
        // border of a line, and pressed the fill is the one of an active
        // element
        return Clickable(
          onEnter: () => setState(() => _hovered = true),
          onExit: () => setState(() {
            _hovered = false;
            _pressed = false;
          }),
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.options.isEmpty ? null : _open,
          child: Container(
            width: width,
            height: theme.rem(28),
            padding: EdgeInsets.only(left: leading == null ? 10 : 4, right: 6),
            decoration: BoxDecoration(
              color: _pressed
                  ? theme.active.withValues(alpha: 0x4D / 255)
                  : _hovered
                  ? theme.hover.withValues(alpha: 0x4D / 255)
                  : theme.titleBar,
              borderRadius: BorderRadius.circular(theme.cornerRadius / 2),
              border: Border.all(
                color: _hovered && !_pressed
                    ? theme.border
                    : theme.borderVariant,
                width: theme.borderWidth,
              ),
            ),
            child: Row(
              children: [
                if (leading != null) ...[leading, const SizedBox(width: 8)],
                Expanded(
                  child: Text(
                    _label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyStyle,
                  ),
                ),
                Icon(Icons.expand_more, size: 16, color: theme.textDim),
              ],
            ),
          ),
        );
      },
    );
  }

  /// the least width of a button that has room for a preview and the start of
  /// a name beside it
  static const _minWidthForLeading = 150.0;
}

/// a color shown as a swatch, which opens a picker, and as hex that can be
/// typed; what is typed counts once it is a color, and goes back to the
/// current one when the field is left with something else
class ColorField extends StatefulWidget {
  const ColorField({
    super.key,
    required this.theme,
    required this.color,
    required this.onChanged,
  });

  final AppTheme theme;
  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  State<ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<ColorField> {
  late final _text = TextEditingController(text: colorToHex(widget.color));
  final _focus = FocusNode();
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _text.text = colorToHex(widget.color);
        setState(() => _invalid = false);
      }
    });
  }

  @override
  void didUpdateWidget(ColorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // a color that came from elsewhere, such as the picker, is not typed over
    if (oldWidget.color != widget.color &&
        parseHexColor(_text.text) != widget.color) {
      _text.text = colorToHex(widget.color);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _typed(String text) {
    final color = parseHexColor(text);
    setState(() => _invalid = color == null);
    if (color != null && color != widget.color) {
      widget.onChanged(color);
    }
  }

  void _openPicker() {
    final box = context.findRenderObject() as RenderBox;
    showColorPicker(
      context,
      theme: widget.theme,
      position: box.localToGlobal(Offset(0, box.size.height + 6)),
      initial: widget.color,
      onChanged: widget.onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Clickable(
          onTap: _openPicker,
          child: Container(
            key: const ValueKey('swatch'),
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(theme.cornerRadius / 2),
              border: Border.all(color: theme.border, width: theme.borderWidth),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 92,
          height: 30,
          child: TextField(
            controller: _text,
            focusNode: _focus,
            onChanged: _typed,
            maxLength: 7,
            style: theme.monoStyle,
            cursorColor: theme.accent,
            decoration: InputDecoration(
              counterText: '',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              filled: true,
              fillColor: theme.background,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(theme.cornerRadius / 2),
                borderSide: BorderSide(
                  color: _invalid ? theme.red : theme.border,
                  width: theme.borderWidth,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(theme.cornerRadius / 2),
                borderSide: BorderSide(
                  color: _invalid ? theme.red : theme.accent,
                  width: theme.borderWidth,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
