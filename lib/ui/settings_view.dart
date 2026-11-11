import 'package:flutter/material.dart';

import '../editor/editor_tabs.dart' show AutoSave;
import '../native_editor/scrollbar_layout.dart' show ScrollbarVisibility;
import '../settings/editor_settings.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'settings_controls.dart';
import 'theme_settings.dart';

/// the settings of the editor and of saving files, which take effect as they
/// are changed
class SettingsView extends StatelessWidget {
  const SettingsView({
    super.key,
    required this.theme,
    required this.controller,
    required this.prefs,
    required this.onPrefs,
    required this.autoSave,
    required this.onAutoSave,
    required this.autoSaveDelay,
    required this.onAutoSaveDelay,
    this.syntaxStyles,
    this.onSyntaxStyles,
  });

  static const _maxWidth = 760.0;
  static const _delayStep = Duration(milliseconds: 500);
  static const _minDelay = Duration(milliseconds: 500);
  static const _maxDelay = Duration(seconds: 60);

  final AppTheme theme;

  /// what the theme settings change
  final ThemeController controller;
  final EditorPrefs prefs;
  final ValueChanged<EditorPrefs> onPrefs;
  final AutoSave autoSave;
  final ValueChanged<AutoSave> onAutoSave;
  final Duration autoSaveDelay;
  final ValueChanged<Duration> onAutoSaveDelay;

  /// which kinds of code are drawn bold or italic, by the names the queries
  /// give them; null when the editor does not color code, which leaves out
  /// the section
  final Map<String, String>? syntaxStyles;
  final ValueChanged<Map<String, String>>? onSyntaxStyles;

  /// the kinds of code a style can be given, and what the queries call them
  static const _syntaxKinds = [
    ('Comments', 'comment'),
    ('Keywords', 'keyword'),
    ('Strings', 'string'),
    ('Numbers', 'number'),
    ('Constants', 'constant'),
    ('Functions', 'function'),
    ('Types', 'type'),
    ('self and built-ins', 'variable.builtin'),
    ('Parameters', 'variable.parameter'),
    ('Fields', 'variable.member'),
    ('Operators', 'operator'),
    ('Brackets and punctuation', 'punctuation'),
  ];

  static const _fontStyleOptions = [
    ('regular', 'Regular'),
    ('bold', 'Bold'),
    ('italic', 'Italic'),
    ('bold italic', 'Bold italic'),
  ];

  /// how [name] is drawn now: comments are italic until it is said otherwise
  String _fontStyleOf(String name) {
    final spec = syntaxStyles?[name];
    if (spec == null) {
      return name == 'comment' ? 'italic' : 'regular';
    }
    final words = spec.toLowerCase().split(RegExp(r'[\s,]+'));
    final bold = words.contains('bold');
    final italic = words.contains('italic');
    return bold && italic
        ? 'bold italic'
        : bold
        ? 'bold'
        : italic
        ? 'italic'
        : 'regular';
  }

  /// the styles with [name] drawn as [style]. what is the default is not kept.
  Map<String, String> _withFontStyle(String name, String style) {
    final styles = Map.of(syntaxStyles ?? const <String, String>{});
    final standard = name == 'comment' ? 'italic' : 'regular';
    if (style == standard) {
      styles.remove(name);
    } else {
      // regular is said as none, as that takes the default style away
      styles[name] = style == 'regular' ? 'none' : style;
    }
    return styles;
  }

  static String _number(num value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1);

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
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Settings', style: theme.titleStyle),
              const SizedBox(height: 24),
              ThemeSettings(theme: theme, controller: controller),
              const SizedBox(height: 24),
              SettingsSection(
                theme: theme,
                title: 'Editor',
                rows: [
                  SettingRow(
                    theme: theme,
                    label: 'Font size',
                    control: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (prefs.fontSize != null)
                          LinkButton(
                            theme: theme,
                            label: 'Reset',
                            onTap: () => onPrefs(prefs.withFontSize(null)),
                          ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: StepperControl(
                            theme: theme,
                            text: _number(fontSize),
                            slider: SliderSpec(
                              value: fontSize,
                              min: EditorPrefs.minFontSize,
                              max: EditorPrefs.maxFontSize,
                              divisions:
                                  (EditorPrefs.maxFontSize -
                                          EditorPrefs.minFontSize)
                                      .round(),
                              onChanged: (v) => onPrefs(
                                prefs.withFontSize(v.roundToDouble()),
                              ),
                            ),
                            onMinus: fontSize > EditorPrefs.minFontSize
                                ? () =>
                                      onPrefs(prefs.withFontSize(fontSize - 1))
                                : null,
                            onPlus: fontSize < EditorPrefs.maxFontSize
                                ? () =>
                                      onPrefs(prefs.withFontSize(fontSize + 1))
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SettingRow(
                    theme: theme,
                    label: 'Tab size',
                    description:
                        'For files that set no indentation of their own',
                    control: StepperControl(
                      theme: theme,
                      text: '${prefs.tabSize}',
                      slider: SliderSpec(
                        value: prefs.tabSize.toDouble(),
                        min: EditorPrefs.minTabSize.toDouble(),
                        max: EditorPrefs.maxTabSize.toDouble(),
                        divisions:
                            EditorPrefs.maxTabSize - EditorPrefs.minTabSize,
                        onChanged: (v) =>
                            onPrefs(prefs.copyWith(tabSize: v.round())),
                      ),
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
                  SettingRow(
                    theme: theme,
                    label: 'Word wrap',
                    control: SwitchControl(
                      theme: theme,
                      value: prefs.wordWrap,
                      onChanged: (v) => onPrefs(prefs.copyWith(wordWrap: v)),
                    ),
                  ),
                  SettingRow(
                    theme: theme,
                    label: 'Line numbers',
                    control: SwitchControl(
                      theme: theme,
                      value: prefs.lineNumbers,
                      onChanged: (v) => onPrefs(prefs.copyWith(lineNumbers: v)),
                    ),
                  ),
                  SettingRow(
                    theme: theme,
                    label: 'Font ligatures',
                    control: SwitchControl(
                      theme: theme,
                      value: prefs.fontLigatures,
                      onChanged: (v) =>
                          onPrefs(prefs.copyWith(fontLigatures: v)),
                    ),
                  ),
                  SettingRow(
                    theme: theme,
                    label: 'Close brackets automatically',
                    control: SwitchControl(
                      theme: theme,
                      value: prefs.autoClosingBrackets,
                      onChanged: (v) =>
                          onPrefs(prefs.copyWith(autoClosingBrackets: v)),
                    ),
                  ),
                  SettingRow(
                    theme: theme,
                    label: 'Mouse wheel zoom',
                    description: 'Whether to zoom the editor font size with the mouse wheel while holding the primary modifier key.',
                    control: SwitchControl(
                      theme: theme,
                      value: prefs.mouseWheelZoom,
                      onChanged: (v) =>
                          onPrefs(prefs.copyWith(mouseWheelZoom: v)),
                    ),
                  ),
                  SettingRow(
                    theme: theme,
                    label: 'Scrollbars',
                    description: 'Auto hides them a moment after scrolling',
                    control: ChoiceControl<ScrollbarVisibility>(
                      theme: theme,
                      value: prefs.scrollbars,
                      options: const [
                        (ScrollbarVisibility.auto, 'Auto'),
                        (ScrollbarVisibility.always, 'Always'),
                        (ScrollbarVisibility.never, 'Never'),
                      ],
                      onChanged: (v) => onPrefs(prefs.copyWith(scrollbars: v)),
                    ),
                  ),
                ],
              ),
              if (syntaxStyles != null && onSyntaxStyles != null) ...[
                const SizedBox(height: 24),
                SettingsSection(
                  theme: theme,
                  title: 'Code styles',
                  rows: [
                    for (final (label, name) in _syntaxKinds)
                      SettingRow(
                        theme: theme,
                        label: label,
                        control: ChoiceControl<String>(
                          theme: theme,
                          value: _fontStyleOf(name),
                          options: _fontStyleOptions,
                          onChanged: (style) =>
                              onSyntaxStyles!(_withFontStyle(name, style)),
                        ),
                      ),
                    if (syntaxStyles!.isNotEmpty)
                      SettingRow(
                        theme: theme,
                        label: 'Reset',
                        description: 'Back to the defaults',
                        control: LinkButton(
                          theme: theme,
                          label: 'Reset all',
                          onTap: () => onSyntaxStyles!(const {}),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              SettingsSection(
                theme: theme,
                title: 'Files',
                rows: [
                  SettingRow(
                    theme: theme,
                    label: 'Auto save',
                    control: ChoiceControl<AutoSave>(
                      theme: theme,
                      value: autoSave,
                      options: [
                        for (final a in AutoSave.values) (a, _autoSaveLabel(a)),
                      ],
                      onChanged: onAutoSave,
                    ),
                  ),
                  if (autoSave == AutoSave.afterDelay)
                    SettingRow(
                      theme: theme,
                      label: 'Auto save delay',
                      control: StepperControl(
                        theme: theme,
                        text:
                            '${_number(autoSaveDelay.inMilliseconds / 1000)} s',
                        slider: SliderSpec(
                          value: autoSaveDelay.inMilliseconds / 1000,
                          min: _minDelay.inMilliseconds / 1000,
                          max: _maxDelay.inMilliseconds / 1000,
                          divisions:
                              (_maxDelay - _minDelay).inMilliseconds ~/
                              _delayStep.inMilliseconds,
                          onChanged: (v) => onAutoSaveDelay(
                            _delayStep *
                                ((v * 1000) / _delayStep.inMilliseconds)
                                    .round(),
                          ),
                        ),
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
