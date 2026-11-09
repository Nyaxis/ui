import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart' show RenderWhitespace;

import '../editor/editor_tabs.dart' show AutoSave;
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
                        StepperControl(
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
                  SettingRow(
                    theme: theme,
                    label: 'Tab size',
                    description:
                        'For files that set no indentation of their own',
                    control: StepperControl(
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
                    label: 'Minimap',
                    control: SwitchControl(
                      theme: theme,
                      value: prefs.minimap,
                      onChanged: (v) => onPrefs(prefs.copyWith(minimap: v)),
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
                    label: 'Show whitespace',
                    control: ChoiceControl<RenderWhitespace>(
                      theme: theme,
                      value: prefs.renderWhitespace,
                      options: [
                        for (final w in RenderWhitespace.values) (w, w.label),
                      ],
                      onChanged: (v) =>
                          onPrefs(prefs.copyWith(renderWhitespace: v)),
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
                    label: 'Smooth scrolling',
                    control: SwitchControl(
                      theme: theme,
                      value: prefs.smoothScrolling,
                      onChanged: (v) =>
                          onPrefs(prefs.copyWith(smoothScrolling: v)),
                    ),
                  ),
                  SettingRow(
                    theme: theme,
                    label: 'Bracket pair colors',
                    control: SwitchControl(
                      theme: theme,
                      value: prefs.bracketPairColorization,
                      onChanged: (v) =>
                          onPrefs(prefs.copyWith(bracketPairColorization: v)),
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
                ],
              ),
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
