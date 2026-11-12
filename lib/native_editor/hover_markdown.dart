import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../syntax/code_highlighter.dart';
import 'diagnostic_hover.dart';
import 'editor_controller.dart';
import 'editor_style.dart';
import 'popover_scrollbar.dart';
import 'scrollbar_layout.dart';

/// the kinds of block that the markdown of a hover has
enum MarkdownBlockKind { paragraph, code, rule, heading, quote, item }

/// one block of markdown: a paragraph, a fenced code, a rule, a heading, a
/// quote or an item of a list
class MarkdownBlock {
  const MarkdownBlock(this.kind, this.text, {this.marker, this.language});

  final MarkdownBlockKind kind;

  /// the language that the fence of a code names, which is the first word
  /// that follows it; null when it names none
  final String? language;

  /// the text; for a code it is the code as it is, and for the others it still
  /// has its inline marks
  final String text;

  /// what an item starts with: a bullet, or its number
  final String? marker;

  @override
  String toString() => '$kind($text)';
}

final RegExp _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})\s*([^`]*)$');
final RegExp _rule = RegExp(r'^ {0,3}([-*_])( *\1){2,} *$');
final RegExp _heading = RegExp(r'^ {0,3}#{1,6}\s+(.*?)\s*#*\s*$');
final RegExp _bullet = RegExp(r'^\s*[-*+]\s+(.*)$');
final RegExp _numbered = RegExp(r'^\s*(\d{1,9})[.)]\s+(.*)$');
final RegExp _quote = RegExp(r'^ {0,3}>\s?(.*)$');

/// splits [source] into its blocks. a fence that is not closed holds what comes
/// after it, as the markdown of a server is often cut
List<MarkdownBlock> parseMarkdown(String source) {
  final blocks = <MarkdownBlock>[];
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final paragraph = <String>[];

  void endParagraph() {
    if (paragraph.isNotEmpty) {
      blocks.add(
        MarkdownBlock(MarkdownBlockKind.paragraph, paragraph.join('\n')),
      );
      paragraph.clear();
    }
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final fence = _fence.firstMatch(line);
    if (fence != null) {
      endParagraph();
      final mark = fence.group(1)!;
      final code = <String>[];
      i++;
      while (i < lines.length) {
        final closing = lines[i].trim();
        if (closing.startsWith(mark[0] * mark.length) &&
            closing.replaceAll(mark[0], '').isEmpty) {
          break;
        }
        code.add(lines[i]);
        i++;
      }
      // past the closing fence, when there is one
      i++;
      final language = (fence.group(2) ?? '')
          .trim()
          .split(RegExp(r'[\s,{]'))
          .first;
      blocks.add(
        MarkdownBlock(
          MarkdownBlockKind.code,
          code.join('\n'),
          language: language.isEmpty ? null : language.toLowerCase(),
        ),
      );
      continue;
    }
    if (line.trim().isEmpty) {
      endParagraph();
      i++;
      continue;
    }
    if (_rule.hasMatch(line)) {
      endParagraph();
      blocks.add(const MarkdownBlock(MarkdownBlockKind.rule, ''));
      i++;
      continue;
    }
    final heading = _heading.firstMatch(line);
    if (heading != null) {
      endParagraph();
      blocks.add(MarkdownBlock(MarkdownBlockKind.heading, heading.group(1)!));
      i++;
      continue;
    }
    final quote = _quote.firstMatch(line);
    if (quote != null) {
      endParagraph();
      blocks.add(MarkdownBlock(MarkdownBlockKind.quote, quote.group(1)!));
      i++;
      continue;
    }
    final bullet = _bullet.firstMatch(line);
    final numbered = bullet == null ? _numbered.firstMatch(line) : null;
    if (bullet != null || numbered != null) {
      endParagraph();
      blocks.add(
        MarkdownBlock(
          MarkdownBlockKind.item,
          bullet != null ? bullet.group(1)! : numbered!.group(2)!,
          marker: bullet != null ? '•' : '${numbered!.group(1)}.',
        ),
      );
      i++;
      continue;
    }
    paragraph.add(line);
    i++;
  }
  endParagraph();
  return blocks;
}

/// how the text of inline markdown is styled
class InlineStyles {
  const InlineStyles({
    required this.text,
    required this.code,
    required this.link,
  });

  final TextStyle text;
  final TextStyle code;
  final TextStyle link;
}

/// the spans of [source], which is inline markdown: `code`, **bold**,
/// *italic*, [links](address) and what is escaped with a backslash. a line
/// that ends is a space, as in markdown, unless it ends in two spaces or a
/// backslash. [onLink] gets the recognizer for an address
List<InlineSpan> inlineSpans(
  String source,
  InlineStyles styles, {
  required GestureRecognizer Function(String url) onLink,
}) {
  final spans = <InlineSpan>[];
  final buffer = StringBuffer();

  void flush() {
    if (buffer.isNotEmpty) {
      spans.add(TextSpan(text: buffer.toString()));
      buffer.clear();
    }
  }

  bool isWord(String char) => RegExp(r'[A-Za-z0-9]').hasMatch(char);

  var i = 0;
  while (i < source.length) {
    final char = source[i];
    if (char == '\\' && i + 1 < source.length) {
      if (source[i + 1] == '\n') {
        buffer.write('\n');
      } else {
        buffer.write(source[i + 1]);
      }
      i += 2;
      continue;
    }
    if (char == '\n') {
      final hard = buffer.toString().endsWith('  ');
      if (hard) {
        final text = buffer.toString();
        buffer
          ..clear()
          ..write(text.trimRight())
          ..write('\n');
      } else {
        buffer.write(' ');
      }
      i++;
      continue;
    }
    if (char == '`') {
      var ticks = 1;
      while (i + ticks < source.length && source[i + ticks] == '`') {
        ticks++;
      }
      final mark = '`' * ticks;
      final end = source.indexOf(mark, i + ticks);
      if (end > 0) {
        flush();
        final code = source
            .substring(i + ticks, end)
            .replaceAll('\n', ' ')
            .trim();
        spans.add(TextSpan(text: code, style: styles.code));
        i = end + ticks;
        continue;
      }
    }
    if (char == '*' || char == '_') {
      final strong = i + 1 < source.length && source[i + 1] == char;
      final mark = strong ? char * 2 : char;
      final before = i == 0 ? ' ' : source[i - 1];
      // an underscore in the middle of a word is a part of it
      final opens = char == '*' || !isWord(before);
      final end = source.indexOf(mark, i + mark.length);
      if (opens &&
          end > i + mark.length &&
          source[i + mark.length] != ' ' &&
          (char == '*' ||
              end + mark.length >= source.length ||
              !isWord(source[end + mark.length]))) {
        flush();
        final inner = inlineSpans(
          source.substring(i + mark.length, end),
          styles,
          onLink: onLink,
        );
        spans.add(
          TextSpan(
            style: strong
                ? const TextStyle(fontWeight: FontWeight.w700)
                : const TextStyle(fontStyle: FontStyle.italic),
            children: inner,
          ),
        );
        i = end + mark.length;
        continue;
      }
    }
    if (char == '[') {
      final close = _matchingBracket(source, i);
      if (close > 0 && close + 1 < source.length && source[close + 1] == '(') {
        final end = source.indexOf(')', close + 2);
        if (end > 0) {
          flush();
          final url = source.substring(close + 2, end).trim().split(' ').first;
          final recognizer = onLink(url);
          spans.add(
            TextSpan(
              style: styles.link,
              // a recognizer is for the text of the span that has it, and
              // not for that of its children, so each of them has it
              children: [
                for (final inner in inlineSpans(
                  source.substring(i + 1, close),
                  styles,
                  onLink: onLink,
                ))
                  _withRecognizer(inner, recognizer),
              ],
            ),
          );
          i = end + 1;
          continue;
        }
      }
    }
    buffer.write(char);
    i++;
  }
  flush();
  return spans;
}

/// [span], and all that is in it, that has text, taking presses with
/// [recognizer]
InlineSpan _withRecognizer(InlineSpan span, GestureRecognizer recognizer) {
  if (span is! TextSpan) {
    return span;
  }
  return TextSpan(
    text: span.text,
    style: span.style,
    recognizer: recognizer,
    children: [
      for (final child in span.children ?? const <InlineSpan>[])
        _withRecognizer(child, recognizer),
    ],
  );
}

/// where the bracket that closes the one at [open] is, or -1
int _matchingBracket(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '\\') {
      i++;
    } else if (source[i] == '[') {
      depth++;
    } else if (source[i] == ']') {
      depth--;
      if (depth == 0) {
        return i;
      }
    }
  }
  return -1;
}

/// the blocks of markdown, one under the other
class HoverMarkdown extends StatefulWidget {
  const HoverMarkdown({
    super.key,
    required this.markdown,
    required this.style,
    this.highlighter,
    this.onOpenLink = openLink,
  });

  final String markdown;
  final EditorStyle style;

  /// gives the code in a fence of a language that it reads its colors
  final CodeHighlighter? highlighter;
  final Future<void> Function(String url) onOpenLink;

  @override
  State<HoverMarkdown> createState() => _HoverMarkdownState();
}

class _HoverMarkdownState extends State<HoverMarkdown> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _release() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  GestureRecognizer _link(String url) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => widget.onOpenLink(url);
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    // the recognizers are made again with the spans, so the old ones go
    _release();
    final style = widget.style;
    final base = style.popoverText;
    // code is in the font of the editor, at the size of the text around it
    final code = style.textStyle.copyWith(
      fontSize: base.fontSize,
      height: base.height,
      color: base.color,
    );
    final styles = InlineStyles(
      text: base,
      code: code.copyWith(backgroundColor: style.popoverCodeBackground),
      link: TextStyle(
        color: base.color,
        decoration: TextDecoration.underline,
        decorationColor: base.color,
      ),
    );
    final blocks = parseMarkdown(widget.markdown);
    // every block has the margins of its own, and they do not run together;
    // but the first has no room over it, and the last none under it
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < blocks.length; i++)
          _block(
            blocks[i],
            styles,
            code,
            first: i == 0,
            last: i == blocks.length - 1,
          ),
      ],
    );
  }

  /// the height of a line of a paragraph, as a share of the size of its text:
  /// it is a length of 1.3 rems, and does not go with the size of the text
  TextStyle _paragraphText(TextStyle text) => text.copyWith(
    height:
        widget.style.popoverRem(EditorStyle.paragraphLineHeight) /
        text.fontSize!,
  );

  Widget _text(String text, TextStyle style, InlineStyles styles) => Text.rich(
    TextSpan(
      style: style,
      children: inlineSpans(text, styles, onLink: _link),
    ),
  );

  /// the text of a code, in the colors of its language when it is read
  InlineSpan _code(MarkdownBlock block, TextStyle code) {
    final highlighter = widget.highlighter;
    if (highlighter == null || !CodeHighlighter.reads(block.language)) {
      return TextSpan(text: block.text, style: code);
    }
    final children = <InlineSpan>[];
    var at = 0;
    for (final span in highlighter.spans(block.text)) {
      final start = span.start.clamp(at, block.text.length);
      final end = span.end.clamp(start, block.text.length);
      if (end == start) {
        continue;
      }
      if (start > at) {
        children.add(TextSpan(text: block.text.substring(at, start)));
      }
      final look = span.style;
      children.add(
        TextSpan(
          text: block.text.substring(start, end),
          style: TextStyle(
            color: look.color == null ? null : Color(look.color!),
            fontWeight: look.bold == true ? FontWeight.w700 : null,
            fontStyle: look.italic == true ? FontStyle.italic : null,
          ),
        ),
      );
      at = end;
    }
    if (at < block.text.length) {
      children.add(TextSpan(text: block.text.substring(at)));
    }
    return TextSpan(style: code, children: children);
  }

  /// a paragraph, with the room under it that a paragraph has, which is of
  /// pixels and not of rems, and none when it is the last block
  Widget _paragraph(
    String text,
    InlineStyles styles, {
    TextStyle? over,
    required bool last,
  }) => Padding(
    padding: EdgeInsets.only(bottom: last ? 0 : EditorStyle.paragraphSpacing),
    child: _text(
      text,
      _paragraphText(over == null ? styles.text : styles.text.merge(over)),
      styles,
    ),
  );

  /// [block], with its margins: those over the first block and under the last
  /// are none, as the room at the ends is the popover's own
  Widget _block(
    MarkdownBlock block,
    InlineStyles styles,
    TextStyle code, {
    required bool first,
    required bool last,
  }) {
    final style = widget.style;
    switch (block.kind) {
      case MarkdownBlockKind.paragraph:
        return _paragraph(block.text, styles, last: last);
      case MarkdownBlockKind.heading:
        // a heading is bold, of the size of a rem, with a rem over it and
        // nothing under it
        return Padding(
          padding: EdgeInsets.only(top: first ? 0 : style.popoverRem(16)),
          child: _text(
            block.text,
            styles.text.copyWith(
              fontSize: style.popoverRem(16),
              fontWeight: FontWeight.w700,
            ),
            styles,
          ),
        );
      case MarkdownBlockKind.code:
        // a rem over and under the code
        return Padding(
          padding: EdgeInsets.only(
            top: first ? 0 : style.popoverRem(16),
            bottom: last ? 0 : style.popoverRem(16),
          ),
          child: Text.rich(_code(block, code)),
        );
      case MarkdownBlockKind.rule:
        // a line of a pixel, with the room of a paragraph over and under it
        return Container(
          margin: EdgeInsets.only(
            top: first ? 0 : EditorStyle.paragraphSpacing,
            bottom: last ? 0 : EditorStyle.paragraphSpacing,
          ),
          height: 1,
          color: style.popoverRule,
        );
      case MarkdownBlockKind.quote:
        // the text of a quote is a paragraph in it; the quote has the room of
        // a paragraph under it too
        return Container(
          margin: EdgeInsets.only(
            bottom: last ? 0 : EditorStyle.paragraphSpacing,
          ),
          padding: EdgeInsets.only(left: style.popoverRem(16)),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: style.popoverMuted, width: 4),
            ),
          ),
          child: _paragraph(
            block.text,
            styles,
            over: TextStyle(color: style.popoverMuted),
            last: last,
          ),
        );
      case MarkdownBlockKind.item:
        // a list is a rem and a quarter in from the left, its items have a
        // quarter of a rem under them and between the mark and the text
        return Padding(
          padding: EdgeInsets.only(
            left: style.popoverRem(10),
            bottom: last ? 0 : style.popoverRem(4),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(block.marker ?? '•', style: _paragraphText(styles.text)),
              SizedBox(width: style.popoverRem(4)),
              Flexible(
                child: _text(block.text, _paragraphText(styles.text), styles),
              ),
            ],
          ),
        );
    }
  }
}

/// what the language server said of a symbol: its markdown in a box of the
/// surface of popovers
class InfoPopover extends StatefulWidget {
  const InfoPopover({
    super.key,
    required this.info,
    required this.style,
    required this.contentLimit,
    this.highlighter,
    this.onOpenLink = openLink,
    this.onPointer,
    this.scrollbarShow = ScrollbarVisibility.auto,
    this.systemAutoHide = false,
  });

  /// gives the code of the text its colors
  final CodeHighlighter? highlighter;

  final HoverInfo info;
  final EditorStyle style;

  /// the most that the text can be, which is scrolled when it is more
  final Size contentLimit;
  final Future<void> Function(String url) onOpenLink;

  /// told when the pointer moves over the popover
  final VoidCallback? onPointer;
  final ScrollbarVisibility scrollbarShow;
  final bool systemAutoHide;

  @override
  State<InfoPopover> createState() => _InfoPopoverState();
}

class _InfoPopoverState extends State<InfoPopover> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final limit = widget.contentLimit;
    return MouseRegion(
      opaque: true,
      cursor: SystemMouseCursors.basic,
      onHover: (_) => widget.onPointer?.call(),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        // a container, as its border takes room that the content is not in
        child: Container(
          decoration: BoxDecoration(
            color: style.popoverSurface,
            borderRadius: BorderRadius.circular(style.popoverRadius),
            border: Border.all(color: style.popoverBorder),
            boxShadow: const [
              BoxShadow(
                offset: Offset(0, 2),
                blurRadius: 3,
                color: Color(0x1F000000),
              ),
              BoxShadow(offset: Offset(0, 1), color: Color(0x0F000000)),
            ],
          ),
          child: PopoverScrollbar(
            controller: _scroll,
            behavior: popoverScrollbarBehavior(
              widget.scrollbarShow,
              systemAutoHide: widget.systemAutoHide,
            ),
            thumb: style.scrollbarThumb,
            thumbHover: style.scrollbarThumbHover,
            thumbActive: style.scrollbarThumbActive,
            surface: style.scrollbarTrack,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: limit.width,
                maxHeight: limit.height,
              ),
              child: SingleChildScrollView(
                controller: _scroll,
                child: Padding(
                  padding: EdgeInsets.all(style.popoverRem(8)),
                  child: IntrinsicWidth(
                    child: HoverMarkdown(
                      markdown: widget.info.markdown,
                      highlighter: widget.highlighter,
                      style: style,
                      onOpenLink: widget.onOpenLink,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
