import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Icons, Tooltip;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'editor_controller.dart';
import 'editor_style.dart';
import 'popover_scrollbar.dart';
import 'scrollbar_layout.dart' show ScrollbarVisibility;

/// when the editor says what the language server found about the text that the
/// pointer rests on
@immutable
class HoverSettings {
  const HoverSettings({
    this.enabled = true,
    this.delay = defaultDelay,
    this.sticky = true,
    this.hidingDelay = defaultHidingDelay,
  });

  static const defaultDelay = Duration(milliseconds: 300);
  static const defaultHidingDelay = Duration(milliseconds: 300);

  /// whether anything is shown when the pointer rests on text
  final bool enabled;

  /// how long the pointer rests before it is shown
  final Duration delay;

  /// whether it stays while the pointer goes toward it, so that what is in it
  /// can be used
  final bool sticky;

  /// how long it stays once the pointer is going away from it; only with
  /// [sticky]
  final Duration hidingDelay;

  @override
  bool operator ==(Object other) =>
      other is HoverSettings &&
      other.enabled == enabled &&
      other.delay == delay &&
      other.sticky == sticky &&
      other.hidingDelay == hidingDelay;

  @override
  int get hashCode => Object.hash(enabled, delay, sticky, hidingDelay);
}

/// the most that the text of a popover can be: 120 columns and 16 rows, but
/// not more than half of the editor, and not less than 20 columns and 4 rows
Size popoverContentLimit({
  required Size area,
  required double charWidth,
  required double lineHeight,
}) => Size(
  math.max(math.min(120 * charWidth, area.width / 2), 20 * charWidth),
  math.max(math.min(16 * lineHeight, area.height / 2), 4 * lineHeight),
);

/// the space between a popover and the right edge of the editor
const double popoverRightMargin = 8;

/// the space between popovers that are one over the other, which is of pixels
const double popoverGap = 10;

/// where a popover of [size] goes for the place [target] in an [area]: directly
/// above the row when it fits there, and otherwise directly below it. it is
/// moved to the left, as far as it takes, to keep clear of the right edge. when
/// it fits in neither place it is below, kept inside the area
Offset placePopover(Rect target, Size size, Size area) =>
    placePopovers(target, [size], area).single;

/// where popovers of [sizes] go, one over the other with [popoverGap] between
/// them, the first nearest the row: all of them above the row when they fit
/// there, and otherwise all below it, and when they fit in neither place they
/// are below, kept inside the area
List<Offset> placePopovers(Rect target, List<Size> sizes, Size area) {
  final bounds = Offset.zero & area;
  Offset origin(double y, Size size) => Offset(
    target.left +
        math.min(
          0.0,
          area.width - popoverRightMargin - (target.left + size.width),
        ),
    y,
  );
  bool fits(Offset at, Size size) {
    final box = at & size;
    return box.left >= bounds.left &&
        box.top >= bounds.top &&
        box.right <= bounds.right &&
        box.bottom <= bounds.bottom;
  }

  final above = <Offset>[];
  var y = target.top;
  for (final size in sizes) {
    final at = origin(y - size.height, size);
    above.add(at);
    y = at.dy - popoverGap;
  }
  if (List.generate(
    sizes.length,
    (i) => fits(above[i], sizes[i]),
  ).every((f) => f)) {
    return above;
  }
  final below = <Offset>[];
  y = target.bottom;
  for (final size in sizes) {
    final at = origin(y, size);
    below.add(at);
    y = at.dy + size.height + popoverGap;
  }
  if (List.generate(
    sizes.length,
    (i) => fits(below[i], sizes[i]),
  ).every((f) => f)) {
    return below;
  }
  return [
    for (var i = 0; i < sizes.length; i++)
      Offset(
        below[i].dx.clamp(0.0, math.max(0.0, area.width - sizes[i].width)),
        below[i].dy.clamp(0.0, math.max(0.0, area.height - sizes[i].height)),
      ),
  ];
}

class _PopoverPlacement extends MultiChildLayoutDelegate {
  _PopoverPlacement(this.target, this.count);

  final Rect target;
  final int count;

  /// the ids of the blocks that fill the space between the popovers, which the
  /// pointer is on, and not on the text under them; they start after the ids
  /// of the popovers, which are their places in the list
  static int gapId(int index) => _firstGapId + index;

  static const int _firstGapId = 1000;

  @override
  void performLayout(Size size) {
    final sizes = [
      for (var i = 0; i < count; i++)
        layoutChild(i, BoxConstraints.loose(size)),
    ];
    final origins = placePopovers(target, sizes, size);
    for (var i = 0; i < count; i++) {
      positionChild(i, origins[i]);
    }
    // the gap is on the side of a popover that the next one is on
    for (var i = 0; i < count - 1; i++) {
      final above = origins[i + 1].dy < origins[i].dy;
      final width = sizes[i].width;
      layoutChild(gapId(i), BoxConstraints.tight(Size(width, popoverGap)));
      positionChild(
        gapId(i),
        Offset(
          origins[i].dx,
          above ? origins[i].dy - popoverGap : origins[i].dy + sizes[i].height,
        ),
      );
    }
  }

  @override
  bool shouldRelayout(_PopoverPlacement oldDelegate) => true;
}

/// popovers for the place [target] of an editor, which fills the space that
/// the editor is in, one over the other, the first nearest the place. the
/// pointer is only on them where they are, and in the gaps between them
class PopoverLayer extends StatelessWidget {
  const PopoverLayer({
    super.key,
    required this.target,
    required this.children,
    this.onGap,
  });

  final Rect target;
  final List<Widget> children;

  /// told when the pointer is in a gap between popovers
  final VoidCallback? onGap;

  @override
  Widget build(BuildContext context) => CustomMultiChildLayout(
    delegate: _PopoverPlacement(target, children.length),
    children: [
      for (var i = 0; i < children.length; i++)
        LayoutId(id: i, child: children[i]),
      for (var i = 0; i < children.length - 1; i++)
        LayoutId(
          id: _PopoverPlacement.gapId(i),
          child: MouseRegion(
            opaque: true,
            onHover: (_) => onGap?.call(),
            child: const SizedBox.expand(),
          ),
        ),
    ],
  );
}

/// how much a background of a popover shows of the color of how bad it is
int _backgroundAlpha(DetailSeverity level) => switch (level) {
  DetailSeverity.error || DetailSeverity.warning => 0x1F,
  DetailSeverity.information => 0x33,
  DetailSeverity.hint => 0,
};

Color diagnosticLevelColor(DetailSeverity level, DiagnosticColors colors) =>
    Color(switch (level) {
      DetailSeverity.error => colors.error,
      DetailSeverity.warning => colors.warning,
      DetailSeverity.information => colors.information,
      DetailSeverity.hint => colors.hint,
    });

/// the message of a diagnostic, and after it in parentheses where it comes
/// from, with the code a link when the server says where it is explained
InlineSpan diagnosticText(
  DiagnosticDetail detail,
  TextStyle style,
  TextStyle linkStyle, {
  GestureRecognizer? onLink,
}) {
  final source = detail.source;
  final code = detail.code;
  return TextSpan(
    style: style,
    children: [
      TextSpan(text: detail.message),
      if (source != null || code != null) ...[
        TextSpan(
          text: ' (${source ?? ''}${source != null && code != null ? ' ' : ''}',
        ),
        if (code != null)
          TextSpan(
            text: code,
            style: detail.codeHref == null ? null : linkStyle,
            recognizer: detail.codeHref == null ? null : onLink,
          ),
        const TextSpan(text: ')'),
      ],
    ],
  );
}

/// opens [url] in the browser; only web pages are opened
Future<void> openLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return;
  }
  try {
    if (Platform.isWindows) {
      await Process.start('rundll32', ['url.dll,FileProtocolHandler', url]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [url]);
    } else {
      await Process.start('xdg-open', [url]);
    }
  } on ProcessException {
    // there is no browser to open it with
  }
}

/// what the language server said about a place: in a box with the color of how
/// bad it is, with a button that copies the message
class DiagnosticPopover extends StatefulWidget {
  const DiagnosticPopover({
    super.key,
    required this.detail,
    required this.colors,
    required this.style,
    required this.contentLimit,
    this.onOpenLink = openLink,
    this.onPointer,
    this.scrollbarShow = ScrollbarVisibility.auto,
    this.systemAutoHide = false,
    this.tooltip,
  });

  /// names [child] with [message] when the pointer rests on it; the editor
  /// gives its own tooltips, and a plain one is used without
  final Widget Function(String message, Widget child)? tooltip;

  /// when the scrollbar of the text is shown, which is the setting of the
  /// editor's scrollbars; with system, whether the system hides them is
  /// [systemAutoHide]
  final ScrollbarVisibility scrollbarShow;
  final bool systemAutoHide;

  final DiagnosticDetail detail;
  final DiagnosticColors colors;
  final EditorStyle style;

  /// the most that the text can be, which is scrolled when it is more
  final Size contentLimit;
  final Future<void> Function(String url) onOpenLink;

  /// told when the pointer moves over the popover
  final VoidCallback? onPointer;

  @override
  State<DiagnosticPopover> createState() => _DiagnosticPopoverState();
}

class _DiagnosticPopoverState extends State<DiagnosticPopover> {
  late final TapGestureRecognizer _link = TapGestureRecognizer()
    ..onTap = _openLink;
  final ScrollController _scroll = ScrollController();
  Timer? _copiedTimer;
  bool _copied = false;

  static const _copiedFor = Duration(seconds: 2);

  Widget _tooltip(String message, Widget child) =>
      widget.tooltip?.call(message, child) ??
      Tooltip(message: message, child: child);

  void _openLink() {
    final href = widget.detail.codeHref;
    if (href != null) {
      widget.onOpenLink(href);
    }
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.detail.message));
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(_copiedFor, () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    _link.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final level = widget.detail.level;
    final accent = diagnosticLevelColor(level, widget.colors);
    final radius = BorderRadius.circular(style.popoverRadius);
    final base = style.popoverText;
    final text = diagnosticText(
      widget.detail,
      base,
      base.copyWith(
        decoration: TextDecoration.underline,
        decorationColor: base.color,
      ),
      onLink: _link,
    );
    final limit = widget.contentLimit;
    final measure = TextPainter(text: text, textDirection: TextDirection.ltr)
      ..layout(maxWidth: limit.width);
    final width = measure.width.ceilToDouble();
    final height = math.min(measure.height, limit.height);
    measure.dispose();
    final tip = _copied ? 'Copied!' : 'Copy Diagnostic';
    return MouseRegion(
      opaque: true,
      cursor: SystemMouseCursors.basic,
      onHover: (_) => widget.onPointer?.call(),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: style.popoverSurface,
            borderRadius: radius,
            boxShadow: const [
              BoxShadow(
                offset: Offset(0, 2),
                blurRadius: 3,
                color: Color(0x1F000000),
              ),
              BoxShadow(offset: Offset(0, 1), color: Color(0x0F000000)),
            ],
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: accent.withAlpha(_backgroundAlpha(level)),
              border: Border.all(color: accent),
              borderRadius: radius,
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
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      style.popoverRem(8),
                      style.popoverRem(4),
                      style.popoverRem(32),
                      style.popoverRem(4),
                    ),
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: SingleChildScrollView(
                        controller: _scroll,
                        child: Text.rich(
                          text,
                          textDirection: TextDirection.ltr,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: style.popoverRem(4),
                    right: style.popoverRem(4),
                    child: _tooltip(
                      tip,
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _copy,
                          child: Padding(
                            padding: EdgeInsets.all(style.popoverRem(2)),
                            child: Icon(
                              _copied ? Icons.check : Icons.content_copy,
                              size: style.popoverRem(14),
                              color: _copied
                                  ? style.popoverSuccess
                                  : style.popoverMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
