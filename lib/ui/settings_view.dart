import 'package:flutter/material.dart';

import '../editor/editor_tabs.dart' show AutoSave;
import '../native_editor/scrollbar_layout.dart'
    show ScrollbarDiagnostics, ScrollbarSettings, ScrollbarVisibility;
import '../settings/editor_settings.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'settings_controls.dart';
import 'theme_settings.dart';

/// the settings of the editor and of saving files, which take effect as they
/// are changed. the sections, and the titles and descriptions of the settings
/// in them, are those of the editor's own settings window
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
    AutoSave.afterDelay => 'After Delay',
    AutoSave.onFocusChange => 'On Focus Change',
    AutoSave.onWindowChange => 'On Window Change',
  };

  @override
  Widget build(BuildContext context) {
    final fontSize = prefs.fontSize ?? theme.fontSizeBody;
    final scrollbar = prefs.scrollbar;
    void setScrollbar(ScrollbarSettings value) =>
        onPrefs(prefs.copyWith(scrollbar: value));
    const gap = SizedBox(height: 24);
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
              gap,
              ThemeSettings(theme: theme, controller: controller),
              gap,
              SettingsSection(
                theme: theme,
                title: 'Buffer Font',
                rows: [
                  SettingRow(
                    theme: theme,
                    label: 'Font Size',
                    description: 'Font size for editor text.',
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
                    label: 'Font Ligatures',
                    control: SwitchControl(
                      theme: theme,
                      value: prefs.fontLigatures,
                      onChanged: (v) =>
                          onPrefs(prefs.copyWith(fontLigatures: v)),
                    ),
                  ),
                ],
              ),
              gap,
              SettingsSection(
                theme: theme,
                title: 'Highlighting',
                rows: [
                  SettingRow(
                    theme: theme,
                    label: 'Unnecessary Code Fade',
                    description:
                        'How much to fade out unused code (0.0 - 0.9).',
                    control: StepperControl(
                      theme: theme,
                      text: prefs.unnecessaryCodeFade.toStringAsFixed(2),
                      slider: SliderSpec(
                        value: prefs.unnecessaryCodeFade,
                        min: 0,
                        max: EditorPrefs.maxUnnecessaryCodeFade,
                        divisions: 9,
                        onChanged: (v) => onPrefs(
                          prefs.copyWith(
                            unnecessaryCodeFade: (v * 10).round() / 10,
                          ),
                        ),
                      ),
                      onMinus: prefs.unnecessaryCodeFade > 0.05
                          ? () => onPrefs(
                              prefs.copyWith(
                                unnecessaryCodeFade:
                                    ((prefs.unnecessaryCodeFade - 0.1) * 10)
                                        .round() /
                                    10,
                              ),
                            )
                          : null,
                      onPlus:
                          prefs.unnecessaryCodeFade <
                              EditorPrefs.maxUnnecessaryCodeFade - 0.05
                          ? () => onPrefs(
                              prefs.copyWith(
                                unnecessaryCodeFade:
                                    ((prefs.unnecessaryCodeFade + 0.1) * 10)
                                        .round() /
                                    10,
                              ),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
              gap,
              SettingsSection(
                theme: theme,
                title: 'Auto Save',
                rows: [
                  SettingRow(
                    theme: theme,
                    label: 'Auto Save Mode',
                    description: 'When to auto save buffer changes.',
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
                      label: 'Delay (milliseconds)',
                      description:
                          'Save after inactivity period (in milliseconds).',
                      control: StepperControl(
                        theme: theme,
                        text: '${autoSaveDelay.inMilliseconds}',
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
              gap,
              SettingsSection(
                theme: theme,
                title: 'Scrolling',
                rows: [
                  SettingRow(
                    theme: theme,
                    label: 'Mouse Wheel Zoom',
                    description: 'Whether to zoom the editor font size with the mouse wheel while holding the primary modifier key.',
                    control: SwitchControl(
                      theme: theme,
                      value: prefs.mouseWheelZoom,
                      onChanged: (v) =>
                          onPrefs(prefs.copyWith(mouseWheelZoom: v)),
                    ),
                  ),
                ],
              ),
              gap,
              SettingsSection(
                theme: theme,
                title: 'Gutter',
                rows: [
                  SettingRow(
                    theme: theme,
                    label: 'Show Line Numbers',
                    description: 'Show line numbers in the gutter.',
                    control: SwitchControl(
                      theme: theme,
                      value: prefs.lineNumbers,
                      onChanged: (v) => onPrefs(prefs.copyWith(lineNumbers: v)),
                    ),
                  ),
                ],
              ),
              gap,
              SettingsSection(
                theme: theme,
                title: 'Scrollbar',
                rows: [
                  SettingRow(
                    theme: theme,
                    label: 'Show',
                    description: 'When to show the scrollbar in the editor.',
                    control: ChoiceControl<ScrollbarVisibility>(
                      theme: theme,
                      value: scrollbar.show,
                      options: const [
                        (ScrollbarVisibility.auto, 'Auto'),
                        (ScrollbarVisibility.system, 'System'),
                        (ScrollbarVisibility.always, 'Always'),
                        (ScrollbarVisibility.never, 'Never'),
                      ],
                      onChanged: (v) =>
                          setScrollbar(scrollbar.copyWith(show: v)),
                    ),
                  ),
                  SettingRow(
                    theme: theme,
                    label: 'Cursors',
                    description: 'Show cursor positions in the scrollbar.',
                    control: SwitchControl(
                      theme: theme,
                      value: scrollbar.cursors,
                      onChanged: (v) =>
                          setScrollbar(scrollbar.copyWith(cursors: v)),
                    ),
                  ),
                  SettingRow(
                    theme: theme,
                    label: 'Search Results',
                    description: 'Show buffer search result indicators in the scrollbar.',
                    control: SwitchControl(
                      theme: theme,
                      value: scrollbar.searchResults,
                      onChanged: (v) =>
                          setScrollbar(scrollbar.copyWith(searchResults: v)),
                    ),
                  ),
                  SettingRow(
                    theme: theme,
                    label: 'Selected Text',
                    description:
                        'Show selected text occurrences in the scrollbar.',
                    control: SwitchControl(
                      theme: theme,
                      value: scrollbar.selectedText,
                      onChanged: (v) =>
                          setScrollbar(scrollbar.copyWith(selectedText: v)),
                    ),
                  ),
                  SettingRow(
                    theme: theme,
                    label: 'Selected Symbol',
                    description:
                        'Show selected symbol occurrences in the scrollbar.',
                    control: SwitchControl(
                      theme: theme,
                      value: scrollbar.selectedSymbol,
                      onChanged: (v) =>
                          setScrollbar(scrollbar.copyWith(selectedSymbol: v)),
                    ),
                  ),
                  SettingRow(
                    theme: theme,
                    label: 'Diagnostics',
                    description:
                        'Which diagnostic indicators to show in the scrollbar.',
                    control: ChoiceControl<ScrollbarDiagnostics>(
                      theme: theme,
                      value: scrollbar.diagnostics,
                      options: const [
                        (ScrollbarDiagnostics.all, 'All'),
                        (ScrollbarDiagnostics.information, 'Information'),
                        (ScrollbarDiagnostics.warning, 'Warning'),
                        (ScrollbarDiagnostics.error, 'Error'),
                        (ScrollbarDiagnostics.none, 'None'),
                      ],
                      onChanged: (v) =>
                          setScrollbar(scrollbar.copyWith(diagnostics: v)),
                    ),
                  ),
                  SettingRow(
                    theme: theme,
                    label: 'Horizontal Scrollbar',
                    description: 'When false, forcefully disables the horizontal scrollbar.',
                    control: SwitchControl(
                      theme: theme,
                      value: scrollbar.horizontal,
                      onChanged: (v) =>
                          setScrollbar(scrollbar.copyWith(horizontal: v)),
                    ),
                  ),
                  SettingRow(
                    theme: theme,
                    label: 'Vertical Scrollbar',
                    description: 'When false, forcefully disables the vertical scrollbar.',
                    control: SwitchControl(
                      theme: theme,
                      value: scrollbar.vertical,
                      onChanged: (v) =>
                          setScrollbar(scrollbar.copyWith(vertical: v)),
                    ),
                  ),
                ],
              ),
              gap,
              SettingsSection(
                theme: theme,
                title: 'Indentation',
                rows: [
                  SettingRow(
                    theme: theme,
                    label: 'Tab Size',
                    description: 'How many columns a tab should occupy.',
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
                ],
              ),
              gap,
              SettingsSection(
                theme: theme,
                title: 'Wrapping',
                rows: [
                  SettingRow(
                    theme: theme,
                    label: 'Soft Wrap',
                    description: 'How to soft-wrap long lines of text.',
                    control: ChoiceControl<bool>(
                      theme: theme,
                      value: prefs.wordWrap,
                      options: const [(false, 'None'), (true, 'Editor Width')],
                      onChanged: (v) => onPrefs(prefs.copyWith(wordWrap: v)),
                    ),
                  ),
                ],
              ),
              gap,
              SettingsSection(
                theme: theme,
                title: 'Autoclose',
                rows: [
                  SettingRow(
                    theme: theme,
                    label: 'Use Autoclose',
                    description: "Whether to automatically type closing characters for you. For example, when you type '(', the editor will automatically add a closing ')' at the correct position.",
                    control: SwitchControl(
                      theme: theme,
                      value: prefs.autoClosingBrackets,
                      onChanged: (v) =>
                          onPrefs(prefs.copyWith(autoClosingBrackets: v)),
                    ),
                  ),
                ],
              ),
              if (syntaxStyles != null && onSyntaxStyles != null) ...[
                gap,
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
            ],
          ),
        ),
      ),
    );
  }
}
