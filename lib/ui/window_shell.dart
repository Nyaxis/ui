import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:window_manager/window_manager.dart';

import '../editor/editor_tabs.dart';
import '../native_editor/cursor_summary.dart';
import '../native_editor/editor_controller.dart' show DiagnosticColors;
import '../native_editor/editor_style.dart';
import '../native_editor/editor_view.dart';
import '../editor/keymap.dart';
import '../editor/luau_language_service.dart';
import '../editor/text_encoding.dart';
import '../native/backend.dart';
import '../settings/config_file.dart';
import '../settings/editor_settings.dart';
import '../syntax/syntax_layer.dart';
import '../syntax/syntax_palette.dart';
import '../syntax/syntax_tree.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'clickable.dart';
import 'context_menu.dart';
import 'dialog.dart';
import 'hover_tooltip.dart';
import 'picker.dart';
import 'settings_view.dart';
import 'sidebar.dart';
import 'skinnable_icon.dart';
import 'superellipse.dart';

/// what the window shows beside the sidebar
enum _View { editor, settings }

/// a button of the bottom bar, with the state that `config.json` keeps
class _BottomButton {
  _BottomButton(
    this.id,
    this.label, {
    this.action,
    this.onPressed,
    this.canHide = true,
    this.dock,
  });

  /// the key of its settings in `config.json`
  final String id;

  /// what the button does, as its menu entry and tooltip name it
  final String label;

  /// the keymap action that does the same, whose keys the tooltip shows
  final String? action;

  /// what left clicking it does, nothing when null
  final VoidCallback? onPressed;

  /// whether its menu offers to hide it
  final bool canHide;

  /// the side it is docked to, null when it cannot be docked
  _Dock? dock;

  bool hidden = false;
}

/// the side of the window that something is docked to
enum _Dock { left, right }

/// names a button on hover, with the [keys] of its action beside the label
Widget _tip({
  required AppTheme theme,
  required String label,
  required String? keys,
  required Widget child,
  bool enabled = true,
}) {
  return HoverTooltip(
    theme: theme,
    title: label,
    keys: keys,
    enabled: enabled,
    child: child,
  );
}

class WindowShell extends StatefulWidget {
  const WindowShell({super.key, required this.controller});

  final ThemeController controller;

  @override
  State<WindowShell> createState() => _WindowShellState();
}

class _WindowShellState extends State<WindowShell> with WindowListener {
  /// keeps the editor alive when the sidebar docks to the other side, which
  /// moves it among the row's children
  final _editorKey = GlobalKey();

  final _tabs = EditorTabs();
  final _sidebarButtonKey = GlobalKey();
  final _keymap = Keymap();
  Backend? _backend;
  LuauLanguageService? _luau;
  String? _presenceFile;

  bool _sidebarOpen = false;
  double _sidebarWidth = 240;

  var _view = _View.editor;
  final _config = ConfigFile.user();
  late final _editorSettings = EditorSettings(_config);
  late final _syntaxStyles = SyntaxStyleSettings(_config);

  bool _maximized = false;
  bool _newMenuOpen = false;

  late final _cursor = _BottomButton(
    'cursor',
    'Go to Line/Column',
    action: 'go_to_line::Toggle',
    onPressed: _openGoToLine,
  );
  late final _indentation = _BottomButton(
    'indentation',
    'Select Indentation',
    action: 'indentation_selector::Toggle',
    onPressed: _openIndentationPicker,
  );
  late final _encoding = _BottomButton(
    'encoding',
    'Reopen with Encoding',
    action: 'encoding_selector::Toggle',
    onPressed: _openEncodingPicker,
  );
  late final _lineEnding = _BottomButton(
    'lineEnding',
    'Select Line Ending',
    action: 'line_ending_selector::Toggle',
    onPressed: _openLineEndingPicker,
  );
  late final _language = _BottomButton(
    'language',
    'Select Language',
    action: 'language_selector::Toggle',
  );
  late final _sidebar = _BottomButton(
    'sidebar',
    'Toggle Sidebar',
    onPressed: () => setState(() => _sidebarOpen = !_sidebarOpen),
    canHide: false,
    dock: _Dock.left,
  );
  late final _buttons = [
    _cursor,
    _indentation,
    _encoding,
    _lineEnding,
    _language,
    _sidebar,
  ];

  File? get _settingsFile {
    final appData = Platform.environment['APPDATA'];
    return appData == null ? null : File('$appData\\Nyaxis\\config.json');
  }

  /// the settings of each bottom bar button in `config.json`, like
  /// `"sidebar": {"dock": "left", "width": 240}` or `"language": {"hidden":
  /// true}`; unknown
  /// or malformed values are ignored
  Future<void> _loadSettings() async {
    final file = _settingsFile;
    if (file == null || !file.existsSync()) {
      return;
    }
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      setState(() {
        for (final button in _buttons) {
          final settings = json[button.id];
          if (settings is! Map) {
            continue;
          }
          final dock = _Dock.values.asNameMap()[settings['dock']];
          if (dock != null && button.dock != null) {
            button.dock = dock;
          }
          if (button.canHide && settings['hidden'] == true) {
            button.hidden = true;
          }
          final width = settings['width'];
          if (button == _sidebar && width is num) {
            _sidebarWidth = width.toDouble().clamp(
              SidebarPanel.minWidth,
              SidebarPanel.maxWidth,
            );
          }
        }
      });
    } catch (e) {
      debugPrint('WindowShell: unreadable ${file.path} ($e)');
    }
  }

  /// the rest of `config.json` is kept as it is
  Future<void> _saveSettings() async {
    final file = _settingsFile;
    if (file == null) {
      return;
    }
    try {
      final json = file.existsSync()
          ? jsonDecode(await file.readAsString()) as Map<String, dynamic>
          : <String, dynamic>{};
      for (final button in _buttons) {
        final existing = json[button.id];
        final settings = existing is Map<String, dynamic>
            ? existing
            : <String, dynamic>{};
        final dock = button.dock;
        if (dock != null) {
          settings['dock'] = dock.name;
        }
        if (button.canHide) {
          settings['hidden'] = button.hidden;
        }
        if (button == _sidebar) {
          settings['width'] = _sidebarWidth;
        }
        if (settings.isNotEmpty) {
          json[button.id] = settings;
        }
      }
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(json),
        flush: true,
      );
    } catch (e) {
      debugPrint('WindowShell: cannot save ${file.path} ($e)');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _startEditor();
    _editorSettings.load();
    _editorSettings.addListener(_applyEditorOptions);
    _tabs.confirmClose = _confirmClose;
    widget.controller.addListener(_applyEditorOptions);
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    _tabs.addListener(_updatePresence);
    Backend.start().then((backend) {
      if (!mounted) {
        backend.dispose();
        return;
      }
      setState(() => _backend = backend);
      _luau = LuauLanguageService(backend);
      _tabs.luau = _luau;
      _updatePresence();
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    widget.controller.removeListener(_applyEditorOptions);
    widget.controller.removeListener(_applySyntax);
    widget.controller.removeListener(_applyOccurrenceColor);
    _tabs.removeListener(_applyOccurrenceColor);
    _syntaxStyles.removeListener(_applySyntax);
    _tabs.removeListener(_applySyntax);
    _editorSettings.removeListener(_applyEditorOptions);
    _editorSettings.dispose();
    _tabs.removeListener(_updatePresence);
    _luau?.dispose().ignore();
    _backend?.dispose();
    _tabs.dispose();
    _keymap.dispose();
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    await windowManager.hide();
    _backend?.dispose();
    // what was changed a moment ago has not been written yet
    await Future.wait([widget.controller.flush(), _config.flush()]);
    await windowManager.destroy();
  }

  /// tells the backend which script is open, skipping redundant updates
  void _updatePresence() {
    final file = _tabs.active < _tabs.tabs.length
        ? _tabs.tabs[_tabs.active].name
        : null;
    if (file == _presenceFile) {
      return;
    }
    _presenceFile = file;
    _backend?.presence(file);
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  /// whether the scripts are open, which they are once the editor is started
  bool _editorStarted = false;

  Future<void> _startEditor() async {
    await _attachNativeEditor();
    if (!mounted) {
      return;
    }
    setState(() => _editorStarted = true);
    await _loadSyntaxQuery();
  }

  /// what the parser finds to color, as the grammar says
  String? _syntaxQuery;

  /// set when the parser cannot be used, which is not tried again
  bool _syntaxUnavailable = false;
  AppTheme? _syntaxFor;
  Map<String, String>? _syntaxStylesFor;
  SyntaxTheme? _syntaxTheme;

  Future<void> _loadSyntaxQuery() async {
    try {
      _syntaxQuery = await rootBundle.loadString(
        'native/tree_sitter/queries/luau/highlights.scm',
      );
    } catch (e) {
      debugPrint('WindowShell: cannot read the syntax query ($e)');
      _syntaxUnavailable = true;
      return;
    }
    await _syntaxStyles.load();
    _tabs.addListener(_applySyntax);
    widget.controller.addListener(_applySyntax);
    _syntaxStyles.addListener(_applySyntax);
    _applySyntax();
  }

  /// gives the tabs the syntax colors, and the colors of the theme
  void _applySyntax() {
    final query = _syntaxQuery;
    if (query == null || _syntaxUnavailable) {
      return;
    }
    final theme = widget.controller.value;
    final styles = _syntaxStyles.value;
    if (!identical(_syntaxFor, theme) || !identical(_syntaxStylesFor, styles)) {
      _syntaxFor = theme;
      _syntaxStylesFor = styles;
      _syntaxTheme = syntaxThemeFor(theme, fontStyles: styles);
    }
    final syntaxTheme = _syntaxTheme!;
    for (final tab in _tabs.tabs) {
      final controller = tab.document.controller;
      final layer = controller.syntax;
      if (layer == null) {
        String? failure;
        final attached = SyntaxLayer.attach(
          controller.buffer,
          syntaxTheme,
          query,
          error: (error) => failure = error,
        );
        if (attached == null) {
          debugPrint('WindowShell: no syntax colors ($failure)');
          _syntaxUnavailable = true;
          return;
        }
        controller.setSyntax(attached);
      } else if (!identical(layer.theme, syntaxTheme)) {
        layer.theme = syntaxTheme;
        controller.redraw();
      }
    }
  }

  /// the tab size the editor was last given, so that a change of theme does
  /// not put it back
  int? _nativeTabSize;

  /// the other places a selected text is, are the accent behind the text; the
  /// diagnostics are underlined in the colors of how bad they are
  void _applyOccurrenceColor() {
    final theme = widget.controller.value;
    final color = theme.accent.withValues(alpha: 0x17 / 255).toARGB32();
    final diagnostics = DiagnosticColors(
      error: theme.red.toARGB32(),
      warning: theme.warning.toARGB32(),
      information: theme.info.toARGB32(),
      hint: theme.hint.toARGB32(),
    );
    for (final tab in _tabs.tabs) {
      tab.document.controller
        ..occurrenceBackground = color
        ..diagnosticColors = diagnostics
        ..unnecessaryCodeFade = _editorSettings.value.unnecessaryCodeFade;
    }
  }

  /// the font size of the editor that flutter draws, when it was changed with
  /// the keys or the wheel, which lasts until the app is closed and is not
  /// saved; null is the one of the settings
  double? _zoomedFontSize;

  static const _minFontSize = 6.0;
  static const _maxFontSize = 100.0;

  /// changes the zoomed size by [step] pixels, from the size that is shown now
  void _zoom(int step) {
    final shown =
        _zoomedFontSize ??
        _editorSettings.value.fontSize ??
        widget.controller.value.fontSizeBody;
    setState(
      () => _zoomedFontSize = (shown + step).clamp(_minFontSize, _maxFontSize),
    );
  }

  void _resetZoom() {
    if (_zoomedFontSize != null) {
      setState(() => _zoomedFontSize = null);
    }
  }

  Future<void> _attachNativeEditor() async {
    _tabs.addListener(_applyOccurrenceColor);
    widget.controller.addListener(_applyOccurrenceColor);
    _bindKeymap();
    _keymap.on('zed::IncreaseBufferFontSize', () async => _zoom(1));
    _keymap.on('zed::DecreaseBufferFontSize', () async => _zoom(-1));
    _keymap.on('zed::ResetBufferFontSize', () async => _resetZoom());
    await _keymap.attachNative(() => _tabs.activeController?.hasFocus ?? false);
    if (mounted) {
      setState(() {});
    }
    await _editorSettings.load();
    _applyEditorOptions();
    await _tabs.start();
  }

  /// what each action does
  void _bindKeymap() {
    _keymap.on('workspace::Save', _tabs.save);
    _keymap.on('workspace::Open', _openFile);
    _keymap.on('go_to_line::Toggle', _openGoToLine);
    _keymap.on('indentation_selector::Toggle', _openIndentationPicker);
    _keymap.on('encoding_selector::Toggle', _openEncodingPicker);
    _keymap.on('line_ending_selector::Toggle', _openLineEndingPicker);
    _keymap.on('pane::CloseOtherItems', () => _tabs.closeOthers(_tabs.active));
    _keymap.on(
      'pane::CloseItemsToTheLeft',
      () => _tabs.closeLeft(_tabs.active),
    );
    _keymap.on(
      'pane::CloseItemsToTheRight',
      () => _tabs.closeRight(_tabs.active),
    );
    _keymap.on('pane::CloseAllItems', _tabs.closeAll);
    _keymap.on('workspace::NewFile', _tabs.newTab);
    _keymap.on('pane::CloseActiveItem', () => _tabs.close(_tabs.active));
    _keymap.on('pane::CloseCleanItems', _tabs.closeClean);
    // the menu of a tab and the keys have each their own name for these
    for (final name in ['workspace::CopyPath', 'editor::CopyPath']) {
      _keymap.on(name, () => _tabs.copyPath(_tabs.active));
    }
    _keymap.on(
      'workspace::CopyRelativePath',
      () => _tabs.copyPath(_tabs.active, relative: true),
    );
    _keymap.on('editor::RevealInFileManager', () => _tabs.reveal(_tabs.active));
    _keymap.on('workspace::ShowEditor', () async => _showView(_View.editor));
    _keymap.on(
      'workspace::ShowSettings',
      () async => _showView(_View.settings),
    );
  }

  void _showView(_View view) {
    if (_view != view) {
      setState(() => _view = view);
    }
  }

  /// gives the editor the settings, which has the theme's font size until one
  /// is set
  void _applyEditorOptions() {
    final size = _editorSettings.value.tabSize;
    if (size != _nativeTabSize) {
      _nativeTabSize = size;
      _tabs.tabSize = size;
      for (final tab in _tabs.tabs) {
        tab.document.controller.setTabSize(size);
      }
    }
    final autoClose = _editorSettings.value.autoClosingBrackets;
    _tabs.autoClose = autoClose;
    for (final tab in _tabs.tabs) {
      tab.document.controller
        ..autoClose = autoClose
        ..unnecessaryCodeFade = _editorSettings.value.unnecessaryCodeFade;
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _setAutoSave(AutoSave value) {
    setState(() => _tabs.autoSave = value);
    _config.update((json) => json['autoSave'] = value.name);
  }

  void _setAutoSaveDelay(Duration value) {
    setState(() => _tabs.autoSaveDelay = value);
    _config.update((json) => json['autoSaveDelay'] = value.inMilliseconds);
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
                      Expanded(
                        child: Row(
                          children: [
                            if (_sidebarOpen && _sidebar.dock == _Dock.left)
                              _sidebarPanel(theme),
                            // the editor stays alive under the settings, and the
                            // key keeps this view's state when the sidebar
                            // docks to the other side
                            Expanded(
                              key: const ValueKey('content'),
                              child: IndexedStack(
                                index: _view.index,
                                sizing: StackFit.expand,
                                children: [
                                  Column(
                                    children: [
                                      _tabBar(theme),
                                      Expanded(child: _editor(theme)),
                                    ],
                                  ),
                                  _settingsView(theme),
                                ],
                              ),
                            ),
                            if (_sidebarOpen && _sidebar.dock == _Dock.right)
                              _sidebarPanel(theme),
                          ],
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

  Widget _sidebarPanel(AppTheme theme) {
    return SidebarPanel(
      theme: theme,
      width: _sidebarWidth,
      onLeft: _sidebar.dock == _Dock.left,
      onResize: (width) => setState(
        () => _sidebarWidth = width.clamp(
          SidebarPanel.minWidth,
          SidebarPanel.maxWidth,
        ),
      ),
      onResizeEnd: _saveSettings,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            for (final (view, icon, label, action) in [
              (_View.editor, 'editor', 'Editor', 'workspace::ShowEditor'),
              (
                _View.settings,
                'settings',
                'Settings',
                'workspace::ShowSettings',
              ),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: SidebarItem(
                  theme: theme,
                  icon: icon,
                  label: label,
                  keys: _keymap.keysFor(action),
                  selected: _view == view,
                  onTap: () => _showView(view),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _settingsView(AppTheme theme) {
    return ListenableBuilder(
      listenable: Listenable.merge([_editorSettings, _syntaxStyles, _tabs]),
      builder: (context, _) => SettingsView(
        theme: theme,
        controller: widget.controller,
        prefs: _editorSettings.value,
        onPrefs: _editorSettings.change,
        syntaxStyles: _syntaxStyles.value,
        onSyntaxStyles: _syntaxStyles.change,
        autoSave: _tabs.autoSave,
        onAutoSave: _setAutoSave,
        autoSaveDelay: _tabs.autoSaveDelay,
        onAutoSaveDelay: _setAutoSaveDelay,
      ),
    );
  }

  /// the colors and the font of the editor that flutter draws
  EditorStyle _nativeStyle(AppTheme theme) {
    final dark = theme.background.computeLuminance() < 0.5;
    final prefs = _editorSettings.value;
    return EditorStyle(
      textStyle: TextStyle(
        fontFamily: theme.monospaceFontFamily,
        fontSize: _zoomedFontSize ?? prefs.fontSize ?? theme.fontSizeBody,
        height: 1.5,
        color: theme.textPrimary,
        fontFeatures: prefs.fontLigatures
            ? null
            : const [FontFeature.disable('liga'), FontFeature.disable('calt')],
      ),
      // the window paints the background, so its opacity applies
      background: const Color(0x00000000),
      selection: theme.selection.withValues(alpha: dark ? 0.25 : 0.3),
      cursor: theme.cursor,
      currentLine: theme.textPrimary.withValues(alpha: 0.07),
      gutterText: theme.lineNumber,
      currentGutterText: theme.accent,
      invisible: theme.textDim,
      // the colors of the scrollbars, which the palettes have in these
      scrollbarTrack: theme.titleBar,
      scrollbarTrackBorder: theme.textPrimary.withValues(alpha: 0.07),
      scrollbarThumb: theme.active.withValues(alpha: 0.5),
      scrollbarThumbHover: theme.disabled,
      scrollbarMarker: theme.info,
      // what pops up over the editor is in the font of the interface, on the
      // raised surface of the theme; there is no color for what has worked in
      // a theme, so the one of strings is used
      // the size is that of the code, as it is for what is laid out inside the
      // editor, so it goes up and down with the zoom keys; the room around the
      // text is in rems and stays as it is
      popoverText: TextStyle(
        fontFamily: theme.fontFamily,
        fontSize: _zoomedFontSize ?? prefs.fontSize ?? theme.fontSizeBody,
        height: EditorStyle.popoverLineHeight,
        fontWeight: FontWeight.w400,
        color: theme.textPrimary,
      ),
      popoverScale: theme.uiFontSize / AppTheme.remPixels,
      popoverRadius: theme.rem(8),
      popoverSurface: theme.acrylic ? const Color(0x00000000) : theme.surface,
      popoverMuted: theme.textDim,
      popoverSuccess: theme.string,
      // the palettes do not have one for a thumb that is pressed, so it is the
      // faint light or dark that the default themes use
      scrollbarThumbActive: dark
          ? const Color(0x23FBFBEB)
          : const Color(0x211F1800),
    );
  }

  Widget _nativeEditorView(AppTheme theme) {
    final controller = _tabs.activeController;
    if (controller == null) {
      return const SizedBox.expand();
    }
    final prefs = _editorSettings.value;
    return EditorView(
      key: ObjectKey(controller),
      controller: controller,
      style: _nativeStyle(theme),
      softWrap: prefs.wordWrap,
      showLineNumbers: prefs.lineNumbers,
      scrollbars: prefs.scrollbar,
      hover: prefs.hover,
      tooltip: (message, child) =>
          _tip(theme: theme, label: message, keys: null, child: child),
      mouseWheelZoom: prefs.mouseWheelZoom,
      onZoom: _zoom,
      autofocus: true,
      onFocusChanged: (focused) {
        if (!focused) {
          _tabs.editorFocusLost();
        }
      },
    );
  }

  Widget _editor(AppTheme theme) {
    if (!_editorStarted) {
      return const SizedBox.expand();
    }
    return ListenableBuilder(
      key: _editorKey,
      listenable: Listenable.merge([_tabs, _editorSettings]),
      builder: (context, _) => _nativeEditorView(theme),
    );
  }

  static const _titleBarHeight = 40.0;
  static const _bottomBarHeight = 28.0;
  static const _tabBarHeight = 40.0;

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
                          onMenu: (position) =>
                              _showTabMenu(context, theme, i, position),
                        ),
                    ],
                  ),
                ),
                // the line along the bottom is not part of the space to center in
                Padding(
                  padding: EdgeInsets.only(bottom: theme.borderWidth),
                  child: Builder(
                    builder: (context) => _BarButton(
                      label: 'New',
                      name: 'add',
                      extent: _tabBarHeight,
                      size: _tabBarHeight * 0.55,
                      hoverInset: 5,
                      hoverRadius: 4,
                      active: _newMenuOpen,
                      theme: theme,
                      onPressed: () => _showNewMenu(context, theme),
                    ),
                  ),
                ),
                for (final (label, name, onPressed) in [
                  ('Inject', 'inject', _inject),
                  ('Execute', 'execute', _execute),
                ])
                  Padding(
                    padding: EdgeInsets.only(bottom: theme.borderWidth),
                    child: _BarButton(
                      label: label,
                      name: name,
                      extent: _tabBarHeight,
                      size: _tabBarHeight * 0.55,
                      hoverInset: 5,
                      hoverRadius: 4,
                      theme: theme,
                      onPressed: onPressed,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _inject() => _backend?.inject();

  Future<void> _execute() async {
    if (_tabs.active >= _tabs.tabs.length) {
      return;
    }
    final script = await _tabs.tabs[_tabs.active].document.getText();
    _backend?.execute(script);
  }

  Future<void> _openFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Luau', extensions: ['lua', 'luau']),
        XTypeGroup(label: 'All files'),
      ],
    );
    if (file != null) {
      await _tabs.openFile(File(file.path));
    }
  }

  /// opens under the button
  void _showNewMenu(BuildContext button, AppTheme theme) {
    final box = button.findRenderObject() as RenderBox;
    setState(() => _newMenuOpen = true);
    showContextMenu(
      button,
      position: box.localToGlobal(Offset(0, box.size.height)),
      theme: theme,
      keysFor: _keymap.keysFor,
      onClosed: () => setState(() => _newMenuOpen = false),
      entries: [
        ContextMenuItem(
          'New File',
          action: 'workspace::NewFile',
          onPressed: _tabs.newTab,
        ),
        ContextMenuItem(
          'Open File',
          action: 'workspace::Open',
          onPressed: _openFile,
        ),
      ],
    );
  }

  void _showTabMenu(
    BuildContext context,
    AppTheme theme,
    int index,
    Offset position,
  ) {
    final hasFile = _tabs.tabs[index].file != null;
    showContextMenu(
      context,
      position: position,
      theme: theme,
      keysFor: _keymap.keysFor,
      entries: [
        ContextMenuItem(
          'Close',
          action: 'pane::CloseActiveItem',
          onPressed: () => _tabs.close(index),
        ),
        ContextMenuItem(
          'Close Others',
          action: 'pane::CloseOtherItems',
          onPressed: _tabs.tabs.length > 1
              ? () => _tabs.closeOthers(index)
              : null,
        ),
        const ContextMenuSeparator(),
        ContextMenuItem(
          'Close Left',
          action: 'pane::CloseItemsToTheLeft',
          onPressed: index > 0 ? () => _tabs.closeLeft(index) : null,
        ),
        ContextMenuItem(
          'Close Right',
          action: 'pane::CloseItemsToTheRight',
          onPressed: index < _tabs.tabs.length - 1
              ? () => _tabs.closeRight(index)
              : null,
        ),
        const ContextMenuSeparator(),
        ContextMenuItem(
          'Close Clean',
          action: 'pane::CloseCleanItems',
          onPressed: _tabs.hasCleanTabs ? _tabs.closeClean : null,
        ),
        ContextMenuItem(
          'Close All',
          action: 'pane::CloseAllItems',
          onPressed: _tabs.closeAll,
        ),
        // a tab with no file has no path to copy and nothing to reveal
        if (hasFile) ...[
          const ContextMenuSeparator(),
          ContextMenuItem(
            'Copy Path',
            action: 'workspace::CopyPath',
            onPressed: () => _tabs.copyPath(index),
          ),
          ContextMenuItem(
            'Copy Relative Path',
            action: 'workspace::CopyRelativePath',
            onPressed: () => _tabs.copyPath(index, relative: true),
          ),
          const ContextMenuSeparator(),
          ContextMenuItem(
            'Reveal in File Explorer',
            action: 'editor::RevealInFileManager',
            onPressed: () => _tabs.reveal(index),
          ),
        ],
        const ContextMenuSeparator(),
        ContextMenuItem(
          'Pin Tab',
          action: 'pane::TogglePinTab',
          onPressed: () {},
        ),
      ],
    );
  }

  /// cursor position, encoding and language of the active document
  Widget _nativeStatus(AppTheme theme) {
    return ListenableBuilder(
      listenable: Listenable.merge([_tabs, ?_tabs.activeController]),
      builder: (context, _) {
        final controller = _tabs.activeController;
        String? cursor;
        if (controller != null) {
          cursor = cursorSummary(
            controller.buffer.text,
            controller.selections.all,
            controller.selections.newest,
          );
        }
        return Row(
          children: [
            for (final (button, text) in [
              if (cursor != null) (_cursor, cursor),
              if (_tabs.indentation.isNotEmpty)
                (_indentation, _tabs.indentation),
              if (_tabs.active < _tabs.tabs.length)
                (_encoding, _tabs.tabs[_tabs.active].encoding.label),
              if (_tabs.lineEnding.isNotEmpty) (_lineEnding, _tabs.lineEnding),
              if (_tabs.languageName != null) (_language, _tabs.languageName!),
            ])
              if (!button.hidden)
                _StatusItem(
                  label: button.label,
                  keys: _keysOf(button),
                  onPressed: button.onPressed,
                  text: text,
                  theme: theme,
                  onMenu: (position) =>
                      _showButtonMenu(theme, button, position),
                ),
          ],
        );
      },
    );
  }

  /// pickers open under the title bar
  static const _pickerTop = _titleBarHeight + 8;

  /// `line` or `line:column`
  static (int, int?)? _parseGoTo(String text) {
    final match = RegExp(r'^\s*(\d+)?(?::(\d+))?\s*$').firstMatch(text);
    final line = int.tryParse(match?.group(1) ?? '');
    if (line == null) {
      return null;
    }
    return (line, int.tryParse(match!.group(2) ?? ''));
  }

  Future<void> _openGoToLine() async {
    if (_tabs.tabs.isEmpty) {
      return;
    }
    final controller = _tabs.activeController;
    if (controller == null) {
      return;
    }
    final point = controller.buffer.offsetToPoint(
      controller.selections.newest.head,
    );
    final cursor = (line: point.row + 1, column: point.column + 1);
    final lines = controller.buffer.lineCount;
    showInputPicker(
      context,
      theme: widget.controller.value,
      top: _pickerTop,
      hint: '${cursor.line}:${cursor.column}',
      describe: (text) {
        final target = _parseGoTo(text);
        if (text.trim().isEmpty) {
          return 'Current Line: ${cursor.line} of $lines (column ${cursor.column})';
        }
        if (target == null) {
          return 'Enter a line, or line:column';
        }
        final (line, column) = target;
        return 'Go to line ${line.clamp(1, lines)}'
            '${column == null ? '' : ', column $column'}';
      },
      onSubmitted: (text) {
        final target = _parseGoTo(text);
        if (target != null) {
          _tabs.goTo(target.$1.clamp(1, lines), target.$2 ?? 1);
        }
      },
    );
  }

  static const _indentSizes = [2, 4, 8];

  /// each size with spaces, then with tabs, named as the bottom bar names them
  Future<void> _openIndentationPicker() async {
    if (_tabs.indentation.isEmpty) {
      return;
    }
    final names = [
      for (final spaces in [true, false])
        for (final size in _indentSizes)
          '${spaces ? 'Spaces' : 'Tab Size'}: $size',
    ];
    showListPicker(
      context,
      theme: widget.controller.value,
      top: _pickerTop,
      items: [
        for (final name in names)
          PickerItem(name, checked: name == _tabs.indentation),
      ],
      onSelected: (i) => _tabs.setIndentation(
        spaces: i < _indentSizes.length,
        size: _indentSizes[i % _indentSizes.length],
      ),
    );
  }

  Future<CloseChoice> _confirmClose(
    List<EditorTab> unsaved, {
    required bool single,
  }) async {
    final many = unsaved.length > 1;
    final tab = unsaved.first;
    final choice = await showConfirmDialog(
      context,
      theme: widget.controller.value,
      message: many
          ? 'Do you want to save changes to the following files?'
          : single && tab.file == null
          ? 'This buffer contains unsaved edits. Do you want to save it?'
          : '`${tab.file?.path ?? tab.name}` contains unsaved edits. Do you want to save it?',
      details: many ? [for (final tab in unsaved) tab.name] : const [],
      buttons: many
          ? const ['Save all', 'Discard all', 'Cancel']
          : const ['Save', "Don't Save", 'Cancel'],
    );
    return switch (choice) {
      0 => CloseChoice.save,
      1 => CloseChoice.discard,
      _ => CloseChoice.cancel,
    };
  }

  Future<void> _openEncodingPicker() async {
    if (_tabs.tabs.isEmpty) {
      return;
    }
    final current = _tabs.tabs[_tabs.active].encoding;
    showListPicker(
      context,
      theme: widget.controller.value,
      top: _pickerTop,
      hint: 'Reopen with encoding...',
      items: [
        for (final encoding in TextEncoding.values)
          PickerItem(encoding.label, checked: encoding == current),
      ],
      onSelected: (i) => _tabs.reopenWithEncoding(TextEncoding.values[i]),
    );
  }

  Future<void> _openLineEndingPicker() async {
    if (_tabs.lineEnding.isEmpty) {
      return;
    }
    final crlf = _tabs.lineEnding == 'CRLF';
    showListPicker(
      context,
      theme: widget.controller.value,
      top: _pickerTop,
      items: [
        PickerItem('LF', checked: !crlf),
        PickerItem('CRLF', checked: crlf),
      ],
      onSelected: (i) => _tabs.setLineEnding(crlf: i == 1),
    );
  }

  String? _keysOf(_BottomButton button) {
    final action = button.action;
    return action == null ? null : _keymap.keysFor(action);
  }

  /// the menu of a bottom bar button: the side it can be docked to, and hiding
  /// it when it can be hidden
  void _showButtonMenu(
    AppTheme theme,
    _BottomButton button,
    Offset position, {
    ContextMenuAnchor anchor = ContextMenuAnchor.topLeft,
  }) {
    final dock = button.dock;
    showContextMenu(
      context,
      position: position,
      anchor: anchor,
      theme: theme,
      entries: [
        if (dock != null)
          for (final side in _Dock.values)
            ContextMenuItem(
              side.name[0].toUpperCase() + side.name.substring(1),
              checked: side == dock,
              onPressed: () {
                setState(() => button.dock = side);
                _saveSettings();
              },
            ),
        if (dock != null && button.canHide) const ContextMenuSeparator(),
        if (button.canHide)
          ContextMenuItem(
            'Hide Button',
            onPressed: () {
              setState(() => button.hidden = true);
              _saveSettings();
            },
          ),
      ],
    );
  }

  Widget _bottomBar(AppTheme theme) {
    final dock = _sidebar.dock!;
    // the button's own space is already between it and the divider
    final divider = Container(
      width: theme.borderWidth,
      height: 14,
      margin: EdgeInsets.only(
        left: dock == _Dock.right ? 4 : 0,
        right: dock == _Dock.left ? 4 : 0,
      ),
      color: theme.border,
    );
    // the icon is drawn for the left, and mirrored for the right
    final sidebarButton = GestureDetector(
      // the menu opens above the button, with its corner at the button's top
      // corner on the side that it is docked to
      onSecondaryTapUp: (details) {
        final box = _sidebarButtonKey.currentContext?.findRenderObject();
        final right = dock == _Dock.right;
        if (box is! RenderBox || !box.attached) {
          _showButtonMenu(theme, _sidebar, details.globalPosition);
          return;
        }
        final top = box.localToGlobal(Offset.zero);
        _showButtonMenu(
          theme,
          _sidebar,
          right ? top + Offset(box.size.width, 0) : top,
          anchor: right
              ? ContextMenuAnchor.bottomRight
              : ContextMenuAnchor.bottomLeft,
        );
      },
      child: Transform.flip(
        key: _sidebarButtonKey,
        flipX: dock == _Dock.right,
        child: _BarButton(
          label: _sidebar.label,
          keys: _keysOf(_sidebar),
          // the button of what is open has no tooltip
          tip: !_sidebarOpen,
          name: _sidebarOpen ? 'sidebar-open' : 'sidebar-closed',
          extent: _bottomBarHeight,
          // the small icon size, which is 14 pixels, and in the text color, like
          // the text of the bar that it is in
          size: 14,
          hoverInset: 2,
          hoverRadius: 4,
          theme: theme,
          onPressed: _sidebar.onPressed!,
        ),
      ),
    );
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          _showBarMenu(theme, details.globalPosition),
      child: Container(
        height: _bottomBarHeight,
        decoration: BoxDecoration(
          color: theme.titleBar,
          border: Border(
            top: BorderSide(color: theme.border, width: theme.borderWidth),
          ),
        ),
        child: Row(
          children: [
            if (dock == _Dock.left) ...[sidebarButton, divider],
            const Spacer(),
            if (_view == _View.editor) _nativeStatus(theme),
            if (dock == _Dock.right) ...[divider, sidebarButton],
          ],
        ),
      ),
    );
  }

  /// the buttons that can be hidden, checked while they are shown
  void _showBarMenu(AppTheme theme, Offset position) {
    showContextMenu(
      context,
      position: position,
      theme: theme,
      entries: [
        for (final button in _buttons)
          if (button.canHide)
            ContextMenuItem(
              button.label,
              checked: !button.hidden,
              onPressed: () {
                setState(() => button.hidden = !button.hidden);
                _saveSettings();
              },
            ),
      ],
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
              // the row is only as tall as the text, so without this the
              // strips above and below it would not drag
              child: SizedBox(
                height: _titleBarHeight,
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    Text('Nyaxis', style: theme.titleStyle),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
          _BarButton(
            label: 'Minimize',
            name: 'minimize',
            cursor: SystemMouseCursors.basic,
            extent: _titleBarHeight,
            size: _titleBarHeight * 0.4,
            theme: theme,
            onPressed: windowManager.minimize,
          ),
          _BarButton(
            label: _maximized ? 'Restore' : 'Maximize',
            name: _maximized ? 'restore' : 'maximize',
            cursor: SystemMouseCursors.basic,
            extent: _titleBarHeight,
            size: _titleBarHeight * 0.4,
            theme: theme,
            onPressed: _toggleMaximize,
          ),
          _BarButton(
            label: 'Close',
            name: 'close',
            cursor: SystemMouseCursors.basic,
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
    required this.onMenu,
  });

  final EditorTab tab;
  final bool selected;
  final AppTheme theme;
  final BorderSide line;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  /// gets where the tab was right clicked
  final ValueChanged<Offset> onMenu;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  static const _closeSize = 14.0;
  static const _closeExtent = 20.0;
  static const _dotSize = 6.0;
  // mirrors the close slot, 4 gap and 8 padding on the right
  static const _margin = _closeExtent + 12;

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
    return Clickable(
      onEnter: () => setState(() => _hovered = true),
      onExit: () => setState(() => _hovered = false),
      onTap: widget.onSelect,
      onSecondaryTapUp: (details) => widget.onMenu(details.globalPosition),
      child: CustomPaint(
        painter: widget.selected
            ? _ReplacePainter(theme.backgroundColor)
            : null,
        child: Container(
          // the dot fills the left margin, so it never moves the name
          padding: EdgeInsets.only(
            left: widget.tab.dirty ? 0 : _margin,
            right: 8,
          ),
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
                  width: _dotSize,
                  height: _dotSize,
                  margin: const EdgeInsets.symmetric(
                    horizontal: (_margin - _dotSize) / 2,
                  ),
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
                    label: 'Close',
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

/// text in the bottom bar, filled while hovered; right clicking it gets
/// the position for a menu
class _StatusItem extends StatefulWidget {
  const _StatusItem({
    required this.label,
    required this.keys,
    required this.text,
    required this.theme,
    required this.onMenu,
    this.onPressed,
  });

  /// what left clicking does, nothing when null
  final VoidCallback? onPressed;

  /// what the item does, apart from the [text] it shows
  final String label;

  /// of its action, null when none are bound
  final String? keys;
  final String text;
  final AppTheme theme;
  final ValueChanged<Offset> onMenu;

  @override
  State<_StatusItem> createState() => _StatusItemState();
}

class _StatusItemState extends State<_StatusItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Clickable(
      onEnter: () => setState(() => _hovered = true),
      onExit: () => setState(() => _hovered = false),
      onTap: widget.onPressed,
      onSecondaryTapUp: (details) => widget.onMenu(details.globalPosition),
      child: _tip(
        theme: theme,
        label: widget.label,
        keys: widget.keys,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered
                ? theme.hover.withValues(alpha: 0.3)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            widget.text,
            style: theme.captionStyle.copyWith(color: theme.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatefulWidget {
  const _BarButton({
    required this.label,
    required this.name,
    required this.extent,
    required this.size,
    required this.theme,
    required this.onPressed,
    this.hoverInset = 0,
    this.hoverRadius = 0,
    this.destructive = false,
    this.active = false,
    this.keys,
    this.tip = true,
    this.cursor = SystemMouseCursors.click,
  });

  /// what the button does
  final String label;

  /// of its action, when some are bound
  final String? keys;

  /// whether it has a tooltip, which the button of what is open does not
  final bool tip;

  final MouseCursor cursor;

  /// the icon's name
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

  /// draws the icon in the accent color, while a menu opened from the button
  /// is showing
  final bool active;
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
    final fill = Clickable(
      cursor: widget.cursor,
      onEnter: () => setState(() => _hovered = true),
      onExit: () => setState(() => _hovered = false),
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
              : widget.active
              ? theme.accent
              : theme.textPrimary,
        ),
      ),
    );
    final tipped = _tip(
      theme: theme,
      label: widget.label,
      keys: widget.keys,
      enabled: widget.tip,
      child: fill,
    );
    if (widget.hoverInset == 0) {
      return tipped;
    }
    return Center(child: AspectRatio(aspectRatio: 1, child: tipped));
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
