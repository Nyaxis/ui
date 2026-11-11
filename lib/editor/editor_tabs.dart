import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../editor_core/buffer.dart' show LineEnding;
import '../native_editor/editor_controller.dart';
import 'luau_language_service.dart';
import 'session_file.dart';
import 'tab_document.dart';
import 'text_encoding.dart';

class EditorTab {
  EditorTab(this.name, this.document, this.encoding, [this.file]);

  String name;
  TextEncoding encoding;

  /// null until an untitled tab is first saved
  File? file;
  final NativeTabDocument document;
  bool dirty = false;
}

/// what to do with tabs that have unsaved changes when they are closed
enum CloseChoice { save, discard, cancel }

/// when a tab with unsaved changes is saved without asking; the names are the
/// values of `autoSave` in `config.json`, and untitled tabs are never saved
enum AutoSave { off, afterDelay, onFocusChange, onWindowChange }

/// the open scripts, each a file in `%APPDATA%\Nyaxis\scripts`; every script
/// in the folder gets a tab
class EditorTabs extends ChangeNotifier with WindowListener {
  static const _extension = '.luau';

  /// the names of the languages of the known extensions; other files are
  /// plain text
  static const _languageNames = {
    '.lua': 'Luau',
    '.luau': 'Luau',
    '.json': 'JSON',
    '.js': 'JavaScript',
    '.ts': 'TypeScript',
    '.md': 'Markdown',
    '.html': 'HTML',
    '.css': 'CSS',
    '.xml': 'XML',
    '.yaml': 'YAML',
    '.yml': 'YAML',
    '.py': 'Python',
  };

  final tabs = <EditorTab>[];
  int active = 0;

  /// the text of the active tab
  EditorController? get activeController =>
      active < tabs.length ? tabs[active].document.controller : null;

  /// the name of the language of the active tab
  String? get languageName {
    if (active >= tabs.length) {
      return null;
    }
    final name = tabs[active].name;
    final dot = name.lastIndexOf('.');
    return _languageNames[dot < 0 ? '' : name.substring(dot).toLowerCase()] ??
        'Plain Text';
  }

  /// the indentation of the active tab, like `Spaces: 4`
  String get indentation {
    final controller = activeController;
    if (controller == null) {
      return '';
    }
    return '${controller.useTabs ? 'Tab Size' : 'Spaces'}: '
        '${controller.display.tabSize}';
  }

  /// of the active tab, `LF` or `CRLF`
  String get lineEnding {
    final controller = activeController;
    if (controller == null) {
      return '';
    }
    return controller.buffer.lineEnding == LineEnding.crlf ? 'CRLF' : 'LF';
  }

  LuauLanguageService? _luau;

  /// the language server for the documents; those that are already open are
  /// told to it
  set luau(LuauLanguageService? value) {
    _luau = value;
    for (final tab in tabs) {
      value?.attach(tab.document);
    }
  }

  Directory? _folder;
  var _nextUri = 0;

  var _autoSave = AutoSave.off;
  var autoSaveDelay = const Duration(seconds: 1);
  final _timers = <EditorTab, Timer>{};

  AutoSave get autoSave => _autoSave;

  /// saves that are waiting for the delay are dropped when it is no longer
  /// the way to save
  set autoSave(AutoSave value) {
    _autoSave = value;
    if (value != AutoSave.afterDelay) {
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
    }
  }

  /// the tabs with unsaved changes are kept for the next start, since the
  /// window can close at any moment
  SessionFile? _session;
  Timer? _sessionTimer;

  /// the auto save options are read from `config.json`, and added to it with
  /// their defaults when missing so they can be found
  Future<void> _loadConfig(String appData) async {
    final file = File('$appData\\Nyaxis\\config.json');
    var json = <String, dynamic>{};
    try {
      if (file.existsSync()) {
        json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('EditorTabs: unreadable ${file.path} ($e)');
      return;
    }
    _autoSave = AutoSave.values.asNameMap()[json['autoSave']] ?? AutoSave.off;
    final delay = json['autoSaveDelay'];
    if (delay is int && delay >= 0) {
      autoSaveDelay = Duration(milliseconds: delay);
    }
    if (!json.containsKey('autoSave') || !json.containsKey('autoSaveDelay')) {
      json.putIfAbsent('autoSave', () => AutoSave.off.name);
      json.putIfAbsent('autoSaveDelay', () => autoSaveDelay.inMilliseconds);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(json),
        flush: true,
      );
    }
  }

  /// opens the scripts of the folder, and the tabs of the last session
  Future<void> start() async {
    final appData = Platform.environment['APPDATA'];
    if (appData == null) {
      debugPrint('EditorTabs: APPDATA unavailable, no scripts');
      return;
    }
    final folder = _folder = Directory('$appData\\Nyaxis\\scripts');
    await folder.create(recursive: true);
    await _loadConfig(appData);

    windowManager.addListener(this);

    final files =
        folder
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith(_extension))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      await _open(file);
    }
    _session = SessionFile(File('$appData\\Nyaxis\\session.json'));
    await _restoreSession(await _session!.read());
    if (tabs.isEmpty) {
      await newTab();
    } else {
      await select(0);
    }
  }

  /// puts the text of each saved tab back in its tab, which is opened when it
  /// is not already; a tab whose file is gone comes back untitled
  Future<void> _restoreSession(List<SavedTab> saved) async {
    for (final entry in saved) {
      final path = entry.file?.toLowerCase();
      var tab = tabs
          .where((t) => path != null && t.file?.path.toLowerCase() == path)
          .firstOrNull;
      if (tab == null) {
        final file = entry.file == null ? null : File(entry.file!);
        tab = await _open(file != null && file.existsSync() ? file : null);
        if (tab == null) {
          continue;
        }
        if (tab.file == null && !tabs.any((t) => t.name == entry.name)) {
          tab.name = entry.name;
        }
      }
      tab.encoding = entry.encoding;
      await tab.document.setText(entry.text);
      tab.dirty = await tab.document.isDirty();
    }
    notifyListeners();
  }

  /// the session is written a moment after the last change, not at each key
  void _scheduleSession() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer(const Duration(milliseconds: 500), _writeSession);
  }

  Future<void> _writeSession() async {
    final session = _session;
    if (session == null) {
      return;
    }
    final unsaved = [
      for (final tab in tabs)
        if (tab.dirty) tab,
    ];
    await session.write([
      for (final tab in unsaved)
        SavedTab(
          name: tab.name,
          file: tab.file?.path,
          encoding: tab.encoding,
          text: await tab.document.getText(),
        ),
    ]);
  }

  /// opens [file], or an empty untitled document when it is null
  Future<EditorTab?> _open(File? file) async {
    try {
      // the language server matches documents by exact uri, and it sees them
      // lowercased, so the uri is lowercase and independent of the file name
      final bytes = file == null ? Uint8List(0) : await file.readAsBytes();
      final encoding = TextEncoding.detect(bytes);
      final name = file == null ? _untitledName() : file.uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      final extension = dot < 0 ? '' : name.substring(dot).toLowerCase();
      final uri = Uri.parse('file:///nyaxis/script${_nextUri++}$extension');
      final document = NativeTabDocument(
        encoding.decode(bytes),
        uri,
        tabSize: tabSize,
        onChanged: _nativeChanged,
      );
      // the scripts are Luau, whatever the file is called
      document.controller
        ..completeBlocks = true
        ..autoClose = autoClose;
      _luau?.attach(document);
      final tab = EditorTab(name, document, encoding, file);
      tabs.add(tab);
      return tab;
    } catch (e) {
      debugPrint('EditorTabs: cannot open ${file?.path} ($e)');
      return null;
    }
  }

  /// the first `Untitled`, `Untitled 2`... that no tab or script uses
  String _untitledName() {
    for (var n = 1; ; n++) {
      final name = '${n == 1 ? 'Untitled' : 'Untitled $n'}$_extension';
      if (!tabs.any((t) => t.name == name) &&
          !File('${_folder!.path}\\$name').existsSync()) {
        return name;
      }
    }
  }

  /// opens [file] in a tab, or selects its tab when it is open already
  Future<void> openFile(File file) async {
    final path = file.path.toLowerCase();
    var index = tabs.indexWhere((t) => t.file?.path.toLowerCase() == path);
    if (index < 0) {
      final tab = await _open(file);
      if (tab == null) {
        return;
      }
      index = tabs.indexOf(tab);
    }
    await select(index);
  }

  /// an untitled tab has no file until it is saved
  Future<void> newTab() async {
    final tab = await _open(null);
    if (tab != null) {
      await select(tabs.indexOf(tab));
    }
  }

  Future<void> select(int index) async {
    if (index < 0 || index >= tabs.length) {
      return;
    }
    if (_autoSave == AutoSave.onFocusChange && index != active) {
      await _autoSaveTab(active);
    }
    active = index;
    notifyListeners();
  }

  /// the tab size new documents of the editor that flutter draws start with
  int tabSize = 4;

  /// whether new documents of the editor that flutter draws type brackets and
  /// quotes in pairs
  bool autoClose = true;

  /// the text of a tab changed: it is dirty or not, and saved a moment later
  /// when auto save says so
  Future<void> _nativeChanged(NativeTabDocument document) async {
    final tab = tabs.where((t) => t.document == document).firstOrNull;
    if (tab != null) {
      await _contentChanged(tab);
    }
  }

  Future<void> _contentChanged(EditorTab tab) async {
    final dirty = await tab.document.isDirty();
    if (dirty != tab.dirty) {
      tab.dirty = dirty;
    }
    // the status shows the line ending and the indentation
    notifyListeners();
    _scheduleSession();
    _timers.remove(tab)?.cancel();
    if (dirty && _autoSave == AutoSave.afterDelay) {
      _timers[tab] = Timer(
        autoSaveDelay,
        () => _autoSaveTab(tabs.indexOf(tab)),
      );
    }
  }

  /// asks what to do with the tabs to close that have unsaved changes, and
  /// whether it is only one tab that is closed; without
  /// it they are discarded
  Future<CloseChoice> Function(List<EditorTab> unsaved, {required bool single})?
  confirmClose;

  /// the editor always keeps one tab
  Future<void> close(int index) => _closeAll([index], single: true);

  /// closing goes from the end, so the indexes still to close do not move
  Future<void> closeOthers(int index) => _closeAll([
    for (var i = tabs.length - 1; i >= 0; i--)
      if (i != index) i,
  ]);

  Future<void> closeLeft(int index) =>
      _closeAll([for (var i = index - 1; i >= 0; i--) i]);

  Future<void> closeRight(int index) =>
      _closeAll([for (var i = tabs.length - 1; i > index; i--) i]);

  Future<void> closeAll() =>
      _closeAll([for (var i = tabs.length - 1; i >= 0; i--) i]);

  /// closes the tabs at [indexes], highest first, after asking about the ones
  /// with unsaved changes; cancelling closes none
  Future<void> _closeAll(List<int> indexes, {bool single = false}) async {
    final unsaved = [
      for (final i in indexes)
        if (i >= 0 && i < tabs.length && tabs[i].dirty) tabs[i],
    ];
    if (unsaved.isNotEmpty) {
      final choice =
          await confirmClose?.call(unsaved, single: single) ??
          CloseChoice.discard;
      if (choice == CloseChoice.cancel) {
        return;
      }
      if (choice == CloseChoice.save) {
        for (final tab in unsaved) {
          await _save(tab);
        }
      }
    }
    for (final i in indexes) {
      await _remove(i);
    }
    // once, so a tab that cannot be activated does not stop the closing
    if (tabs.isEmpty) {
      await newTab();
    } else {
      await select(active);
    }
  }

  Future<void> _remove(int index) async {
    if (index < 0 || index >= tabs.length) {
      return;
    }
    final tab = tabs[index];
    _timers.remove(tab)?.cancel();
    tabs.removeAt(index);
    if (index < active) {
      active--;
    }
    active = active.clamp(0, tabs.isNotEmpty ? tabs.length - 1 : 0);
    await tab.document.close();
    _scheduleSession();
  }

  /// the file's path, or its name when [relative], since scripts are all in
  /// one folder; untitled tabs have no file, so nothing is copied
  Future<void> copyPath(int index, {bool relative = false}) async {
    final file = tabs[index].file;
    if (file != null) {
      await Clipboard.setData(
        ClipboardData(text: relative ? tabs[index].name : file.path),
      );
    }
  }

  Future<void> reveal(int index) async {
    final file = tabs[index].file;
    if (file != null) {
      // explorer fails to parse the path when it is quoted along with /select,
      await Process.run('explorer', ['/select,', file.path]);
    }
  }

  /// puts the cursor at [line], and [column] when given, and focuses the editor
  Future<void> goTo(int line, [int column = 1]) async {
    final controller = activeController;
    if (controller != null) {
      controller.goToLineColumn(line, column);
      controller.focus();
    }
  }

  /// indents the active document with [spaces] or tabs, [size] wide. the
  /// indentation it already has keeps its levels, each as wide as the old
  /// size, and a remainder that is not a whole level stays as spaces
  Future<void> setIndentation({required bool spaces, required int size}) async {
    final controller = activeController;
    if (controller != null) {
      controller.setIndentation(spaces: spaces, size: size);
      controller.focus();
    }
  }

  Future<void> setLineEnding({required bool crlf}) async {
    if (active < tabs.length) {
      final document = tabs[active].document;
      document.changeLineEnding(crlf ? LineEnding.crlf : LineEnding.lf);
      document.controller.focus();
    }
  }

  /// reads the active tab's file again with [encoding], so changes that are
  /// not saved are lost; an untitled tab has no file to read, and is saved
  /// with [encoding] instead
  Future<void> reopenWithEncoding(TextEncoding encoding) async {
    if (active >= tabs.length) {
      return;
    }
    final tab = tabs[active];
    final file = tab.file;
    if (file == null) {
      tab.encoding = encoding;
      notifyListeners();
      return;
    }
    try {
      await tab.document.setText(encoding.decode(await file.readAsBytes()));
      await tab.document.markSaved();
      tab.encoding = encoding;
      tab.dirty = false;
      notifyListeners();
      _scheduleSession();
      tab.document.controller.focus();
    } catch (e) {
      debugPrint(
        'EditorTabs: cannot reopen ${file.path} as ${encoding.label} '
        '($e)',
      );
    }
  }

  Future<void> save() async {
    if (active < tabs.length) {
      await _save(tabs[active]);
    }
  }

  Future<void> _save(EditorTab tab) async {
    try {
      final file = tab.file ?? File('${_folder!.path}\\${tab.name}');
      final text = await tab.document.getText();
      tab.encoding = tab.encoding.fit(text);
      await file.writeAsBytes(tab.encoding.encode(text), flush: true);
      await tab.document.markSaved();
      tab.file = file;
      tab.name = file.uri.pathSegments.last;
      tab.dirty = false;
      notifyListeners();
      _scheduleSession();
    } catch (e) {
      debugPrint('EditorTabs: cannot save ${tab.name} ($e)');
    }
  }

  /// saves the tab if it has a file and unsaved changes
  Future<void> _autoSaveTab(int index) async {
    if (index < tabs.length && tabs[index].dirty && tabs[index].file != null) {
      await _save(tabs[index]);
    }
  }

  Future<void> _autoSaveAll() async {
    for (var i = 0; i < tabs.length; i++) {
      await _autoSaveTab(i);
    }
  }

  /// the editor lost the focus, which saves the tabs when auto save says so
  Future<void> editorFocusLost() async {
    if (_autoSave == AutoSave.onFocusChange) {
      await _autoSaveAll();
    }
  }

  @override
  void onWindowBlur() {
    if (_autoSave == AutoSave.onWindowChange) {
      _autoSaveAll();
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _sessionTimer?.cancel();
    super.dispose();
  }
}
