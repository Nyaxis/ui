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
      child: Row(
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
          control,
        ],
      ),
    );
  }
}

/// an on and off switch
class SwitchControl extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Clickable(
      onTap: () => onChanged(!value),
      child: Semantics(
        toggled: value,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: _width,
          height: _height,
          padding: const EdgeInsets.all((_height - _knob) / 2),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: value ? theme.accent : theme.active,
            borderRadius: BorderRadius.circular(_height / 2),
          ),
          child: Container(
            width: _knob,
            height: _knob,
            decoration: BoxDecoration(
              color: value ? theme.titleBar : theme.textPrimary,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// a number that moves by one step each way; a null callback disables that
/// side
class StepperControl extends StatelessWidget {
  const StepperControl({
    super.key,
    required this.theme,
    required this.text,
    required this.onMinus,
    required this.onPlus,
  });

  final AppTheme theme;
  final String text;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
          color: enabled && _hovered ? theme.hover : theme.background,
          borderRadius: BorderRadius.circular(theme.cornerRadius / 2),
          border: Border.all(color: theme.border, width: theme.borderWidth),
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

/// a row of options that one is chosen from
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
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: WrapAlignment.end,
      children: [
        for (final (option, label) in options)
          _ChoiceButton(
            theme: theme,
            label: label,
            selected: option == value,
            onTap: () => onChanged(option),
          ),
      ],
    );
  }
}

class _ChoiceButton extends StatefulWidget {
  const _ChoiceButton({
    required this.theme,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final AppTheme theme;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ChoiceButton> createState() => _ChoiceButtonState();
}

class _ChoiceButtonState extends State<_ChoiceButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Clickable(
      onEnter: () => setState(() => _hovered = true),
      onExit: () => setState(() => _hovered = false),
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: widget.selected
              ? theme.accent
              : (_hovered ? theme.hover : theme.background),
          borderRadius: BorderRadius.circular(theme.cornerRadius / 2),
          border: Border.all(
            color: widget.selected ? theme.accent : theme.border,
            width: theme.borderWidth,
          ),
        ),
        child: Text(
          widget.label,
          style: theme.captionStyle.copyWith(
            color: widget.selected ? theme.titleBar : theme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
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
  });

  final AppTheme theme;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final double width;

  @override
  State<DropdownControl<T>> createState() => _DropdownControlState<T>();
}

class _DropdownControlState<T> extends State<DropdownControl<T>> {
  bool _hovered = false;

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
            onPressed: () => widget.onChanged(option),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Clickable(
      onEnter: () => setState(() => _hovered = true),
      onExit: () => setState(() => _hovered = false),
      onTap: widget.options.isEmpty ? null : _open,
      child: Container(
        width: widget.width,
        height: 30,
        padding: const EdgeInsets.only(left: 10, right: 6),
        decoration: BoxDecoration(
          color: _hovered ? theme.hover : theme.background,
          borderRadius: BorderRadius.circular(theme.cornerRadius / 2),
          border: Border.all(color: theme.border, width: theme.borderWidth),
        ),
        child: Row(
          children: [
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
  }
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
