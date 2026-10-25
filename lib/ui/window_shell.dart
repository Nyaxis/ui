import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

class WindowShell extends StatefulWidget {
  const WindowShell({super.key, required this.controller});

  final ThemeController controller;

  @override
  State<WindowShell> createState() => _WindowShellState();
}

class _WindowShellState extends State<WindowShell> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final theme = widget.controller.value;
        final windowRadius = BorderRadius.circular(theme.cornerRadius);

        return ClipRRect(
          borderRadius: windowRadius,
          child: Container(
            decoration: BoxDecoration(
              color: theme.background,
              borderRadius: windowRadius,
              border: Border.all(color: theme.border, width: theme.borderWidth),
            ),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: _titleBar(theme),
            ),
          ),
        );
      },
    );
  }

  Widget _titleBar(AppTheme theme) {
    return SizedBox(
      height: 40,
      child: DragToMoveArea(
        child: Row(
          children: [
            const SizedBox(width: 14),
            Text('Nyaxis', style: theme.titleStyle),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
