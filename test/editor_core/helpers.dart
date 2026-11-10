import 'package:ui/editor_core/buffer.dart';
import 'package:ui/editor_core/display/inlay_map.dart';
import 'package:ui/editor_core/patch.dart';

/// an inlay at [offset] of [buffer] as it is now
Inlay inlayAt(
  TextBuffer buffer,
  int id,
  int offset,
  String text, [
  Bias bias = Bias.left,
]) => Inlay(id: id, position: buffer.anchorAt(offset, bias), text: text);

/// the inlays of [inlays] that are shown, which are the ones whose text was
/// not taken out, each with where it is in [buffer]
List<(Inlay, int)> shownInlays(BufferSnapshot buffer, List<Inlay> inlays) => [
  for (final inlay in inlays)
    if (buffer.isValid(inlay.position))
      (inlay, buffer.offsetForAnchor(inlay.position)),
];
