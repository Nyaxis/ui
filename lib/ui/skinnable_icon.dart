import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/theme_controller.dart';
import 'gamma_icon.dart';

/// draws `icons\<name>.<ext>` from the active theme's folder when it exists,
/// otherwise the bundled `assets/icons/<name>/<name>-<size>.svg` closest to
/// [size]; svgs are tinted through `currentColor`, raster images are drawn as
/// they are
class SkinnableIcon extends StatelessWidget {
  const SkinnableIcon({
    super.key,
    required this.name,
    required this.size,
    required this.color,
    this.plain = false,
  });

  /// whether the icon is drawn as it is, and not with the corrected edges that
  /// every svg icon has otherwise; [GammaIcon] draws the plain one until its
  /// own is ready
  final bool plain;

  static const _extensions = [
    'svg',
    'png',
    'webp',
    'jpg',
    'jpeg',
    'gif',
    'bmp',
  ];

  static final _found = <String, File?>{};

  final String name;
  final double size;
  final Color color;

  /// whether the theme has a file of its own for the icon [name]
  static bool hasSkin(String name) => _skin(name) != null;

  /// the file that the theme has for the icon [name], or null
  static File? skinFile(String name) => _skin(name);

  /// whether the file that the theme has for the icon [name] is an svg, which
  /// is drawn with the corrected edges as the bundled icons are; the other
  /// kinds are images, which are drawn as they are
  static bool skinIsSvg(String name) =>
      _skin(name)?.path.toLowerCase().endsWith('.svg') ?? false;

  /// where the theme's folder is; a test can say another
  @visibleForTesting
  static Directory? Function() themeDirectory = () => ThemeController.directory;

  /// forgets which files were found, as a test that changed [themeDirectory]
  /// needs
  @visibleForTesting
  static void forgetFiles() => _found.clear();

  File? get _file => _skin(name);

  static File? _skin(String name) {
    final dir = themeDirectory();
    if (dir == null) {
      return null;
    }
    // by theme too, since another theme has icons of its own
    return _found.putIfAbsent('${dir.path}|$name', () {
      for (final ext in _extensions) {
        final s = Platform.pathSeparator;
        final file = File('${dir.path}${s}icons$s$name.$ext');
        if (file.existsSync()) {
          return file;
        }
      }
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // every icon that is an svg has the corrected edges, the bundled ones and
    // those that the theme has files for, which includes the bundled ones that
    // the default theme is given as files; an image of the theme's own is drawn
    // as it is
    if (!plain && (!hasSkin(name) || skinIsSvg(name))) {
      return GammaIcon(name: name, size: size, color: color);
    }
    final theme = SvgTheme(currentColor: color);
    final bundledSize = size >= 32 ? 32 : (size >= 22 ? 22 : 16);
    final bundled = SvgPicture.asset(
      'assets/icons/$name/$name-$bundledSize.svg',
      width: size,
      height: size,
      theme: theme,
    );

    final file = _file;
    if (file == null) {
      return bundled;
    }
    if (file.path.toLowerCase().endsWith('.svg')) {
      return SvgPicture.file(
        file,
        width: size,
        height: size,
        theme: theme,
        errorBuilder: (_, _, _) => bundled,
      );
    }
    return Image.file(
      file,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => bundled,
    );
  }
}
