import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:window_manager/window_manager.dart';

import 'text_encoding.dart';

class EditorTab {
  EditorTab(this.name, this.document, this.encoding, [this.file]);

  String name;
  TextEncoding encoding;

  /// null until an untitled tab is first saved
  File? file;
  final MonacoDocument document;
  bool dirty = false;
}

/// when a tab with unsaved changes is saved without asking; the names are the
/// values of `autoSave` in `config.json`, and untitled tabs are never saved
enum AutoSave { off, afterDelay, onFocusChange, onWindowChange }

/// the open scripts, each a file in `%APPDATA%\Nyaxis\scripts`; every script
/// in the folder gets a tab
class EditorTabs extends ChangeNotifier with WindowListener {
  static const _extension = '.luau';

  final tabs = <EditorTab>[];
  int active = 0;

  MonacoController? _controller;
  Directory? _folder;
  StreamSubscription<MonacoEvent>? _events;
  var _nextUri = 0;

  var _autoSave = AutoSave.off;
  var _autoSaveDelay = const Duration(seconds: 1);
  final _timers = <EditorTab, Timer>{};

  /// action to monaco key; the page posts `nyaxis.<action>` when the key is
  /// pressed in the editor, where flutter never sees it
  static const _keybindings = {
    'save': 'monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS',
  };

  static String get _keybindingScript => [
    for (final binding in _keybindings.entries)
      'editor.addCommand(${binding.value}, () => '
          'window.flutterChannel.postMessage(JSON.stringify('
          "{kind: 'event', name: 'nyaxis.${binding.key}', data: {}})));",
  ].join('\n');

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
      _autoSaveDelay = Duration(milliseconds: delay);
    }
    if (!json.containsKey('autoSave') || !json.containsKey('autoSaveDelay')) {
      json.putIfAbsent('autoSave', () => AutoSave.off.name);
      json.putIfAbsent('autoSaveDelay', () => _autoSaveDelay.inMilliseconds);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(json),
        flush: true,
      );
    }
  }

  Future<void> attach(MonacoController controller) async {
    final appData = Platform.environment['APPDATA'];
    if (appData == null) {
      debugPrint('EditorTabs: APPDATA unavailable, no scripts');
      return;
    }
    _controller = controller;
    final folder = _folder = Directory('$appData\\Nyaxis\\scripts');
    await folder.create(recursive: true);
    await _loadConfig(appData);

    windowManager.addListener(this);
    _events = controller.events.listen(_onEvent);
    await controller.runJavaScript(_keybindingScript);

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
    if (tabs.isEmpty) {
      await newTab();
    } else {
      await select(0);
    }
  }

  /// opens [file], or an empty untitled document when it is null
  Future<EditorTab?> _open(File? file) async {
    final controller = _controller;
    if (controller == null) {
      return null;
    }
    try {
      // the language server matches documents by exact uri, and it sees them
      // lowercased, so the uri is lowercase and independent of the file name
      final bytes = file == null ? Uint8List(0) : await file.readAsBytes();
      final encoding = TextEncoding.detect(bytes);
      final document = await controller.openDocument(
        text: encoding.decode(bytes),
        language: MonacoLanguage.lua,
        uri: Uri.parse('file:///nyaxis/script${_nextUri++}$_extension'),
      );
      final tab = EditorTab(
        file == null ? _untitledName() : file.uri.pathSegments.last,
        document,
        encoding,
        file,
      );
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
    await _controller?.activateDocument(tabs[index].document);
  }

  /// unsaved changes are lost, since there is no prompt to ask; the editor
  /// always keeps one tab
  Future<void> close(int index) async {
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
    if (tabs.isEmpty) {
      await newTab();
    } else {
      await select(active);
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

  Future<void> _onEvent(MonacoEvent event) async {
    if (event is MonacoUnknownEvent && event.name.startsWith('nyaxis.')) {
      switch (event.name.substring('nyaxis.'.length)) {
        case 'save':
          await save();
      }
    } else if (event is MonacoFocusChanged) {
      if (!event.focused && _autoSave == AutoSave.onFocusChange) {
        await _autoSaveAll();
      }
    } else if (event is MonacoContentChanged) {
      for (final tab in tabs) {
        if (tab.document.uri == event.documentUri) {
          final dirty = await tab.document.isDirty();
          if (dirty != tab.dirty) {
            tab.dirty = dirty;
            notifyListeners();
          }
          _timers.remove(tab)?.cancel();
          if (dirty && _autoSave == AutoSave.afterDelay) {
            _timers[tab] = Timer(
              _autoSaveDelay,
              () => _autoSaveTab(tabs.indexOf(tab)),
            );
          }
        }
      }
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
    _events?.cancel();
    super.dispose();
  }
}
