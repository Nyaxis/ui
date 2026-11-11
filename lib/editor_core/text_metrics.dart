/// how wide characters are, in whatever unit the layout is given its width in.
/// the editor gives the width of the glyphs of its font in pixels, and a
/// text that is only laid out, as in a test, gives cells.
abstract class TextMetrics {
  /// how wide the character [rune] is
  double advance(int rune);
}

/// cells of a terminal: one for most characters, two for the wide ones that
/// East Asian text and emoji are made of, and none for the marks that go on the
/// character before them
class CellMetrics implements TextMetrics {
  const CellMetrics();

  @override
  double advance(int rune) {
    if (_isMark(rune)) {
      return 0;
    }
    return _isWide(rune) ? 2 : 1;
  }

  static bool _isMark(int r) =>
      (r >= 0x0300 && r <= 0x036F) ||
      (r >= 0x200B && r <= 0x200F) ||
      (r >= 0xFE00 && r <= 0xFE0F);

  static bool _isWide(int r) =>
      (r >= 0x1100 && r <= 0x115F) ||
      (r >= 0x2E80 && r <= 0xA4CF) ||
      (r >= 0xAC00 && r <= 0xD7A3) ||
      (r >= 0xF900 && r <= 0xFAFF) ||
      (r >= 0xFE30 && r <= 0xFE6F) ||
      (r >= 0xFF00 && r <= 0xFF60) ||
      (r >= 0xFFE0 && r <= 0xFFE6) ||
      (r >= 0x1F300 && r <= 0x1F64F) ||
      (r >= 0x1F900 && r <= 0x1F9FF) ||
      (r >= 0x20000 && r <= 0x3FFFD);
}
