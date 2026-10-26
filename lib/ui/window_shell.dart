import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'skinnable_icon.dart';
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

        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: ShapeDecoration(shape: shape),
          child: ClipPath(
            clipper: ShapeBorderClipper(shape: shape),
            child: ColoredBox(
              color: theme.backgroundColor,
              child: Padding(
                padding: EdgeInsets.all(theme.borderWidth),
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  body: _titleBar(theme),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static const _titleBarHeight = 40.0;

  Widget _titleBar(AppTheme theme) {
    return Container(
      height: _titleBarHeight,
      decoration: BoxDecoration(
        color: theme.titleBar,
        border: Border(
          bottom: BorderSide(color: theme.border, width: theme.borderWidth),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Text('Nyaxis', style: theme.titleStyle),
                  const Spacer(),
                ],
              ),
            ),
          ),
          _WindowButton(
            name: 'minimize',
            theme: theme,
            onPressed: windowManager.minimize,
          ),
          _WindowButton(
            name: 'maximize',
            theme: theme,
            onPressed: _toggleMaximize,
          ),
          _WindowButton(
            name: 'close',
            theme: theme,
            onPressed: windowManager.close,
          ),
        ],
      ),
    );
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.name,
    required this.theme,
    required this.onPressed,
  });

  final String name;
  final AppTheme theme;
  final VoidCallback onPressed;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          alignment: Alignment.center,
          color: _hovered ? theme.border : Colors.transparent,
          child: SkinnableIcon(
            name: widget.name,
            size: _WindowShellState._titleBarHeight * 0.4,
            color: theme.textPrimary,
          ),
        ),
      ),
    );
  }
}
