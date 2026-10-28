import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:window_manager/window_manager.dart';

import '../editor/editor_tabs.dart';
import '../editor/file_icon_theme.dart';
import '../editor/keymap.dart';
import '../editor/language_extensions.dart';
import '../editor/luau_lsp.dart';
import '../editor/text_encoding.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'clickable.dart';
import 'context_menu.dart';
import 'deferred_size.dart';
import 'dialog.dart';
import 'picker.dart';
import 'sidebar.dart';
import 'skinnable_icon.dart';
import 'superellipse.dart';

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
  required bool below,
  required Widget child,
}) {
  return Tooltip(
    richMessage: TextSpan(
      text: label,
      style: theme.bodyStyle,
      children: [
        if (keys != null)
          TextSpan(
            text: '   ${Keymap.formatKeys(keys)}',
            style: theme.bodyStyle.copyWith(color: theme.textDim),
          ),
      ],
    ),
    preferBelow: below,
    waitDuration: const Duration(milliseconds: 500),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: theme.surface,
      borderRadius: BorderRadius.circular(theme.cornerRadius),
      border: Border.all(color: theme.border, width: theme.borderWidth),
    ),
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
  static const _monacoTheme = MonacoTheme('nyaxis');

  MonacoController? _monaco;
  final _tabs = EditorTabs();
  final _keymap = Keymap();

  bool _sidebarOpen = false;
  double _sidebarWidth = 240;

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
    onPressed: _openLanguagePicker,
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
    _tabs.confirmClose = _confirmClose;
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
    _keymap.on('workspace::Open', _openFile);
    _keymap.on('go_to_line::Toggle', _openGoToLine);
    _keymap.on('indentation_selector::Toggle', _openIndentationPicker);
    _keymap.on('encoding_selector::Toggle', _openEncodingPicker);
    _keymap.on('language_selector::Toggle', _openLanguagePicker);
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
    _keymap.on('workspace::CopyPath', () => _tabs.copyPath(_tabs.active));
    _keymap.on(
      'workspace::RevealInFileManager',
      () => _tabs.reveal(_tabs.active),
    );
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
                      Expanded(
                        child: Row(
                          children: [
                            if (_sidebarOpen && _sidebar.dock == _Dock.left)
                              _sidebarPanel(theme),
                            Expanded(
                              child: Column(
                                children: [
                                  _tabBar(theme),
                                  Expanded(child: _editor(theme)),
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
    );
  }

  Widget _editor(AppTheme theme) {
    return
    // the webview is slow to resize, so it waits for the
    // window to stop being dragged
    DeferredSize(
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
                      size: _tabBarHeight * 0.5,
                      hoverInset: 5,
                      hoverRadius: 4,
                      active: _newMenuOpen,
                      theme: theme,
                      onPressed: () => _showNewMenu(context, theme),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
        ContextMenuItem('New File', onPressed: _tabs.newTab),
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
        ContextMenuItem('Close', onPressed: () => _tabs.close(index)),
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
          'Close All',
          action: 'pane::CloseAllItems',
          onPressed: _tabs.closeAll,
        ),
        const ContextMenuSeparator(),
        ContextMenuItem(
          'Copy Path',
          action: 'workspace::CopyPath',
          onPressed: hasFile ? () => _tabs.copyPath(index) : null,
        ),
        ContextMenuItem(
          'Copy Relative Path',
          onPressed: hasFile
              ? () => _tabs.copyPath(index, relative: true)
              : null,
        ),
        const ContextMenuSeparator(),
        ContextMenuItem(
          'Reveal in File Explorer',
          action: 'workspace::RevealInFileManager',
          onPressed: hasFile ? () => _tabs.reveal(index) : null,
        ),
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
  Widget _status(AppTheme theme, MonacoController monaco) {
    return ValueListenableBuilder<MonacoLiveStats>(
      valueListenable: monaco.stats,
      builder: (context, stats, _) {
        final cursor = stats.cursorPosition;
        return ListenableBuilder(
          listenable: _tabs,
          builder: (context, _) {
            final language = _tabs.language ?? stats.language;
            return Row(
              children: [
                for (final (button, text) in [
                  if (cursor != null)
                    (_cursor, 'Ln ${cursor.line}, Col ${cursor.column}'),
                  if (_tabs.indentation.isNotEmpty)
                    (_indentation, _tabs.indentation),
                  if (_tabs.active < _tabs.tabs.length)
                    (_encoding, _tabs.tabs[_tabs.active].encoding.label),
                  if (_tabs.lineEnding.isNotEmpty)
                    (_lineEnding, _tabs.lineEnding),
                  if (language != null)
                    (_language, language.label ?? language.id),
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
    final stats = _monaco?.stats.value;
    if (stats == null || _tabs.tabs.isEmpty) {
      return;
    }
    final cursor = stats.cursorPosition;
    final lines = stats.lineCount;
    showInputPicker(
      context,
      theme: widget.controller.value,
      top: _pickerTop,
      hint: cursor == null ? 'Line:Column' : '${cursor.line}:${cursor.column}',
      describe: (text) {
        final target = _parseGoTo(text);
        if (text.trim().isEmpty) {
          return cursor == null
              ? 'Lines: $lines'
              : 'Current Line: ${cursor.line} of $lines (column ${cursor.column})';
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

  Future<void> _openLanguagePicker() async {
    final monaco = _monaco;
    if (monaco == null || _tabs.tabs.isEmpty) {
      return;
    }
    final current = _tabs.language ?? monaco.stats.value.language;
    final icons = await FileIconTheme.load(widget.controller.palette);
    if (!mounted) {
      return;
    }
    final languages = MonacoLanguage.builtIn;
    showListPicker(
      context,
      theme: widget.controller.value,
      top: _pickerTop,
      hint: 'Select a language...',
      items: [
        for (final language in languages)
          PickerItem(
            language.label ?? language.id,
            checked: language == current,
            icon: icons?.assetFor(
              languageExtensions[language.id] ?? language.id,
            ),
          ),
      ],
      onSelected: (i) => _tabs.setLanguage(languages[i]),
    );
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
  void _showButtonMenu(AppTheme theme, _BottomButton button, Offset position) {
    final dock = button.dock;
    showContextMenu(
      context,
      position: position,
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
    final monaco = _monaco;
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
      onSecondaryTapUp: (details) =>
          _showButtonMenu(theme, _sidebar, details.globalPosition),
      child: Transform.flip(
        flipX: dock == _Dock.right,
        child: _BarButton(
          label: _sidebar.label,
          keys: _keysOf(_sidebar),
          tipBelow: false,
          name: _sidebarOpen ? 'sidebar-open' : 'sidebar-closed',
          extent: _bottomBarHeight,
          // the icon's own grid, so its lines land on whole pixels
          size: 16,
          hoverInset: 2,
          hoverRadius: 4,
          dim: true,
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
            if (monaco != null) _status(theme, monaco),
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
        below: false,
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
            style: theme.captionStyle.copyWith(
              color: _hovered ? theme.textPrimary : null,
            ),
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
    this.dim = false,
    this.active = false,
    this.keys,
    this.tipBelow = true,
    this.cursor = SystemMouseCursors.click,
  });

  /// what the button does
  final String label;

  /// of its action, when some are bound
  final String? keys;

  /// whether its tooltip opens under the button, or above it
  final bool tipBelow;

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

  /// draws the icon in the dim text color until the button is hovered
  final bool dim;

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
              : (widget.dim && !_hovered && !_pressed
                    ? theme.textDim
                    : theme.textPrimary),
        ),
      ),
    );
    final tipped = _tip(
      theme: theme,
      label: widget.label,
      keys: widget.keys,
      below: widget.tipBelow,
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
