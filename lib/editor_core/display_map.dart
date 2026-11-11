import 'buffer.dart';
import 'display/block_map.dart';
import 'display/fold_map.dart';
import 'display/inlay_map.dart';
import 'display/invisibles.dart';
import 'display/layer_edit.dart';
import 'display/line_wrapper.dart';
import 'display/tab_map.dart';
import 'display/wrap_map.dart';
import 'highlight.dart';
import 'point.dart';
import 'rope.dart';
import 'sum_tree.dart' show Bias;
import 'text_metrics.dart';

export 'display/block_map.dart'
    show
        BlockPlacement,
        BlockPlacementKind,
        BlockProperties,
        BlockStyle,
        CustomBlock;
export 'display/fold_map.dart' show Fold, FoldPlaceholder, foldEllipsis;
export 'display/inlay_map.dart' show Inlay;
export 'highlight.dart';
export 'display/line_wrapper.dart' show IndentAdjustment;
export 'display/wrap_map.dart' show RowEdit, WrapChunk;

/// how a text is laid out on the screen. it is made of layers, each of which
/// changes the text of the one below it:
///
/// - the inlay layer puts in text that is not in the buffer
/// - the fold layer shows a placeholder for what is folded away
/// - the tab layer makes each tab the spaces to the next stop
/// - the wrap layer breaks the lines that are too wide into rows
///
/// the map takes what was done to the buffer since it last looked, each layer
/// working out only what an edit touched, whenever the layout is asked for or
/// changed, and gives a [DisplaySnapshot] of the layout as it is.
class DisplayMap {
  DisplayMap(
    this.buffer, {
    int tabSize = 4,
    double? wrapWidth,
    TextMetrics metrics = const CellMetrics(),
    IndentAdjustment softWrapIndent = const IndentAdjustment.sameIndent(),
  }) : _tabSize = tabSize,
       _subscription = buffer.subscribe() {
    _inlays = InlayMap(buffer.snapshot);
    _folds = FoldMap(_inlays.snapshot);
    _tabs = TabMap(_folds.snapshot, tabSize);
    _wraps = WrapMap(
      _tabs.snapshot,
      metrics: metrics,
      wrapWidth: wrapWidth,
      softWrapIndent: softWrapIndent,
    )..addListener(_notify);
    _blocks = BlockMap(_wraps.snapshot);
  }

  final List<void Function()> _listeners = [];

  /// [listener] is told when the layout changed by itself, which it does
  /// when rows that were being wrapped in the background are done
  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  /// whether rows are still being wrapped, so that the layout is not the one
  /// it will be
  bool get isRewrapping => _wraps.isRewrapping;

  final TextBuffer buffer;

  /// the edits of the buffer that the layers have not been told of yet
  final Subscription _subscription;
  int _tabSize;
  late final InlayMap _inlays;
  late final FoldMap _folds;
  late final TabMap _tabs;
  late final WrapMap _wraps;
  late final BlockMap _blocks;

  /// what the wrap layer changed that the block layer has not been told of
  EditPatch _pendingWrapEdits = EditPatch();

  /// the layout as it is; it does not change, so it can be kept
  DisplaySnapshot get snapshot {
    _syncThroughWrap();
    final blocks = _blocks.read(_wraps.snapshot, _takeWrapEdits());
    return DisplaySnapshot._(blocks);
  }

  List<RowEdit> _takeWrapEdits() {
    final edits = _pendingWrapEdits.edits;
    _pendingWrapEdits = EditPatch();
    return edits;
  }

  /// the blocks of the map, made to follow the layout first
  BlockMapWriter _blockWriter() {
    _syncThroughWrap();
    return _blocks.write(_wraps.snapshot, _takeWrapEdits());
  }

  /// puts in blocks, and gives their ids
  List<int> insertBlocks(Iterable<BlockProperties> blocks) =>
      _blockWriter().insert(blocks);

  /// gives blocks the heights they are mapped to
  void resizeBlocks(Map<int, int> heights) => _blockWriter().resize(heights);

  /// takes out the blocks with [ids]
  void removeBlocks(Set<int> ids) => _blockWriter().remove(ids);

  /// takes out the blocks that replace rows that [ranges] of the buffer touch
  void removeIntersectingReplaceBlocks(
    Iterable<(int start, int end)> ranges, {
    bool inclusive = false,
  }) => _blockWriter().removeIntersectingReplaceBlocks(
    ranges,
    inclusive: inclusive,
  );

  /// the blocks, in the order of where they are
  List<CustomBlock> get blocks => _blocks.blocks;

  int get tabSize => _tabSize;
  double? get wrapWidth => _wraps.wrapWidth;

  /// the inlays, in the order they are shown
  List<Inlay> get inlays => _inlays.inlays;

  /// the folds, in the order of where they start
  List<Fold> get folds => _folds.snapshot.folds;

  void dispose() {
    buffer.unsubscribe(_subscription);
    _wraps.dispose();
    _listeners.clear();
  }

  (InlaySnapshot, List<LayerEdit>) _syncThroughInlay() =>
      _inlays.sync(buffer.snapshot, _subscription.consume().edits);

  void _syncThroughWrap() {
    final (inlaySnapshot, inlayEdits) = _syncThroughInlay();
    _afterFolds(_folds.read(inlaySnapshot, inlayEdits));
  }

  void _afterFolds((FoldSnapshot, List<LayerEdit>) folded) {
    final (tabSnapshot, tabEdits) = _tabs.sync(folded.$1, folded.$2, _tabSize);
    final (_, wrapEdits) = _wraps.sync(tabSnapshot, tabEdits);
    _pendingWrapEdits = _pendingWrapEdits.compose(wrapEdits);
  }

  /// folds [ranges] of the buffer, each with what is shown in its place, or
  /// null for the ellipsis
  void fold(
    Iterable<(int start, int end, FoldPlaceholder? placeholder)> ranges,
  ) {
    _syncThroughWrap();
    _afterFolds(_folds.fold(ranges));
  }

  /// takes out the folds that have any of [ranges] of the buffer; with
  /// [inclusive], also the ones that only touch them
  void unfold(Iterable<(int start, int end)> ranges, {bool inclusive = false}) {
    _syncThroughWrap();
    _afterFolds(_folds.unfoldIntersecting(ranges, inclusive: inclusive));
  }

  /// takes out the folds that have any of [ranges] of the buffer and were
  /// made with a placeholder that has [typeTag]
  void removeFolds(Iterable<(int start, int end)> ranges, Object typeTag) {
    _syncThroughWrap();
    _afterFolds(_folds.removeFolds(ranges, typeTag));
  }

  /// takes out the inlays with the ids of [toRemove], and puts in [toInsert]
  void spliceInlays(Iterable<int> toRemove, Iterable<Inlay> toInsert) {
    _syncThroughWrap();
    final (inlaySnapshot, inlayEdits) = _inlays.splice(toRemove, toInsert);
    _afterFolds(_folds.read(inlaySnapshot, inlayEdits));
  }

  void setTabSize(int tabSize) {
    if (tabSize == _tabSize) {
      return;
    }
    _syncThroughWrap();
    _tabSize = tabSize;
    _afterFolds((_folds.snapshot, const []));
  }

  /// sets the width that lines wrap to, or null for lines that do not wrap
  void setWrapWidth(double? wrapWidth) {
    _syncThroughWrap();
    _wraps.setWrapWidth(wrapWidth);
  }

  /// sets how wide characters are, as when the font changes
  void setMetrics(TextMetrics metrics) {
    _syncThroughWrap();
    _wraps.setMetrics(metrics);
  }

  void setSoftWrapIndent(IndentAdjustment indent) {
    _syncThroughWrap();
    _wraps.setSoftWrapIndent(indent);
  }
}

/// a piece of a row to be drawn in one look
class HighlightedChunk {
  const HighlightedChunk(
    this.text, {
    this.style,
    this.isTab = false,
    this.isInlay = false,
    this.replacement,
  });

  final String text;
  final HighlightStyle? style;

  /// whether the text is the spaces of a tab
  final bool isTab;

  /// whether the text is of an inlay, not of the buffer
  final bool isInlay;

  /// what to draw instead of [text], which looks like nothing; null when it
  /// is drawn as it is
  final String? replacement;
}

/// the layout of a text at one time: which rows there are, what is on them,
/// and how a place in the buffer and a place on the screen go to each other.
/// a display point is a row of the screen, and a column that counts the code
/// units of what is shown on the row.
class DisplaySnapshot {
  DisplaySnapshot._(this.blockSnapshot);

  final BlockSnapshot blockSnapshot;
  WrapSnapshot get wrapSnapshot => blockSnapshot.wrapSnapshot;

  TabSnapshot get tabSnapshot => wrapSnapshot.tabSnapshot;
  FoldSnapshot get foldSnapshot => tabSnapshot.foldSnapshot;
  InlaySnapshot get inlaySnapshot => foldSnapshot.inlaySnapshot;
  BufferSnapshot get bufferSnapshot => inlaySnapshot.bufferSnapshot;
  Rope get buffer => inlaySnapshot.buffer;

  /// the place of the end of what is shown
  Point get maxPoint => blockSnapshot.maxPoint;

  /// the rows of the screen
  int get rowCount => blockSnapshot.rowCount;

  int get longestRow => blockSnapshot.longestRow;

  /// how long row [row] is, in the code units of what is shown on it
  int lineLen(int row) => blockSnapshot.lineLen(row);

  /// what is shown on row [row]
  String rowText(int row) => blockSnapshot.rowText(row);

  /// the pieces of what is shown on row [row], each with the layer it is of;
  /// a row of a block has none
  Iterable<WrapChunk> rowChunks(
    int row, [
    Highlights highlights = Highlights.none,
  ]) => blockSnapshot.rowChunks(row, highlights);

  /// what is shown on row [row] as it is to be drawn: in pieces of one look,
  /// with the characters that look like nothing cut out to be drawn as
  /// something else
  Iterable<HighlightedChunk> highlightedRowChunks(
    int row, [
    Highlights highlights = Highlights.none,
  ]) sync* {
    for (final chunk in rowChunks(row, highlights)) {
      final text = chunk.text;
      var runStart = 0;
      var i = 0;
      while (i < text.length) {
        var rune = text.codeUnitAt(i);
        var length = 1;
        if (rune >= 0xD800 &&
            rune <= 0xDBFF &&
            i + 1 < text.length &&
            text.codeUnitAt(i + 1) >= 0xDC00 &&
            text.codeUnitAt(i + 1) <= 0xDFFF) {
          rune =
              0x10000 +
              ((rune - 0xD800) << 10) +
              (text.codeUnitAt(i + 1) - 0xDC00);
          length = 2;
        }
        if (!chunk.isWrap && isInvisible(rune)) {
          if (i > runStart) {
            yield HighlightedChunk(
              text.substring(runStart, i),
              style: chunk.style,
              isTab: chunk.tab?.isTab ?? false,
              isInlay: chunk.tab?.inlay != null,
            );
          }
          yield HighlightedChunk(
            text.substring(i, i + length),
            style: chunk.style,
            isInlay: chunk.tab?.inlay != null,
            replacement: replacement(rune) == null
                ? null
                : String.fromCharCode(replacement(rune)!),
          );
          runStart = i + length;
        }
        i += length;
      }
      if (text.length > runStart) {
        yield HighlightedChunk(
          text.substring(runStart),
          style: chunk.style,
          isTab: chunk.tab?.isTab ?? false,
          isInlay: chunk.tab?.inlay != null,
        );
      }
    }
  }

  /// all that is shown
  String get text => blockSnapshot.text;

  /// whether row [row] is a block
  bool isBlockLine(int row) => blockSnapshot.isBlockLine(row);

  /// whether line [bufferRow] of the buffer is in rows that a block replaces
  bool isLineReplaced(int bufferRow) => blockSnapshot.isLineReplaced(bufferRow);

  /// the blocks that start in rows [startRow] to [endRow]
  List<(int, CustomBlock)> blocksInRange(int startRow, int endRow) =>
      blockSnapshot.blocksInRange(startRow, endRow);

  /// the row of the buffer that row [row] shows part of, null for a block,
  /// and whether the row continues a line that wrapped
  ({int? bufferRow, bool softWrapped}) rowInfo(int row) =>
      blockSnapshot.rowInfo(row);

  /// the indent that row [row] has when it continues a line that wrapped
  int? softWrapIndent(int row) {
    if (row <= 0 || blockSnapshot.isBlockLine(row)) {
      return null;
    }
    final wrapRow = blockSnapshot.toWrapPoint(Point(row, 0), Bias.left).row;
    return wrapSnapshot.softWrapIndent(wrapRow - 1);
  }

  /// where the point [point] of the buffer is shown. in a fold, or where a
  /// row wraps, [bias] says which side it goes to.
  Point pointToDisplayPoint(Point point, [Bias bias = Bias.left]) =>
      blockSnapshot.toBlockPoint(wrapSnapshot.makeWrapPoint(point, bias));

  /// the point of the buffer that is shown at the display point [point]
  Point displayPointToPoint(Point point, [Bias bias = Bias.left]) =>
      wrapSnapshot.toPoint(blockSnapshot.toWrapPoint(point, bias), bias);

  /// where the offset [offset] of the buffer is shown
  Point offsetToDisplayPoint(int offset, [Bias bias = Bias.left]) =>
      pointToDisplayPoint(buffer.offsetToPoint(offset), bias);

  /// the offset of the buffer that is shown at the display point [point]
  int displayPointToOffset(Point point, [Bias bias = Bias.left]) =>
      buffer.pointToOffset(displayPointToPoint(point, bias));

  /// [point] moved to a place a cursor can be at
  Point clipPoint(Point point, [Bias bias = Bias.left]) =>
      blockSnapshot.clipPoint(point, bias);

  /// whether the buffer offset [offset] is inside a fold
  bool intersectsFold(int offset) => foldSnapshot.intersectsFold(offset);

  /// whether row [bufferRow] of the buffer has a fold on it
  bool isLineFolded(int bufferRow) => foldSnapshot.isLineFolded(bufferRow);
}
