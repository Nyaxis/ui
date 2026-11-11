import 'dart:async';

import 'package:flutter/foundation.dart';

import '../editor_core/buffer.dart';
import '../editor_core/patch.dart' show Bias;
import '../lsp/diagnostic_range.dart';
import '../lsp/document_sync.dart';
import '../lsp/json_rpc.dart';
import '../lsp/lsp_client.dart';
import '../native/backend.dart';
import '../native_editor/editor_controller.dart' show DiagnosticRanges;
import 'tab_document.dart';

/// the language server of the backend, told of the documents that flutter
/// draws, with what it finds wrong underlined in them. a document that is
/// attached before the server is ready is opened once it is
class LuauLanguageService {
  LuauLanguageService(this._backend);

  final Backend _backend;
  LspClient? _client;
  Future<void>? _starting;
  StreamSubscription<PublishedDiagnostics>? _diagnostics;

  final _documents = <NativeTabDocument>[];
  final _syncs = <NativeTabDocument, LspDocumentSync>{};

  bool get isConnected => _client?.isInitialized ?? false;

  /// the backend refuses everything until it is licensed and ready, which is
  /// after the first documents are open, so the server is only started then. a
  /// start that gets no answer is tried again by the next document attached
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    await _backend.ready;
    final client = LspClient(
      JsonRpcConnection.messages(_backend.lspMessages, _backend.lspSend),
    );
    _backend.lspStart();
    try {
      await client.initialize().timeout(const Duration(seconds: 15));
    } on Object catch (e) {
      debugPrint('luau-lsp: not connected ($e)');
      await client.shutdown();
      _starting = null;
      return;
    }
    _client = client;
    _diagnostics = client.diagnostics.listen(_onDiagnostics);
    for (final document in _documents) {
      _open(document);
    }
  }

  void attach(NativeTabDocument document) {
    if (_documents.contains(document)) {
      return;
    }
    _documents.add(document);
    document.onClosed = detach;
    if (isConnected) {
      _open(document);
    } else {
      unawaited(start());
    }
  }

  void detach(NativeTabDocument document) {
    _documents.remove(document);
    _syncs.remove(document)?.close();
  }

  void _open(NativeTabDocument document) {
    final sync = LspDocumentSync(
      client: _client!,
      buffer: document.controller.buffer,
      uri: document.uri.toString(),
      languageId: 'luau',
    )..open();
    _syncs[document] = sync;
  }

  void _onDiagnostics(PublishedDiagnostics published) {
    for (final entry in _syncs.entries) {
      final sync = entry.value;
      if (sync.uri != published.uri) {
        continue;
      }
      // what was found in text that has changed since is not where it was
      if (published.version != null && published.version != sync.version) {
        return;
      }
      _show(entry.key, published.diagnostics);
    }
  }

  void _show(NativeTabDocument document, List<LspDiagnostic> diagnostics) {
    final buffer = document.controller.buffer;
    final text = buffer.text;
    final bySeverity = {
      for (final severity in DiagnosticSeverity.values)
        severity: <(int, int)>[],
    };
    final unused = <(int, int)>[];
    for (final diagnostic in diagnostics) {
      final (start, end) = diagnosticOffsets(text, diagnostic.range);
      if (end > start) {
        bySeverity[diagnostic.severity]!.add((start, end));
        if (diagnostic.unnecessary) {
          unused.add((start, end));
        }
      }
    }
    List<AnchorRange> ranges(List<(int, int)> places) =>
        (places..sort((a, b) => a.$1.compareTo(b.$1)))
            .map(
              (p) => AnchorRange(
                buffer.anchorAt(p.$1, Bias.right),
                buffer.anchorAt(p.$2, Bias.left),
              ),
            )
            .toList();
    document.controller.setDiagnostics(
      DiagnosticRanges(
        errors: ranges(bySeverity[DiagnosticSeverity.error]!),
        warnings: ranges(bySeverity[DiagnosticSeverity.warning]!),
        information: ranges(bySeverity[DiagnosticSeverity.information]!),
        hints: ranges(bySeverity[DiagnosticSeverity.hint]!),
        unnecessary: ranges(unused),
      ),
    );
  }

  Future<void> dispose() async {
    for (final document in _documents) {
      document.onClosed = null;
    }
    for (final sync in _syncs.values) {
      sync.close();
    }
    _syncs.clear();
    _documents.clear();
    await _diagnostics?.cancel();
    await _client?.shutdown();
    _client = null;
  }
}
