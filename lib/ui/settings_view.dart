import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart' show RenderWhitespace;

import '../editor/editor_tabs.dart' show AutoSave;
import '../settings/editor_settings.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'clickable.dart';

/// the settings of the editor and of saving files, which take effect as they
/// are changed
class SettingsView extends StatelessWidget {
  const SettingsView({
    super.key,
    required this.theme,
    required this.controller,
    required this.palettes,
    required this.prefs,
    required this.onPrefs,
    required this.autoSave,
    required this.onAutoSave,
    required this.autoSaveDelay,
    required this.onAutoSaveDelay,
  });

  static const _maxWidth = 640.0;
  static const _delayStep = Duration(milliseconds: 500);
  static const _minDelay = Duration(milliseconds: 500);
  static const _maxDelay = Duration(seconds: 60);

  final AppTheme theme;

  /// what the theme settings change
  final ThemeController controller;

  /// the palettes of the theme, which the current one is among
  final List<String> palettes;
  final EditorPrefs prefs;
  final ValueChanged<EditorPrefs> onPrefs;
  final AutoSave autoSave;
  final ValueChanged<AutoSave> onAutoSave;
  final Duration autoSaveDelay;
  final ValueChanged<Duration> onAutoSaveDelay;

  static String _number(num value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1);

  static const _maxRadius = 24.0;
  static const _maxBorder = 6.0;
  static const _minOpacity = 0.3;
  static const _opacityStep = 0.05;

  /// `Catppuccin Mocha` is `Mocha`, since the flavors are all Catppuccin's
  static String _paletteLabel(String name) =>
      name.replaceFirst('Catppuccin ', '');

  static double _round(double opacity) => (opacity * 20).round() / 20;

  static String _autoSaveLabel(AutoSave value) => switch (value) {
    AutoSave.off => 'Off',
    AutoSave.afterDelay => 'After delay',
    AutoSave.onFocusChange => 'Editor focus',
    AutoSave.onWindowChange => 'Window focus',
  };

  @override
  Widget build(BuildContext context) {
    final fontSize = prefs.fontSize ?? theme.fontSizeBody;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Settings', style: theme.titleStyle),
              const SizedBox(height: 24),
              _Section(
                theme: theme,
                title: 'Theme',
                rows: [
                  if (palettes.length > 1)
                    _SettingRow(
                      theme: theme,
                      label: 'Palette',
                      control: _Choice<String>(
                        theme: theme,
                        value: controller.palette,
                        options: [
                          for (final name in palettes)
                            (name, _paletteLabel(name)),
                        ],
                        onChanged: controller.setPalette,
                      ),
                    ),
                  _SettingRow(
                    theme: theme,
                    label: 'Corner radius',
                    control: _Stepper(
                      theme: theme,
                      text: _number(theme.cornerRadius),
                      onMinus: theme.cornerRadius > 0
                          ? () => controller.setCornerRadius(
                              theme.cornerRadius - 1,
                            )
                          : null,
                      onPlus: theme.cornerRadius < _maxRadius
                          ? () => controller.setCornerRadius(
                              theme.cornerRadius + 1,
                            )
                          : null,
                    ),
                  ),
                  _SettingRow(
                    theme: theme,
                    label: 'Border width',
                    control: _Stepper(
                      theme: theme,
                      text: _number(theme.borderWidth),
                      onMinus: theme.borderWidth > 0
                          ? () =>
                                controller.setBorderWidth(theme.borderWidth - 1)
                          : null,
                      onPlus: theme.borderWidth < _maxBorder
                          ? () =>
                                controller.setBorderWidth(theme.borderWidth + 1)
                          : null,
                    ),
                  ),
                  _SettingRow(
                    theme: theme,
                    label: 'Window opacity',
                    control: _Stepper(
                      theme: theme,
                      text: '${(theme.backgroundOpacity * 100).round()}%',
                      onMinus: theme.backgroundOpacity > _minOpacity
                          ? () => controller.setBackgroundOpacity(
                              _round(theme.backgroundOpacity - _opacityStep),
                            )
                          : null,
                      onPlus: theme.backgroundOpacity < 1
                          ? () => controller.setBackgroundOpacity(
                              _round(theme.backgroundOpacity + _opacityStep),
                            )
                          : null,
                    ),
                  ),
                  _SettingRow(
                    theme: theme,
                    label: 'Blurred window background',
                    control: _Switch(
                      theme: theme,
                      value: theme.acrylic,
                      onChanged: controller.setAcrylic,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _Section(
                theme: theme,
                title: 'Editor',
                rows: [
                  _SettingRow(
                    theme: theme,
                    label: 'Font size',
                    control: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (prefs.fontSize != null)
                          _TextButton(
                            theme: theme,
                            label: 'Reset',
                            onTap: () => onPrefs(prefs.withFontSize(null)),
                          ),
                        const SizedBox(width: 8),
                        _Stepper(
                          theme: theme,
                          text: _number(fontSize),
                          onMinus: fontSize > EditorPrefs.minFontSize
                              ? () => onPrefs(prefs.withFontSize(fontSize - 1))
                              : null,
                          onPlus: fontSize < EditorPrefs.maxFontSize
                              ? () => onPrefs(prefs.withFontSize(fontSize + 1))
                              : null,
                        ),
                      ],
                    ),
                  ),
                  _SettingRow(
                    theme: theme,
                    label: 'Tab size',
                    description:
                        'For files that set no indentation of their own',
                    control: _Stepper(
                      theme: theme,
                      text: '${prefs.tabSize}',
                      onMinus: prefs.tabSize > EditorPrefs.minTabSize
                          ? () => onPrefs(
                              prefs.copyWith(tabSize: prefs.tabSize - 1),
                            )
                          : null,
                      onPlus: prefs.tabSize < EditorPrefs.maxTabSize
                          ? () => onPrefs(
                              prefs.copyWith(tabSize: prefs.tabSize + 1),
                            )
                          : null,
                    ),
                  ),
                  _SettingRow(
                    theme: theme,
                    label: 'Word wrap',
                    control: _Switch(
                      theme: theme,
                      value: prefs.wordWrap,
                      onChanged: (v) => onPrefs(prefs.copyWith(wordWrap: v)),
                    ),
                  ),
                  _SettingRow(
                    theme: theme,
                    label: 'Minimap',
                    control: _Switch(
                      theme: theme,
                      value: prefs.minimap,
                      onChanged: (v) => onPrefs(prefs.copyWith(minimap: v)),
                    ),
                  ),
                  _SettingRow(
                    theme: theme,
                    label: 'Line numbers',
                    control: _Switch(
                      theme: theme,
                      value: prefs.lineNumbers,
                      onChanged: (v) => onPrefs(prefs.copyWith(lineNumbers: v)),
                    ),
                  ),
                  _SettingRow(
                    theme: theme,
                    label: 'Show whitespace',
                    control: _Choice<RenderWhitespace>(
                      theme: theme,
                      value: prefs.renderWhitespace,
                      options: [
                        for (final w in RenderWhitespace.values) (w, w.label),
                      ],
                      onChanged: (v) =>
                          onPrefs(prefs.copyWith(renderWhitespace: v)),
                    ),
                  ),
                  _SettingRow(
                    theme: theme,
                    label: 'Font ligatures',
                    control: _Switch(
                      theme: theme,
                      value: prefs.fontLigatures,
                      onChanged: (v) =>
                          onPrefs(prefs.copyWith(fontLigatures: v)),
                    ),
                  ),
                  _SettingRow(
                    theme: theme,
                    label: 'Smooth scrolling',
                    control: _Switch(
                      theme: theme,
                      value: prefs.smoothScrolling,
                      onChanged: (v) =>
                          onPrefs(prefs.copyWith(smoothScrolling: v)),
                    ),
                  ),
                  _SettingRow(
                    theme: theme,
                    label: 'Bracket pair colors',
                    control: _Switch(
                      theme: theme,
                      value: prefs.bracketPairColorization,
                      onChanged: (v) =>
                          onPrefs(prefs.copyWith(bracketPairColorization: v)),
                    ),
                  ),
                  _SettingRow(
                    theme: theme,
                    label: 'Close brackets automatically',
                    control: _Switch(
                      theme: theme,
                      value: prefs.autoClosingBrackets,
                      onChanged: (v) =>
                          onPrefs(prefs.copyWith(autoClosingBrackets: v)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _Section(
                theme: theme,
                title: 'Files',
                rows: [
                  _SettingRow(
                    theme: theme,
                    label: 'Auto save',
                    control: _Choice<AutoSave>(
                      theme: theme,
                      value: autoSave,
                      options: [
                        for (final a in AutoSave.values) (a, _autoSaveLabel(a)),
                      ],
                      onChanged: onAutoSave,
                    ),
                  ),
                  if (autoSave == AutoSave.afterDelay)
                    _SettingRow(
                      theme: theme,
                      label: 'Auto save delay',
                      control: _Stepper(
                        theme: theme,
                        text:
                            '${_number(autoSaveDelay.inMilliseconds / 1000)} s',
                        onMinus: autoSaveDelay > _minDelay
                            ? () => onAutoSaveDelay(autoSaveDelay - _delayStep)
                            : null,
                        onPlus: autoSaveDelay < _maxDelay
                            ? () => onAutoSaveDelay(autoSaveDelay + _delayStep)
                            : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// a titled group of rows, divided by lines
class _Section extends StatelessWidget {
  const _Section({
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
class _SettingRow extends StatelessWidget {
  const _SettingRow({
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
class _Switch extends StatelessWidget {
  const _Switch({
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
class _Stepper extends StatelessWidget {
  const _Stepper({
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
class _Choice<T> extends StatelessWidget {
  const _Choice({
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

/// text that can be pressed, underlined while hovered
class _TextButton extends StatefulWidget {
  const _TextButton({
    required this.theme,
    required this.label,
    required this.onTap,
  });

  final AppTheme theme;
  final String label;
  final VoidCallback onTap;

  @override
  State<_TextButton> createState() => _TextButtonState();
}

class _TextButtonState extends State<_TextButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Clickable(
      onEnter: () => setState(() => _hovered = true),
      onExit: () => setState(() => _hovered = false),
      onTap: widget.onTap,
      child: Text(
        widget.label,
        style: theme.captionStyle.copyWith(
          color: theme.accent,
          decoration: _hovered ? TextDecoration.underline : null,
          decorationColor: theme.accent,
        ),
      ),
    );
  }
}
