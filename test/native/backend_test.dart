import 'package:flutter_test/flutter_test.dart';
import 'package:ui/native/backend.dart';

void main() {
  test('the backend is ready when it says so, and not before', () async {
    final backend = Backend.detached();
    var ready = false;
    backend.ready.then((_) => ready = true);

    backend.handleLine('{"evt":"state","detail":"CheckingLicense"}');
    backend.handleLine('{"evt":"state","detail":"UpdatingInjector"}');
    backend.handleLine('{"evt":"error","detail":"locked"}');
    await Future<void>.delayed(Duration.zero);
    expect(ready, isFalse);

    backend.handleLine('{"evt":"state","detail":"Ready"}');
    await Future<void>.delayed(Duration.zero);
    expect(ready, isTrue);
    backend.dispose();
  });

  test('a second ready is not an error', () {
    final backend = Backend.detached();
    backend.handleLine('{"evt":"state","detail":"Ready"}');
    backend.handleLine('{"evt":"state","detail":"Ready"}');
    backend.dispose();
  });

  test('what the language server sends comes out as it was sent', () async {
    final backend = Backend.detached();
    final messages = <String>[];
    backend.lspMessages.listen(messages.add);
    backend.handleLine(r'{"evt":"lsp","detail":"{\"jsonrpc\":\"2.0\"}"}');
    backend.handleLine('not json');
    await Future<void>.delayed(Duration.zero);
    expect(messages, ['{"jsonrpc":"2.0"}']);
    backend.dispose();
  });
}
