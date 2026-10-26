import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'superellipse.dart';

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
        final shape = SuperellipseBorder(
          radius: theme.cornerRadius,
          power: theme.roundingPower,
          side: BorderSide(color: theme.border, width: theme.borderWidth),
        );

        return ClipPath(
          clipper: ShapeBorderClipper(shape: shape),
          child: Container(
            decoration: ShapeDecoration(
              color: theme.backgroundColor,
              shape: SuperellipseBorder(
                radius: theme.cornerRadius,
                power: theme.roundingPower,
              ),
            ),
            foregroundDecoration: ShapeDecoration(shape: shape),
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
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: theme.background,
        border: Border(
          bottom: BorderSide(color: theme.border, width: theme.borderWidth),
        ),
      ),
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
