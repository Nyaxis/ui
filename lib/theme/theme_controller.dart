import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

class ThemeController extends ValueNotifier<AppTheme> {
  ThemeController(super.value);

  static const _assetPath = 'assets/theme.json';

  static Future<ThemeController> load() async {
    try {
      final raw = await rootBundle.loadString(_assetPath);
      return ThemeController(
        AppTheme.fromJson(jsonDecode(raw) as Map<String, dynamic>),
      );
    } catch (e) {
      debugPrint(
        'ThemeController.load: could not read $_assetPath, using defaults ($e)',
      );
      return ThemeController(const AppTheme());
    }
  }

  void setCornerRadius(double radius) =>
      value = value.copyWith(cornerRadius: radius);
}
