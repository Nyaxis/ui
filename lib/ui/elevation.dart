import 'package:flutter/painting.dart';

import '../theme/app_theme.dart';

/// whether the theme is a light one, which has softer shadows
bool isLightTheme(AppTheme theme) => theme.background.computeLuminance() > 0.5;

/// the shadow of what is raised above the window, such as a menu or a popover
List<BoxShadow> elevatedShadows(AppTheme theme) {
  final light = isLightTheme(theme);
  return [
    const BoxShadow(
      offset: Offset(0, 2),
      blurRadius: 3,
      color: Color.fromRGBO(0, 0, 0, 0.12),
    ),
    BoxShadow(
      offset: const Offset(0, 1),
      color: Color.fromRGBO(0, 0, 0, light ? 0.03 : 0.06),
    ),
  ];
}

/// the shadow of what is above all else in the window, such as a dialog or a
/// picker
List<BoxShadow> modalShadows(AppTheme theme) {
  final light = isLightTheme(theme);
  return [
    BoxShadow(
      offset: const Offset(0, 2),
      blurRadius: 3,
      color: Color.fromRGBO(0, 0, 0, light ? 0.06 : 0.12),
    ),
    BoxShadow(
      offset: const Offset(0, 3),
      blurRadius: 6,
      color: Color.fromRGBO(0, 0, 0, light ? 0.06 : 0.08),
    ),
    const BoxShadow(
      offset: Offset(0, 6),
      blurRadius: 12,
      color: Color.fromRGBO(0, 0, 0, 0.04),
    ),
    BoxShadow(
      offset: const Offset(0, 1),
      color: Color.fromRGBO(0, 0, 0, light ? 0.04 : 0.12),
    ),
  ];
}
