import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:window_manager/window_manager.dart';

import '../editor/editor_tabs.dart';
import '../editor/keymap.dart';
import '../editor/luau_lsp.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'deferred_size.dart';
import 'skinnable_icon.dart';
import 'superellipse.dart';

class WindowShell extends StatefulWidget {
  const WindowShell({super.key, required this.controller});

  final ThemeController controller;

  @override
  State<WindowShell> createState() => _WindowShellState();
}

class _WindowShellState extends State<WindowShell> with WindowListener {
  static const _monacoTheme = MonacoTheme('nyaxis');

  MonacoController? _monaco;
  final _tabs = EditorTabs();
  final _keymap = Keymap();

  // only picks the icon for now, there is no sidebar to show yet
  bool _sidebarOpen = false;

  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_applyMonacoTheme);
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    widget.controller.removeListener(_applyMonacoTheme);
    _tabs.dispose();
    _keymap.dispose();
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  /// the documents have to exist before the server connects, so it sees them
  Future<void> _attachEditor(MonacoController controller) async {
    _keymap.on('workspace::Save', _tabs.save);
    await _keymap.attach(controller);
    await _tabs.attach(controller);
    await connectLuauLsp(controller);
  }

  /// `#rrggbb`, with an alpha suffix when [opacity] is given
  static String _hex(Color c, [double? opacity]) {
    final rgb = (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    final alpha = opacity == null
        ? ''
        : (opacity * 255).round().toRadixString(16).padLeft(2, '0');
    return '#$rgb$alpha';
  }

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
          // the window paints the background, so its opacity applies
          'editor.background': '#00000000',
          'editor.foreground': _hex(theme.textPrimary),
          'editorGutter.background': '#00000000',
          'editorLineNumber.foreground': _hex(theme.lineNumber),
          'editorLineNumber.activeForeground': _hex(theme.accent),
          'editorCursor.foreground': _hex(theme.accent),
          'editor.selectionBackground': _hex(
            theme.selection,
            dark ? 0.25 : 0.3,
          ),
          'editor.lineHighlightBackground': _hex(theme.textPrimary, 0.07),
          // the focused line is outlined in this color
          'focusBorder': '#00000000',
          'editorIndentGuide.background1': _hex(theme.border, 0.6),
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
        // a window that fills the screen has no corners or edge to draw
        final borderWidth = _maximized ? 0.0 : theme.borderWidth;
        final shape = SuperellipseBorder(
          radius: _maximized ? 0 : theme.cornerRadius,
          power: theme.roundingPower,
          side: _maximized
              ? BorderSide.none
              : BorderSide(color: theme.border, width: theme.borderWidth),
        );

        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: ShapeDecoration(shape: shape),
          child: ClipPath(
            clipper: ShapeBorderClipper(shape: shape),
            child: ColoredBox(
              color: theme.backgroundColor,
              child: Padding(
                padding: EdgeInsets.all(borderWidth),
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  body: Column(
                    children: [
                      _titleBar(theme),
                      _tabBar(theme),
                      Expanded(
                        // the webview is slow to resize, so it waits for the
                        // window to stop being dragged
                        child: DeferredSize(
                          child: MonacoEditor(
                            backgroundColor: Colors.transparent,
                            page: const MonacoPageConfig(
                              customCss: 'html, body { background: transparent !important; }',
                            ),
                            loadingBuilder: (_) => const SizedBox.expand(),
                            onReady: (controller) {
                              setState(() => _monaco = controller);
                              _applyMonacoTheme();
                              _attachEditor(controller);
                            },
                            options: EditorOptions(
                              theme: _monacoTheme,
                              fontFamily: theme.monospaceFontFamily,
                              fontSize: theme.fontSizeBody,
                            ),
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
  static const _tabBarHeight = 34.0;

  /// the selected tab shares the editor's color, so it reads as part of it
  /// and breaks the line under the other tabs
  Widget _tabBar(AppTheme theme) {
    final line = BorderSide(color: theme.border, width: theme.borderWidth);
    return ListenableBuilder(
      listenable: _tabs,
      builder: (context, _) => Container(
        height: _tabBarHeight,
        color: theme.titleBar,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: theme.borderWidth,
              child: ColoredBox(color: theme.border),
            ),
            Row(
              children: [
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var i = 0; i < _tabs.tabs.length; i++)
                        _Tab(
                          tab: _tabs.tabs[i],
                          selected: i == _tabs.active,
                          theme: theme,
                          line: line,
                          onSelect: () => _tabs.select(i),
                          onClose: () => _tabs.close(i),
                        ),
                    ],
                  ),
                ),
                // the line along the bottom is not part of the space to center in
                Padding(
                  padding: EdgeInsets.only(bottom: theme.borderWidth),
                  child: _BarButton(
                    name: 'add',
                    extent: _tabBarHeight,
                    size: _tabBarHeight * 0.5,
                    hoverInset: 5,
                    hoverRadius: 4,
                    theme: theme,
                    onPressed: _tabs.newTab,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// cursor position, encoding and language of the active document
  Widget _status(AppTheme theme, MonacoController monaco) {
    return ValueListenableBuilder<MonacoLiveStats>(
      valueListenable: monaco.stats,
      builder: (context, stats, _) {
        final cursor = stats.cursorPosition;
        final language = stats.language;
        return ListenableBuilder(
          listenable: _tabs,
          builder: (context, _) => Row(
            children: [
              for (final text in [
                if (cursor != null) 'Ln ${cursor.line}, Col ${cursor.column}',
                if (_tabs.indentation.isNotEmpty) _tabs.indentation,
                if (_tabs.active < _tabs.tabs.length)
                  _tabs.tabs[_tabs.active].encoding.label,
                if (language != null) language.label ?? language.id,
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(text, style: theme.captionStyle),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _bottomBar(AppTheme theme) {
    final monaco = _monaco;
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
          if (monaco != null) _status(theme, monaco),
          Container(
            width: theme.borderWidth,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: theme.border,
          ),
          _BarButton(
            name: _sidebarOpen ? 'sidebar-open' : 'sidebar-closed',
            extent: _bottomBarHeight,
            // the icon's own grid, so its lines land on whole pixels
            size: 16,
            hoverInset: 2,
            hoverRadius: 4,
            dim: true,
            theme: theme,
            onPressed: () => setState(() => _sidebarOpen = !_sidebarOpen),
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
            name: _maximized ? 'restore' : 'maximize',
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

class _Tab extends StatefulWidget {
  const _Tab({
    required this.tab,
    required this.selected,
    required this.theme,
    required this.line,
    required this.onSelect,
    required this.onClose,
  });

  final EditorTab tab;
  final bool selected;
  final AppTheme theme;
  final BorderSide line;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  static const _closeSize = 14.0;
  static const _closeExtent = 20.0;

  bool _hovered = false;

  /// the tab bar's color, slightly darker
  Color _inactive(AppTheme theme) {
    final hsl = HSLColor.fromColor(theme.titleBar);
    return hsl.withLightness((hsl.lightness - 0.03).clamp(0.0, 1.0)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final color = widget.selected ? theme.textPrimary : theme.textDim;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        child: CustomPaint(
          painter: widget.selected
              ? _ReplacePainter(theme.backgroundColor)
              : null,
          child: Container(
            padding: const EdgeInsets.only(left: 14, right: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.selected ? null : _inactive(theme),
              border: Border(
                right: widget.line,
                // the selected tab keeps the space, so the text doesn't shift
                bottom: widget.selected
                    ? widget.line.copyWith(color: Colors.transparent)
                    : widget.line,
              ),
            ),
            child: Row(
              children: [
                if (widget.tab.dirty)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: theme.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                Text(
                  widget.tab.name,
                  style: theme.bodyStyle.copyWith(color: color),
                ),
                // the slot is always there, so hovering never resizes the tab
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Opacity(
                    opacity: _hovered ? 1 : 0,
                    child: _BarButton(
                      name: 'close',
                      extent: _closeExtent,
                      size: _closeSize,
                      hoverInset: 1,
                      hoverRadius: 4,
                      theme: theme,
                      onPressed: widget.onClose,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// replaces what is under it instead of blending, so the tab bar's opaque
/// fill doesn't show through the selected tab when the background is
/// translucent
class _ReplacePainter extends CustomPainter {
  const _ReplacePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = color
        ..blendMode = BlendMode.src,
    );
  }

  @override
  bool shouldRepaint(_ReplacePainter oldDelegate) => oldDelegate.color != color;
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
    this.dim = false,
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

  /// draws the icon in the dim text color until the button is hovered
  final bool dim;
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
    if (widget.destructive) {
      return _pressed
          ? Color.alphaBlend(theme.background.withValues(alpha: 0.2), theme.red)
          : theme.red;
    }
    return (_pressed ? theme.active : theme.hover).withValues(
      alpha: _pressed ? 0.6 : 0.3,
    );
  }

  /// a button with an inset hover is a rounded square, otherwise the fill
  /// covers the whole button
  Widget _hoverFill(AppTheme theme) {
    final onRed = widget.destructive && (_hovered || _pressed);
    // only the visible fill reacts, not the inset around it
    final fill = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _fillColor(theme),
            borderRadius: BorderRadius.circular(widget.hoverRadius),
          ),
          child: SkinnableIcon(
            name: widget.name,
            size: widget.size,
            color: onRed
                ? theme.background
                : (widget.dim && !_hovered && !_pressed
                      ? theme.textDim
                      : theme.textPrimary),
          ),
        ),
      ),
    );
    if (widget.hoverInset == 0) {
      return fill;
    }
    return Center(child: AspectRatio(aspectRatio: 1, child: fill));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.extent,
      padding: EdgeInsets.all(widget.hoverInset),
      child: _hoverFill(widget.theme),
    );
  }
}
