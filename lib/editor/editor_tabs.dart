import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

/// what to do with tabs that have unsaved changes when they are closed
enum CloseChoice { save, discard, cancel }

/// when a tab with unsaved changes is saved without asking; the names are the
/// values of `autoSave` in `config.json`, and untitled tabs are never saved
enum AutoSave { off, afterDelay, onFocusChange, onWindowChange }

/// the open scripts, each a file in `%APPDATA%\Nyaxis\scripts`; every script
/// in the folder gets a tab
class EditorTabs extends ChangeNotifier with WindowListener {
  static const _extension = '.luau';

  /// the language of each known extension; other files open as plain text
  static const _languages = {
    '.lua': MonacoLanguage.lua,
    '.luau': MonacoLanguage.lua,
    '.json': MonacoLanguage.json,
    '.js': MonacoLanguage.javascript,
    '.ts': MonacoLanguage.typescript,
    '.md': MonacoLanguage.markdown,
    '.html': MonacoLanguage.html,
    '.css': MonacoLanguage.css,
    '.xml': MonacoLanguage.xml,
    '.yaml': MonacoLanguage.yaml,
    '.yml': MonacoLanguage.yaml,
    '.py': MonacoLanguage.python,
  };

  final tabs = <EditorTab>[];
  int active = 0;

  MonacoController? _controller;
  Directory? _folder;
  StreamSubscription<MonacoEvent>? _events;
  var _nextUri = 0;

  var _autoSave = AutoSave.off;
  var _autoSaveDelay = const Duration(seconds: 1);
  final _timers = <EditorTab, Timer>{};

  /// tells flutter how the active document is indented, how its lines end and
  /// what language it is in, which monaco detects from its content or is told
  static const _documentScript = '''
const post = (name, data) => window.flutterChannel.postMessage(
    JSON.stringify({kind: 'event', name: 'nyaxis.' + name, data}));
const reportIndent = () => {
  const model = editor.getModel();
  if (!model) return;
  const {insertSpaces, tabSize} = model.getOptions();
  post('indent', {insertSpaces, tabSize});
};
editor.onDidChangeModel(reportIndent);
editor.onDidChangeModelOptions(reportIndent);
reportIndent();

let crlf;
const reportEol = () => {
  const model = editor.getModel();
  if (!model) return;
  const now = model.getEOL().length === 2;
  if (now === crlf) return;
  crlf = now;
  post('eol', {crlf});
};
editor.onDidChangeModel(() => { crlf = undefined; reportEol(); });
editor.onDidChangeModelContent(reportEol);
reportEol();

const reportLanguage = () => {
  const model = editor.getModel();
  if (model) post('language', {id: model.getLanguageId()});
};
editor.onDidChangeModel(reportLanguage);
editor.onDidChangeModelLanguage(reportLanguage);
reportLanguage();''';

  /// of the active document, like `Spaces: 4`; empty until monaco reports it
  String indentation = '';

  /// of the active document, `LF` or `CRLF`; empty until monaco reports it
  String lineEnding = '';

  /// of the active document; the live stats of the editor only follow its
  /// content and cursor, not a change of language
  MonacoLanguage? language;

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
    await controller.runJavaScript(_documentScript);

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
      final name = file == null ? _untitledName() : file.uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      final extension = dot < 0 ? '' : name.substring(dot).toLowerCase();
      final document = await controller.openDocument(
        text: encoding.decode(bytes),
        language: _languages[extension] ?? MonacoLanguage.plaintext,
        uri: Uri.parse('file:///nyaxis/script${_nextUri++}$extension'),
      );
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
    await _controller?.activateDocument(tabs[index].document);
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
    if (tabs.isEmpty) {
      await newTab();
    } else {
      await select(active);
    }
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
    final position = '{lineNumber: $line, column: $column}';
    await _controller?.runJavaScript(
      'editor.setPosition($position);'
      'editor.revealPositionInCenter($position);'
      'editor.focus();',
    );
  }

  /// indents the active document with [spaces] or tabs, [size] wide. the
  /// indentation it already has keeps its levels, each as wide as the old
  /// size, and a remainder that is not a whole level stays as spaces
  Future<void> setIndentation({required bool spaces, required int size}) async {
    await _controller?.runJavaScript('''
(() => {
  const model = editor.getModel();
  if (!model) return;
  const old = model.getOptions().tabSize;
  const edits = [];
  for (let line = 1; line <= model.getLineCount(); line++) {
    const lead = /^[ \\t]*/.exec(model.getLineContent(line))[0];
    if (!lead) continue;
    let columns = 0;
    for (const c of lead) columns += c === '\\t' ? old - columns % old : 1;
    const levels = Math.floor(columns / old);
    const text = ($spaces ? ' '.repeat(levels * $size) : '\\t'.repeat(levels))
        + ' '.repeat(columns % old);
    if (text !== lead) {
      edits.push({
        range: {startLineNumber: line, startColumn: 1,
                endLineNumber: line, endColumn: lead.length + 1},
        text,
      });
    }
  }
  model.updateOptions({insertSpaces: $spaces, tabSize: $size});
  editor.pushUndoStop();
  editor.executeEdits('nyaxis.indentation', edits);
  editor.pushUndoStop();
  editor.focus();
})();''');
  }

  Future<void> setLanguage(MonacoLanguage language) async {
    if (active >= tabs.length) {
      return;
    }
    await tabs[active].document.setLanguage(language);
    await _controller?.runJavaScript('editor.focus();');
  }

  Future<void> setLineEnding({required bool crlf}) async {
    await _controller?.runJavaScript(
      'editor.getModel()?.setEOL(${crlf ? 1 : 0});editor.focus();',
    );
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
      await _controller?.runJavaScript('editor.focus();');
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
        case 'indent':
          indentation =
              '${event.data['insertSpaces'] == true ? 'Spaces' : 'Tab Size'}: '
              '${event.data['tabSize']}';
          notifyListeners();
        case 'language':
          language = MonacoLanguage(event.data['id'] as String);
          notifyListeners();
        case 'eol':
          lineEnding = event.data['crlf'] == true ? 'CRLF' : 'LF';
          notifyListeners();
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
