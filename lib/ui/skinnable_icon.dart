import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/theme_controller.dart';

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
  });

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

  File? get _file {
    final dir = ThemeController.directory;
    if (dir == null) {
      return null;
    }
    return _found.putIfAbsent(name, () {
      for (final ext in _extensions) {
        final file = File('${dir.path}\\icons\\$name.$ext');
        if (file.existsSync()) {
          return file;
        }
      }
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
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
