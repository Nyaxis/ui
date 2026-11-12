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

/// where a popover of [size] goes for the place [target] in an [area]: directly
/// above the row when it fits there, and otherwise directly below it. it is
/// moved to the left, as far as it takes, to keep clear of the right edge. when
/// it fits in neither place it is below, kept inside the area
Offset placePopover(Rect target, Size size, Size area) {
  final shift = math.min(
    0.0,
    area.width - popoverRightMargin - (target.left + size.width),
  );
  final x = target.left + shift;
  final bounds = Offset.zero & area;
  bool fits(Offset origin) {
    final box = origin & size;
    return box.left >= bounds.left &&
        box.top >= bounds.top &&
        box.right <= bounds.right &&
        box.bottom <= bounds.bottom;
  }

  final above = Offset(x, target.top - size.height);
  if (fits(above)) {
    return above;
  }
  final below = Offset(x, target.bottom);
  if (fits(below)) {
    return below;
  }
  return Offset(
    below.dx.clamp(0.0, math.max(0.0, area.width - size.width)),
    below.dy.clamp(0.0, math.max(0.0, area.height - size.height)),
  );
}

class _PopoverPlacement extends SingleChildLayoutDelegate {
  const _PopoverPlacement(this.target);

  final Rect target;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      placePopover(target, childSize, size);

  @override
  bool shouldRelayout(_PopoverPlacement oldDelegate) =>
      oldDelegate.target != target;
}

/// a popover for the place [target] of an editor, which fills the space that
/// the editor is in. the pointer is only on it where the popover itself is
class PopoverLayer extends StatelessWidget {
  const PopoverLayer({super.key, required this.target, required this.child});

  final Rect target;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomSingleChildLayout(
    delegate: _PopoverPlacement(target),
    child: child,
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
  });

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
                    padding: const EdgeInsets.fromLTRB(8, 4, 32, 4),
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
                    top: 4,
                    right: 4,
                    child: Tooltip(
                      message: tip,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _copy,
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              _copied ? Icons.check : Icons.content_copy,
                              size: 14,
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
