import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor_core/buffer.dart';
import 'package:ui/editor_core/patch.dart' show Bias;
import 'package:ui/editor_core/highlight.dart';
import 'package:ui/native_editor/diagnostic_hover.dart';
import 'package:ui/native_editor/editor_controller.dart';
import 'package:ui/native_editor/editor_style.dart';
import 'package:ui/native_editor/hover_markdown.dart';
import 'package:ui/syntax/code_highlighter.dart';
import 'package:ui/syntax/syntax_tree.dart';

/// a highlighter that has the colors of some codes, and not the parser
class _FakeHighlighter extends CodeHighlighter {
  _FakeHighlighter(this.known) : super('', SyntaxTheme({}));

  final Map<String, List<SyntaxSpan>> known;

  @override
  List<SyntaxSpan> spans(String code) => known[code] ?? const [];
}

void main() {
  group('the blocks of markdown', () {
    test('say the language that a fence names', () {
      MarkdownBlock first(String source) => parseMarkdown(source).first;
      expect(first('```luau\nx\n```').language, 'luau');
      expect(first('```Luau title="a"\nx\n```').language, 'luau');
      expect(first('```\nx\n```').language, isNull);
      expect(first('~~~lua\nx\n~~~').language, 'lua');
    });

    List<String> kinds(String source) => [
      for (final b in parseMarkdown(source)) b.kind.name,
    ];

    test('are a fenced code, and the text after it', () {
      final blocks = parseMarkdown(
        '```luau\nlocal x: number\n```\n\nA number.',
      );
      expect(kinds('```luau\nlocal x: number\n```\n\nA number.'), [
        'code',
        'paragraph',
      ]);
      expect(blocks[0].text, 'local x: number');
      expect(blocks[1].text, 'A number.');
    });

    test('hold what comes after a fence that is not closed', () {
      final blocks = parseMarkdown('```luau\nfunction f()\n  return 1');
      expect(blocks, hasLength(1));
      expect(blocks.single.text, 'function f()\n  return 1');
    });

    test('are not cut by what looks like a fence in a code', () {
      final blocks = parseMarkdown('````\n```\ninner\n```\n````\nafter');
      expect(blocks.first.text, '```\ninner\n```');
      expect(blocks.last.text, 'after');
    });

    test('have rules, headings, quotes and items', () {
      expect(kinds('---\n# Title\n> said\n- one\n2. two\ntext\nmore'), [
        'rule',
        'heading',
        'quote',
        'item',
        'item',
        'paragraph',
      ]);
      final blocks = parseMarkdown('- one\n12. two');
      expect(blocks[0].marker, '•');
      expect(blocks[1].marker, '12.');
      expect(blocks[1].text, 'two');
    });

    test(
      'keep the lines of a paragraph together, and a blank line ends it',
      () {
        final blocks = parseMarkdown('one\ntwo\n\nthree');
        expect(blocks.map((b) => b.text), ['one\ntwo', 'three']);
      },
    );

    test('are none for nothing', () {
      expect(parseMarkdown(''), isEmpty);
      expect(parseMarkdown('  \n\n '), isEmpty);
    });
  });

  group('the inline marks', () {
    const code = TextStyle(fontFamily: 'code');
    const link = TextStyle(decoration: TextDecoration.underline);
    const styles = InlineStyles(text: TextStyle(), code: code, link: link);

    List<InlineSpan> spans(String source, [List<String>? links]) => inlineSpans(
      source,
      styles,
      onLink: (url) {
        links?.add(url);
        return TapGestureRecognizer();
      },
    );

    String plain(List<InlineSpan> spans) =>
        TextSpan(children: spans).toPlainText();

    test('are code, bold, italic and links, without their marks', () {
      expect(plain(spans('a `b` **c** *d* [e](http://x)')), 'a b c d e');
    });

    test('give code its style, and a link its address', () {
      final links = <String>[];
      final result = spans('`x` and [y](http://example.com/a)', links);
      expect((result.first as TextSpan).style, code);
      expect(links, ['http://example.com/a']);
      expect((result.last as TextSpan).style, link);
    });

    test('give the text of a link, all of it, the press of the link', () {
      final result = spans('[a **b** `c`](http://x)');
      var texts = 0;
      var pressable = 0;
      for (final span in result) {
        span.visitChildren((s) {
          if (s is TextSpan && s.text != null) {
            texts++;
            if (s.recognizer != null) {
              pressable++;
            }
          }
          return true;
        });
      }
      expect(texts, 4);
      expect(pressable, texts);
    });

    test('leave an underscore in a word, and a star that is alone', () {
      expect(
        plain(spans('my_local_name and 2 * 3')),
        'my_local_name and 2 * 3',
      );
    });

    test('make a line that ends a space, unless it ends in two spaces', () {
      expect(plain(spans('one\ntwo')), 'one two');
      expect(plain(spans('one  \ntwo')), 'one\ntwo');
    });

    test('take an escaped mark as itself', () {
      expect(plain(spans(r'\*not\* \`this\`')), '*not* `this`');
    });

    test('keep what is not closed as it is', () {
      expect(plain(spans('a `b')), 'a `b');
      expect(plain(spans('a [b')), 'a [b');
      expect(plain(spans('a **b')), 'a **b');
    });
  });

  group('the popover of a symbol', () {
    const style = EditorStyle(
      textStyle: TextStyle(fontFamily: 'Roboto', fontSize: 14, height: 1.5),
      popoverText: TextStyle(fontFamily: 'Roboto', fontSize: 14, height: 1.5),
    );

    Future<void> pump(
      WidgetTester tester,
      String markdown, {
      EditorStyle style = style,
      Size limit = const Size(400, 200),
      Future<void> Function(String url)? onOpenLink,
    }) {
      final buffer = TextBuffer('abc');
      return tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: InfoPopover(
              info: HoverInfo(
                range: AnchorRange(
                  buffer.anchorAt(0, Bias.right),
                  buffer.anchorAt(1, Bias.left),
                ),
                markdown: markdown,
              ),
              style: style,
              contentLimit: limit,
              onOpenLink: onOpenLink ?? (_) async {},
            ),
          ),
        ),
      );
    }

    group('has the room that the blocks of a hover have', () {
      Rect rect(WidgetTester tester, String text) =>
          tester.getRect(find.textContaining(text, findRichText: true).first);

      testWidgets('a paragraph is 1.3 rems high a line, with 8 under it', (
        tester,
      ) async {
        await pump(tester, 'one\n\ntwo');
        final one = rect(tester, 'one');
        final two = rect(tester, 'two');
        // the engine makes the box of a line a whole number of pixels
        expect(one.height, closeTo(20.8, 0.5));
        expect(two.top - one.bottom, closeTo(8, 0.01));
      });

      testWidgets('there is 8 pixels of a paragraph under the last one', (
        tester,
      ) async {
        await pump(tester, 'one');
        final popover = tester.getRect(find.byType(InfoPopover));
        final one = rect(tester, 'one');
        // 8 of the padding, and the 8 of the paragraph; the border is 1
        expect(popover.bottom - one.bottom, closeTo(1 + 8 + 8, 0.01));
        expect(one.top - popover.top, closeTo(1 + 8, 0.01));
      });

      testWidgets('a code has a rem over it and a rem under it', (
        tester,
      ) async {
        await pump(tester, 'one\n\n```luau\nlocal x\n```\n\ntwo');
        final one = rect(tester, 'one');
        final code = rect(tester, 'local x');
        final two = rect(tester, 'two');
        // the 8 of the paragraph, and the 16 of the code
        expect(code.top - one.bottom, closeTo(8 + 16, 0.01));
        expect(two.top - code.bottom, closeTo(16, 0.01));
      });

      testWidgets('a code at the start has its rem over it, too', (
        tester,
      ) async {
        await pump(tester, '```luau\nlocal x\n```');
        final popover = tester.getRect(find.byType(InfoPopover));
        final code = rect(tester, 'local x');
        expect(code.top - popover.top, closeTo(1 + 8 + 16, 0.01));
        expect(popover.bottom - code.bottom, closeTo(1 + 8 + 16, 0.01));
      });

      testWidgets('a rule is a pixel, with 8 over it and 8 under it', (
        tester,
      ) async {
        await pump(tester, 'one\n\n---\n\ntwo');
        final one = rect(tester, 'one');
        final two = rect(tester, 'two');
        // the 8 of the paragraph, 8, the line, and 8
        expect(two.top - one.bottom, closeTo(8 + 8 + 1 + 8, 0.01));
      });

      testWidgets('a heading is bold, of a rem, with a rem over it', (
        tester,
      ) async {
        await pump(tester, 'one\n\n# Title');
        final one = rect(tester, 'one');
        final title = rect(tester, 'Title');
        expect(title.top - one.bottom, closeTo(8 + 16, 0.01));
        final text = tester.widget<RichText>(
          find.textContaining('Title', findRichText: true),
        );
        // the root of the text has the style of its surroundings, and the
        // span of the heading is in it
        final span = (text.text as TextSpan).children!.single as TextSpan;
        expect(span.style!.fontSize, 16);
        expect(span.style!.fontWeight, FontWeight.w700);
      });

      testWidgets('a quote is a rem in, with a line of 4, and 8 under it', (
        tester,
      ) async {
        await pump(tester, '> said\n\nafter');
        final said = rect(tester, 'said');
        final after = rect(tester, 'after');
        final popover = tester.getRect(find.byType(InfoPopover));
        // the border of the popover, its room, the line of the quote, a rem
        expect(said.left - popover.left, closeTo(1 + 8 + 4 + 16, 0.01));
        // the 8 of the paragraph in it, and the 8 of the quote
        expect(after.top - said.bottom, closeTo(8 + 8, 0.01));
      });

      testWidgets('an item is 10 in, 4 from its mark, with 4 under it', (
        tester,
      ) async {
        await pump(tester, '- one\n- two');
        final mark = rect(tester, '•');
        final one = rect(tester, 'one');
        final two = rect(tester, 'two');
        final popover = tester.getRect(find.byType(InfoPopover));
        expect(mark.left - popover.left, closeTo(1 + 8 + 10, 0.01));
        expect(one.left - mark.right, closeTo(4, 0.01));
        expect(one.height, closeTo(20.8, 0.5));
        expect(two.top - one.bottom, closeTo(4, 0.01));
      });

      testWidgets(
        'the rems go with the size of the interface, the pixels not',
        (tester) async {
          await pump(
            tester,
            'one\n\n# Title\n\n```luau\nx\n```\n\ntwo',
            style: const EditorStyle(
              textStyle: TextStyle(fontFamily: 'Roboto', fontSize: 14),
              popoverText: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 14,
                height: 1.5,
              ),
              popoverScale: 2,
            ),
          );
          final one = rect(tester, 'one');
          final title = rect(tester, 'Title');
          final code = rect(tester, 'x');
          final two = rect(tester, 'two');
          // a line of a paragraph is 1.3 rems, which are 32 pixels now
          expect(one.height, closeTo(41.6, 0.5));
          // the 8 of the paragraph is of pixels, the rem of the heading is not
          expect(title.top - one.bottom, closeTo(8 + 32, 0.01));
          expect(two.top - code.bottom, closeTo(32, 0.01));
        },
      );
    });

    group('has the colors of the code', () {
      Future<void> pumpWith(
        WidgetTester tester,
        String markdown,
        CodeHighlighter? highlighter,
      ) {
        final buffer = TextBuffer('abc');
        return tester.pumpWidget(
          MaterialApp(
            home: Align(
              alignment: Alignment.topLeft,
              child: InfoPopover(
                info: HoverInfo(
                  range: AnchorRange(
                    buffer.anchorAt(0, Bias.right),
                    buffer.anchorAt(1, Bias.left),
                  ),
                  markdown: markdown,
                ),
                style: style,
                highlighter: highlighter,
                contentLimit: const Size(400, 200),
                onOpenLink: (_) async {},
              ),
            ),
          ),
        );
      }

      /// the pieces of the code and their colors, as `text:color`
      List<String> pieces(WidgetTester tester) {
        final rich = tester.widget<RichText>(
          find.textContaining('local', findRichText: true),
        );
        final root = rich.text as TextSpan;
        final code = root.children!.single as TextSpan;
        return [
          for (final child in code.children ?? const <InlineSpan>[])
            if (child is TextSpan)
              '${child.text}:${child.style?.color?.toARGB32()}',
        ];
      }

      testWidgets('the words that are read are given theirs', (tester) async {
        await pumpWith(
          tester,
          '```luau\nlocal x = 1\n```',
          _FakeHighlighter({
            'local x = 1': [
              const SyntaxSpan(0, 5, HighlightStyle(color: 0xFFAA0000)),
              const SyntaxSpan(10, 11, HighlightStyle(color: 0xFF00AA00)),
            ],
          }),
        );
        expect(pieces(tester), [
          'local:${0xFFAA0000}',
          ' x = :null',
          '1:${0xFF00AA00}',
        ]);
      });

      testWidgets('a code of another language is plain', (tester) async {
        await pumpWith(
          tester,
          '```rust\nlocal x = 1\n```',
          _FakeHighlighter({
            'local x = 1': [
              const SyntaxSpan(0, 5, HighlightStyle(color: 0xFFAA0000)),
            ],
          }),
        );
        expect(pieces(tester), isEmpty);
        expect(find.text('local x = 1'), findsOneWidget);
      });

      testWidgets('a code is plain without a highlighter', (tester) async {
        await pumpWith(tester, '```luau\nlocal x = 1\n```', null);
        expect(find.text('local x = 1'), findsOneWidget);
      });

      testWidgets('a bold and an italic word are so', (tester) async {
        await pumpWith(
          tester,
          '```lua\nlocal\n```',
          _FakeHighlighter({
            'local': [
              const SyntaxSpan(0, 5, HighlightStyle(bold: true, italic: true)),
            ],
          }),
        );
        final rich = tester.widget<RichText>(
          find.textContaining('local', findRichText: true),
        );
        final code = (rich.text as TextSpan).children!.single as TextSpan;
        final word = code.children!.single as TextSpan;
        expect(word.style!.fontWeight, FontWeight.w700);
        expect(word.style!.fontStyle, FontStyle.italic);
      });
    });

    testWidgets('shows the code and the text of a hover', (tester) async {
      await pump(tester, '```luau\nlocal x: number\n```\n\nThe **count**.');
      expect(find.text('local x: number'), findsOneWidget);
      expect(
        find.textContaining('The count.', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('has the code in the font of the editor', (tester) async {
      await pump(tester, '```luau\nlocal x\n```');
      final rich = tester.widget<RichText>(
        find.textContaining('local x', findRichText: true),
      );
      final code = (rich.text as TextSpan).children!.single as TextSpan;
      expect(code.style!.fontFamily, 'Roboto');
      expect(code.style!.fontSize, 14);
    });

    testWidgets('opens the address of a link that is pressed', (tester) async {
      final opened = <String>[];
      await pump(
        tester,
        'see [the page](https://example.com/p)',
        onOpenLink: (url) async => opened.add(url),
      );
      final rich = tester.widget<RichText>(
        find.textContaining('see the page', findRichText: true),
      );
      final span = rich.text as TextSpan;
      TapGestureRecognizer? recognizer;
      span.visitChildren((s) {
        if (s is TextSpan && s.recognizer is TapGestureRecognizer) {
          recognizer = s.recognizer as TapGestureRecognizer;
        }
        return true;
      });
      recognizer!.onTap!();
      expect(opened, ['https://example.com/p']);
    });

    testWidgets('is scrolled when it is more than the limit', (tester) async {
      final lines = List.generate(40, (i) => 'line $i').join('\n\n');
      await pump(tester, lines, limit: const Size(300, 120));
      final box = tester.getRect(find.byType(InfoPopover));
      // the limit is of what is inside the border, which is a pixel at each side
      expect(box.height, lessThanOrEqualTo(120 + 2));
      expect(box.width, lessThanOrEqualTo(300 + 2));
    });

    testWidgets('has room in rems around the text', (tester) async {
      await pump(tester, 'x');
      final small = tester.getRect(find.byType(InfoPopover));
      await pump(
        tester,
        'x',
        style: const EditorStyle(
          textStyle: TextStyle(fontFamily: 'Roboto', fontSize: 14),
          popoverText: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 14,
            height: 1.5,
          ),
          popoverScale: 2,
        ),
      );
      final large = tester.getRect(find.byType(InfoPopover));
      // the room at both sides of the text is of 8 rems
      expect(large.width - small.width, closeTo(2 * 8 * (2 - 1), 0.5));
    });
  });

  group('popovers one over the other', () {
    test('go above the place with a gap, the first nearest to it', () {
      final at = placePopovers(const Rect.fromLTWH(50, 300, 8, 20), const [
        Size(100, 40),
        Size(100, 60),
      ], const Size(500, 500));
      expect(at[0], const Offset(50, 300 - 40));
      expect(at[1], Offset(50, 300 - 40 - popoverGap - 60));
    });

    test('go below the place when they do not fit above it', () {
      final at = placePopovers(const Rect.fromLTWH(50, 60, 8, 20), const [
        Size(100, 40),
        Size(100, 60),
      ], const Size(500, 500));
      expect(at[0], const Offset(50, 80));
      expect(at[1], Offset(50, 80 + 40 + popoverGap));
    });

    test('are all above or all below, and not one of each', () {
      // the first fits above the place, but both do not
      final at = placePopovers(const Rect.fromLTWH(50, 70, 8, 20), const [
        Size(100, 40),
        Size(100, 60),
      ], const Size(500, 500));
      expect(at[0].dy, 90);
      expect(at[1].dy, 90 + 40 + popoverGap);
    });

    test('keep clear of the right edge, each by its own width', () {
      final at = placePopovers(const Rect.fromLTWH(380, 300, 8, 20), const [
        Size(60, 40),
        Size(100, 40),
      ], const Size(400, 500));
      expect(at[0].dx + 60, 400 - popoverRightMargin);
      expect(at[1].dx + 100, 400 - popoverRightMargin);
    });

    test('are the one that placePopover places, when there is one', () {
      const target = Rect.fromLTWH(50, 100, 8, 20);
      const size = Size(100, 40);
      const area = Size(500, 500);
      expect(
        placePopovers(target, const [size], area).single,
        placePopover(target, size, area),
      );
    });
  });
}
