import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor_core/buffer.dart';
import 'package:ui/editor_core/patch.dart' show Bias;
import 'package:ui/native_editor/diagnostic_hover.dart';
import 'package:ui/native_editor/editor_controller.dart';
import 'package:ui/native_editor/editor_style.dart';
import 'package:ui/native_editor/hover_markdown.dart';

void main() {
  group('the blocks of markdown', () {
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
      final text = tester.widget<Text>(find.text('local x'));
      expect(text.style!.fontFamily, 'Roboto');
      expect(text.style!.fontSize, 14);
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
      expect(box.height, lessThanOrEqualTo(120));
      expect(box.width, lessThanOrEqualTo(300));
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
