import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'native/window_effects.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'ui/window_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  final themeController = await ThemeController.load();

  // The runner creates a WS_POPUP window with DWM glass; there is no OS
  // chrome and the rounded corners are painted by WindowShell alone.
  await windowManager.center();

  void applyWindowEffect(AppTheme theme) => WindowEffects.apply(
    acrylic: theme.acrylic,
    cornerRadius: theme.cornerRadius,
    blur: theme.blur,
  );
  applyWindowEffect(themeController.value);
  themeController.addListener(() => applyWindowEffect(themeController.value));

  runApp(NyaxisApp(controller: themeController));
}

class NyaxisApp extends StatelessWidget {
  const NyaxisApp({super.key, required this.controller});

  final ThemeController controller;

  @override
  Widget build(BuildContext context) {
    // rebuild on any theme change
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final theme = controller.value;

        return MaterialApp(
          title: 'Nyaxis',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: theme.accent,
              brightness: Brightness.dark,
            ),
            // otherwise the scaffold paints square corners into the clip
            scaffoldBackgroundColor: Colors.transparent,
            // base styles: primary font + type scale on the Material slots
            fontFamily: theme.fontFamily,
            textTheme: TextTheme(
              titleLarge: theme.titleStyle,
              headlineSmall: theme.headingStyle,
              bodyMedium: theme.bodyStyle,
              bodySmall: theme.captionStyle,
            ),
          ),
          home: WindowShell(controller: controller),
        );
      },
    );
  }
}
