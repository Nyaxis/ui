import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_monaco/flutter_monaco.dart';

class EditorTab {
  EditorTab(this.file, this.document);

  final File file;
  final MonacoDocument document;
  bool dirty = false;

  String get name => file.uri.pathSegments.last;
}

/// the open scripts, each a file in `%APPDATA%\Nyaxis\scripts`; every script
/// in the folder gets a tab
class EditorTabs extends ChangeNotifier {
  static const _extension = '.luau';

  final tabs = <EditorTab>[];
  int active = 0;

  MonacoController? _controller;
  Directory? _folder;
  StreamSubscription<MonacoEvent>? _events;
  var _nextUri = 0;

  /// `nyaxisSave` is posted by the page when ctrl+s is pressed in the editor,
  /// where flutter never sees the key
  static const _saveKey = '''
editor.addCommand(
  monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS,
  () => window.flutterChannel.postMessage(
    JSON.stringify({kind: 'event', name: 'nyaxisSave', data: {}})
  )
);
''';

  Future<void> attach(MonacoController controller) async {
    final appData = Platform.environment['APPDATA'];
    if (appData == null) {
      debugPrint('EditorTabs: APPDATA unavailable, no scripts');
      return;
    }
    _controller = controller;
    final folder = _folder = Directory('$appData\\Nyaxis\\scripts');
    await folder.create(recursive: true);

    _events = controller.events.listen(_onEvent);
    await controller.runJavaScript(_saveKey);

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

  Future<EditorTab?> _open(File file) async {
    final controller = _controller;
    if (controller == null) {
      return null;
    }
    try {
      // the language server matches documents by exact uri, and it sees them
      // lowercased, so the uri is lowercase and independent of the file name
      final document = await controller.openDocument(
        text: await file.readAsString(encoding: utf8),
        language: MonacoLanguage.lua,
        uri: Uri.parse('file:///nyaxis/script${_nextUri++}$_extension'),
      );
      final tab = EditorTab(file, document);
      tabs.add(tab);
      return tab;
    } catch (e) {
      debugPrint('EditorTabs: cannot open ${file.path} ($e)');
      return null;
    }
  }

  Future<void> newTab() async {
    final folder = _folder;
    if (folder == null) {
      return;
    }
    var file = File('${folder.path}\\Untitled$_extension');
    for (var n = 2; file.existsSync(); n++) {
      file = File('${folder.path}\\Untitled $n$_extension');
    }
    await file.writeAsString('', flush: true);
    final tab = await _open(file);
    if (tab != null) {
      await select(tabs.indexOf(tab));
    }
  }

  Future<void> select(int index) async {
    if (index < 0 || index >= tabs.length) {
      return;
    }
    active = index;
    notifyListeners();
    await _controller?.activateDocument(tabs[index].document);
  }

  /// unsaved changes are saved first, since there is no prompt to ask; the
  /// editor always keeps one tab
  Future<void> close(int index) async {
    if (index < 0 || index >= tabs.length) {
      return;
    }
    final tab = tabs[index];
    if (tab.dirty) {
      await _save(tab);
    }
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
      await tab.file.writeAsString(await tab.document.getText(), flush: true);
      await tab.document.markSaved();
      tab.dirty = false;
      notifyListeners();
    } catch (e) {
      debugPrint('EditorTabs: cannot save ${tab.file.path} ($e)');
    }
  }

  Future<void> _onEvent(MonacoEvent event) async {
    if (event is MonacoUnknownEvent && event.name == 'nyaxisSave') {
      await save();
    } else if (event is MonacoContentChanged) {
      for (final tab in tabs) {
        if (tab.document.uri == event.documentUri) {
          final dirty = await tab.document.isDirty();
          if (dirty != tab.dirty) {
            tab.dirty = dirty;
            notifyListeners();
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }
}
