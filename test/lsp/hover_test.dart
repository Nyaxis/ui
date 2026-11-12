import 'package:flutter_test/flutter_test.dart';
import 'package:ui/lsp/lsp_client.dart';

import 'lsp_test_server.dart';

void main() {
  group('what a server says of a place', () {
    test('is the markup of the answer, with its range', () {
      final hover = LspHover.fromJson({
        'contents': {
          'kind': 'markdown',
          'value': '```luau\nlocal x: number\n```',
        },
        'range': {
          'start': {'line': 0, 'character': 6},
          'end': {'line': 0, 'character': 7},
        },
      })!;
      expect(hover.markdown, '```luau\nlocal x: number\n```');
      expect(hover.range, const LspRange(LspPosition(0, 6), LspPosition(0, 7)));
    });

    test('is a string, or a code with its language, or a list of those', () {
      expect(LspHover.fromJson({'contents': 'a text'})!.markdown, 'a text');
      expect(
        LspHover.fromJson({
          'contents': {'language': 'luau', 'value': 'x'},
        })!.markdown,
        '```luau\nx\n```',
      );
      final listed = LspHover.fromJson({
        'contents': [
          {'language': 'luau', 'value': 'x'},
          'its text',
          {'kind': 'markdown', 'value': 'more'},
        ],
      })!;
      expect(listed.markdown, '```luau\nx\n```\n\nits text\n\nmore');
      expect(listed.range, isNull);
    });

    test('is nothing when the answer is nothing, or has no text', () {
      expect(LspHover.fromJson(null), isNull);
      expect(LspHover.fromJson(const <String, Object?>{}), isNull);
      expect(LspHover.fromJson({'contents': ''}), isNull);
      expect(
        LspHover.fromJson({
          'contents': [
            {'kind': 'markdown', 'value': '  '},
          ],
        }),
        isNull,
      );
      expect(LspHover.fromJson('x'), isNull);
    });
  });

  group('asking for it', () {
    test('sends the document and the place, and reads the answer', () async {
      Object? asked;
      final pair = LspTestPair.create(
        onHover: (params) {
          asked = params;
          return {
            'contents': {'kind': 'markdown', 'value': 'a number'},
          };
        },
      );
      await pair.client.initialize();
      final hover = await pair.client.hover(
        'file:///a.luau',
        const LspPosition(2, 5),
      );
      expect(hover!.markdown, 'a number');
      expect(asked, {
        'textDocument': {'uri': 'file:///a.luau'},
        'position': {'line': 2, 'character': 5},
      });
      await pair.dispose();
    });

    test('is null where the server says nothing', () async {
      final pair = LspTestPair.create(onHover: (_) => null);
      await pair.client.initialize();
      expect(
        await pair.client.hover('file:///a.luau', const LspPosition(0, 0)),
        isNull,
      );
      await pair.dispose();
    });

    test('is not done before the server is initialized', () async {
      final pair = LspTestPair.create(onHover: (_) => {'contents': 'x'});
      expect(
        await pair.client.hover('file:///a.luau', const LspPosition(0, 0)),
        isNull,
      );
      await pair.dispose();
    });

    test('says that hovers are understood as markdown', () async {
      final pair = LspTestPair.create();
      Object? capabilities;
      pair.server.onRequest = (method, params) async {
        if (method == 'initialize') {
          capabilities = (params! as Map)['capabilities'];
          return {'capabilities': <String, Object?>{}};
        }
        return null;
      };
      await pair.client.initialize();
      final textDocument = (capabilities! as Map)['textDocument'] as Map;
      expect(textDocument['hover'], {
        'dynamicRegistration': false,
        'contentFormat': ['markdown', 'plaintext'],
      });
      await pair.dispose();
    });
  });
}
