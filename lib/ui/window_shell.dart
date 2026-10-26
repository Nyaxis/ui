import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:window_manager/window_manager.dart';

import '../editor/luau_lsp.dart';
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
  static const _monacoTheme = MonacoTheme('nyaxis');

  MonacoController? _monaco;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_applyMonacoTheme);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_applyMonacoTheme);
    super.dispose();
  }

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// the editor is drawn by monaco, so the palette reaches it as a custom
  /// monaco theme
  Future<void> _applyMonacoTheme() async {
    final monaco = _monaco;
    if (monaco == null) {
      return;
    }
    final theme = widget.controller.value;
    final dark = theme.background.computeLuminance() < 0.5;
    await monaco.defineTheme(
      MonacoThemeDefinition(
        id: _monacoTheme.id,
        base: dark ? MonacoBaseTheme.vsDark : MonacoBaseTheme.vs,
        colors: {
          'editor.background': _hex(theme.background),
          'editor.foreground': _hex(theme.textPrimary),
          'editorGutter.background': _hex(theme.background),
          'editorLineNumber.foreground': _hex(theme.textDim),
          'editorLineNumber.activeForeground': _hex(theme.textPrimary),
          'editorCursor.foreground': _hex(theme.accent),
          'editor.selectionBackground': _hex(theme.border),
          'editor.lineHighlightBackground': _hex(theme.titleBar),
          'editorWidget.background': _hex(theme.titleBar),
          'editorWidget.border': _hex(theme.border),
        },
      ),
    );
    await monaco.setTheme(_monacoTheme);
  }

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
                  body: Column(
                    children: [
                      _titleBar(theme),
                      Expanded(
                        child: MonacoEditor(
                          backgroundColor: theme.background,
                          page: MonacoPageConfig(
                            customCss:
                                'html, body { background: ${_hex(theme.background)} !important; }',
                          ),
                          loadingBuilder: (_) =>
                              ColoredBox(color: theme.background),
                          onReady: (controller) {
                            _monaco = controller;
                            _applyMonacoTheme();
                            attachLuauLsp(controller);
                          },
                          options: EditorOptions(
                            theme: _monacoTheme,
                            fontFamily: theme.monospaceFontFamily,
                            fontSize: theme.fontSizeBody,
                          ),
                        ),
                      ),
                      _bottomBar(theme),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static const _titleBarHeight = 40.0;
  static const _bottomBarHeight = 28.0;

  Widget _bottomBar(AppTheme theme) {
    return Container(
      height: _bottomBarHeight,
      decoration: BoxDecoration(
        color: theme.titleBar,
        border: Border(
          top: BorderSide(color: theme.border, width: theme.borderWidth),
        ),
      ),
      child: Row(
        children: [
          const Spacer(),
          _BarButton(
            name: 'sidebar',
            extent: _bottomBarHeight,
            size: _bottomBarHeight * 0.65,
            hoverInset: 2,
            hoverRadius: 4,
            theme: theme,
            onPressed: () {},
          ),
        ],
      ),
    );
  }

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
          _BarButton(
            name: 'minimize',
            extent: _titleBarHeight,
            size: _titleBarHeight * 0.4,
            theme: theme,
            onPressed: windowManager.minimize,
          ),
          _BarButton(
            name: 'maximize',
            extent: _titleBarHeight,
            size: _titleBarHeight * 0.4,
            theme: theme,
            onPressed: _toggleMaximize,
          ),
          _BarButton(
            name: 'close',
            extent: _titleBarHeight,
            size: _titleBarHeight * 0.4,
            destructive: true,
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

class _BarButton extends StatefulWidget {
  const _BarButton({
    required this.name,
    required this.extent,
    required this.size,
    required this.theme,
    required this.onPressed,
    this.hoverInset = 0,
    this.hoverRadius = 0,
    this.destructive = false,
  });

  final String name;

  /// the button is a square the height of its bar
  final double extent;
  final double size;

  /// space between the button's edge and its hover fill, and the fill's corner
  /// radius
  final double hoverInset;
  final double hoverRadius;

  /// hovers in the theme's red instead of the border color
  final bool destructive;
  final AppTheme theme;
  final VoidCallback onPressed;

  @override
  State<_BarButton> createState() => _BarButtonState();
}

class _BarButtonState extends State<_BarButton> {
  bool _hovered = false;
  bool _pressed = false;

  Color _fillColor(AppTheme theme) {
    if (!_hovered && !_pressed) {
      return Colors.transparent;
    }
    final base = widget.destructive ? theme.red : theme.border;
    if (!_pressed) {
      return base;
    }
    final shift = widget.destructive ? theme.background : theme.textPrimary;
    return Color.alphaBlend(
      shift.withValues(alpha: widget.destructive ? 0.2 : 0.1),
      base,
    );
  }

  /// a button with an inset hover is a rounded square, otherwise the fill
  /// covers the whole button
  Widget _hoverFill(AppTheme theme) {
    final onRed = widget.destructive && (_hovered || _pressed);
    final fill = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _fillColor(theme),
        borderRadius: BorderRadius.circular(widget.hoverRadius),
      ),
      child: SkinnableIcon(
        name: widget.name,
        size: widget.size,
        color: onRed ? theme.background : theme.textPrimary,
      ),
    );
    if (widget.hoverInset == 0) {
      return fill;
    }
    return Center(child: AspectRatio(aspectRatio: 1, child: fill));
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: Container(
          width: widget.extent,
          padding: EdgeInsets.all(widget.hoverInset),
          child: _hoverFill(theme),
        ),
      ),
    );
  }
}
