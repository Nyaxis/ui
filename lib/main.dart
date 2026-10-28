import 'package:flutter/material.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';
import 'package:window_manager/window_manager.dart';

import 'native/window_effects.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'ui/window_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  final themeController = await ThemeController.load();

  // setTitleBarStyle is deliberately never called: it clears the frameless
  // flag the runner relies on
  await windowManager.setMinimumSize(const Size(480, 320));
  await windowManager.center();

  // the webview takes the ui thread's dispatcher queue, which the acrylic
  // backdrop then shares, so it has to start first
  await WebviewController.initializeEnvironment();

  void applyWindowEffect(AppTheme theme) => WindowEffects.apply(
    acrylic: theme.acrylic,
    cornerRadius: theme.cornerRadius,
    roundingPower: theme.roundingPower,
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
