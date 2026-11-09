import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'dialog.dart';
import 'palette_preview.dart';
import 'picker.dart';
import 'settings_controls.dart';

/// the sections that choose, make, rename and remove themes and palettes, and
/// change what is in them; every change shows at once, and is saved
class ThemeSettings extends StatelessWidget {
  const ThemeSettings({
    super.key,
    required this.theme,
    required this.controller,
  });

  static const _maxRadius = 24.0;
  static const _maxBorder = 6.0;
  static const _powerStep = 0.5;
  static const _minOpacity = 0.3;
  static const _opacityStep = 0.05;

  /// pickers open under the title bar
  static const _top = 48.0;

  final AppTheme theme;
  final ThemeController controller;

  static String _number(num value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1);

  static double _roundOpacity(double opacity) => (opacity * 20).round() / 20;

  /// says why something went wrong, in the middle of the window
  void _tell(BuildContext context, String message) {
    showConfirmDialog(
      context,
      theme: theme,
      message: message,
      buttons: const ['OK'],
    );
  }

  /// asks for a name at the top of the window; [check] is why a name will not
  /// do, and [run] does the work with one that will, and returns what went
  /// wrong
  void _ask(
    BuildContext context, {
    required String hint,
    required String Function(String name) prompt,
    required String? Function(String name) check,
    required Future<String?> Function(String name) run,
    String initialText = '',
  }) {
    showInputPicker(
      context,
      theme: theme,
      top: _top,
      hint: hint,
      initialText: initialText,
      describe: (text) => check(text) ?? prompt(text.trim()),
      onSubmitted: (text) async {
        if (check(text) != null) {
          return;
        }
        final error = await run(text);
        if (error != null && context.mounted) {
          _tell(context, error);
        }
      },
    );
  }

  Future<void> _confirmRemove(
    BuildContext context, {
    required String message,
    required List<String> details,
    required Future<String?> Function() run,
  }) async {
    final choice = await showConfirmDialog(
      context,
      theme: theme,
      message: message,
      details: details,
      buttons: const ['Remove', 'Cancel'],
    );
    if (choice != 0) {
      return;
    }
    final error = await run();
    if (error != null && context.mounted) {
      _tell(context, error);
    }
  }

  /// the menu of a choice, and what can be done with the choices
  Widget _managed({
    required Widget menu,
    required VoidCallback onNew,
    required VoidCallback? onRename,
    required VoidCallback? onRemove,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // the menu gives way when the row is narrow, the links do not
        Flexible(child: menu),
        const SizedBox(width: 14),
        LinkButton(theme: theme, label: 'New', onTap: onNew),
        const SizedBox(width: 12),
        LinkButton(theme: theme, label: 'Rename', onTap: onRename),
        const SizedBox(width: 12),
        LinkButton(theme: theme, label: 'Remove', onTap: onRemove),
      ],
    );
  }

  Widget _fontMenu(String value, ValueChanged<String> onChanged) {
    final fonts = controller.fonts;
    return DropdownControl<String>(
      theme: theme,
      value: value,
      options: [
        for (final family in {...fonts, value}) (family, family),
      ],
      onChanged: onChanged,
    );
  }

  Widget _size(String label, String role, double value) {
    return SettingRow(
      theme: theme,
      label: label,
      control: StepperControl(
        theme: theme,
        text: _number(value),
        slider: SliderSpec(
          value: value,
          min: ThemeController.minFontSize,
          max: ThemeController.maxFontSize,
          divisions: (ThemeController.maxFontSize - ThemeController.minFontSize)
              .round(),
          onChanged: (v) => controller.setFontSize(role, v.roundToDouble()),
        ),
        onMinus: value > ThemeController.minFontSize
            ? () => controller.setFontSize(role, value - 1)
            : null,
        onPlus: value < ThemeController.maxFontSize
            ? () => controller.setFontSize(role, value + 1)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themes = controller.themes;
    final palettes = controller.palettes;
    final themeName = controller.themeName;
    final palette = controller.palette;
    const gap = SizedBox(height: 24);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSection(
          theme: theme,
          title: 'Theme',
          rows: [
            SettingRow(
              theme: theme,
              label: 'Theme',
              control: _managed(
                menu: DropdownControl<String>(
                  theme: theme,
                  value: themeName,
                  options: [for (final name in themes) (name, name)],
                  onChanged: controller.switchTheme,
                ),
                onNew: () => _ask(
                  context,
                  hint: 'Name the new theme...',
                  prompt: (name) => name.isEmpty
                      ? 'Copies "$themeName"'
                      : 'Enter to copy "$themeName" as "$name"',
                  check: controller.validateThemeName,
                  run: controller.createTheme,
                ),
                onRename: controller.canChangeTheme
                    ? () => _ask(
                        context,
                        hint: 'Rename the theme...',
                        initialText: themeName,
                        prompt: (name) => 'Enter to rename it to "$name"',
                        check: (name) =>
                            controller.validateThemeName(name, renaming: true),
                        run: controller.renameTheme,
                      )
                    : null,
                onRemove: controller.canChangeTheme
                    ? () => _confirmRemove(
                        context,
                        message: 'Remove the theme "$themeName"?',
                        details: const [
                          'Its palettes, fonts and icons are removed with it.',
                        ],
                        run: controller.deleteTheme,
                      )
                    : null,
              ),
            ),
            SettingRow(
              theme: theme,
              label: 'Palette',
              control: _managed(
                menu: DropdownControl<String>(
                  theme: theme,
                  value: palette,
                  width: 260,
                  options: [for (final name in palettes) (name, name)],
                  onChanged: controller.setPalette,
                  leadingFor: (name) {
                    final colors = controller.paletteColors(name);
                    return colors == null
                        ? null
                        : PalettePreview(colors: colors, border: theme.border);
                  },
                ),
                onNew: () => _ask(
                  context,
                  hint: 'Name the new palette...',
                  prompt: (name) => name.isEmpty
                      ? 'Copies the colors in use'
                      : 'Enter to save the colors in use as "$name"',
                  check: controller.validatePaletteName,
                  run: controller.createPalette,
                ),
                onRename: () => _ask(
                  context,
                  hint: 'Rename the palette...',
                  initialText: palette,
                  prompt: (name) => 'Enter to rename it to "$name"',
                  check: (name) =>
                      controller.validatePaletteName(name, renaming: true),
                  run: controller.renamePalette,
                ),
                onRemove: palettes.length > 1
                    ? () => _confirmRemove(
                        context,
                        message: 'Remove the palette "$palette"?',
                        details: const [],
                        run: controller.deletePalette,
                      )
                    : null,
              ),
            ),
          ],
        ),
        gap,
        SettingsSection(
          theme: theme,
          title: 'Colors',
          rows: [
            for (final (role, label) in ThemeController.paletteRoles)
              SettingRow(
                theme: theme,
                label: label,
                control: ColorField(
                  theme: theme,
                  color: controller.colorOf(role),
                  onChanged: (color) => controller.setColor(role, color),
                ),
              ),
          ],
        ),
        gap,
        SettingsSection(
          theme: theme,
          title: 'Window',
          rows: [
            SettingRow(
              theme: theme,
              label: 'Corner radius',
              control: StepperControl(
                theme: theme,
                text: _number(theme.cornerRadius),
                slider: SliderSpec(
                  value: theme.cornerRadius,
                  min: 0,
                  max: _maxRadius,
                  divisions: _maxRadius.round(),
                  onChanged: (v) =>
                      controller.setCornerRadius(v.roundToDouble()),
                ),
                onMinus: theme.cornerRadius > 0
                    ? () => controller.setCornerRadius(theme.cornerRadius - 1)
                    : null,
                onPlus: theme.cornerRadius < _maxRadius
                    ? () => controller.setCornerRadius(theme.cornerRadius + 1)
                    : null,
              ),
            ),
            SettingRow(
              theme: theme,
              label: 'Rounding power',
              control: StepperControl(
                theme: theme,
                text: _number(theme.roundingPower),
                slider: SliderSpec(
                  value: theme.roundingPower,
                  min: ThemeController.minRoundingPower,
                  max: ThemeController.maxRoundingPower,
                  divisions:
                      ((ThemeController.maxRoundingPower -
                                  ThemeController.minRoundingPower) /
                              _powerStep)
                          .round(),
                  onChanged: (v) => controller.setRoundingPower(
                    (v / _powerStep).round() * _powerStep,
                  ),
                ),
                onMinus: theme.roundingPower > ThemeController.minRoundingPower
                    ? () => controller.setRoundingPower(
                        theme.roundingPower - _powerStep,
                      )
                    : null,
                onPlus: theme.roundingPower < ThemeController.maxRoundingPower
                    ? () => controller.setRoundingPower(
                        theme.roundingPower + _powerStep,
                      )
                    : null,
              ),
            ),
            SettingRow(
              theme: theme,
              label: 'Border width',
              control: StepperControl(
                theme: theme,
                text: _number(theme.borderWidth),
                slider: SliderSpec(
                  value: theme.borderWidth,
                  min: 0,
                  max: _maxBorder,
                  divisions: _maxBorder.round(),
                  onChanged: (v) =>
                      controller.setBorderWidth(v.roundToDouble()),
                ),
                onMinus: theme.borderWidth > 0
                    ? () => controller.setBorderWidth(theme.borderWidth - 1)
                    : null,
                onPlus: theme.borderWidth < _maxBorder
                    ? () => controller.setBorderWidth(theme.borderWidth + 1)
                    : null,
              ),
            ),
            SettingRow(
              theme: theme,
              label: 'Window opacity',
              control: StepperControl(
                theme: theme,
                text: '${(theme.backgroundOpacity * 100).round()}%',
                slider: SliderSpec(
                  value: theme.backgroundOpacity,
                  min: _minOpacity,
                  max: 1,
                  divisions: ((1 - _minOpacity) / _opacityStep).round(),
                  onChanged: (v) =>
                      controller.setBackgroundOpacity(_roundOpacity(v)),
                ),
                onMinus: theme.backgroundOpacity > _minOpacity
                    ? () => controller.setBackgroundOpacity(
                        _roundOpacity(theme.backgroundOpacity - _opacityStep),
                      )
                    : null,
                onPlus: theme.backgroundOpacity < 1
                    ? () => controller.setBackgroundOpacity(
                        _roundOpacity(theme.backgroundOpacity + _opacityStep),
                      )
                    : null,
              ),
            ),
            SettingRow(
              theme: theme,
              label: 'Blurred window background',
              control: SwitchControl(
                theme: theme,
                value: theme.acrylic,
                onChanged: controller.setAcrylic,
              ),
            ),
          ],
        ),
        gap,
        SettingsSection(
          theme: theme,
          title: 'Text',
          rows: [
            SettingRow(
              theme: theme,
              label: 'Interface font',
              control: _fontMenu(theme.fontFamily, controller.setFontFamily),
            ),
            SettingRow(
              theme: theme,
              label: 'Editor font',
              control: _fontMenu(
                theme.monospaceFontFamily,
                controller.setMonospaceFontFamily,
              ),
            ),
            _size('Title size', 'title', theme.fontSizeTitle),
            _size('Heading size', 'heading', theme.fontSizeHeading),
            _size('Body size', 'body', theme.fontSizeBody),
            _size('Caption size', 'caption', theme.fontSizeCaption),
          ],
        ),
      ],
    );
  }
}
