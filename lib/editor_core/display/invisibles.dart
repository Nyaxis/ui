// characters that look like nothing, or like a space, are shown as something
// that can be seen: the control characters as their symbols, and the rest
// as a space of a fixed width. the ones that are used to build other
// characters are kept in the text, and only marked.
//
// the ones that are looked for are the control characters, the whitespace
// that is not a plain space, the characters of the "format" kind such as
// byte order marks and direction overrides, and a few blank letters.

/// whether [c] looks like nothing, or like a space
bool isInvisible(int c) {
  if (c <= 0x1F) {
    return c != 0x09 && c != 0x0A && c != 0x0D;
  }
  if (c >= 0x7F) {
    return c <= 0x9F ||
        (_isWhitespace(c) && c != _ideographicSpace) ||
        _isFormatOrOtherInvisible(c);
  }
  return false;
}

/// what to show for [c], or null when it is to stay as it is
int? replacement(int c) {
  if (c <= 0x1F) {
    return 0x2400 + c;
  }
  if (c == 0x7F) {
    return 0x2421;
  }
  return _shouldPreserve(c) ? null : _fixedWidthSpace;
}

const int _fixedWidthSpace = 0x2007;
const int _ideographicSpace = 0x3000;

bool _isWhitespace(int c) =>
    (c >= 0x85 && c <= 0x85) ||
    c == 0xA0 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202F ||
    c == 0x205F ||
    c == _ideographicSpace;

bool _isFormatOrOtherInvisible(int c) =>
    c == 0xAD ||
    (c >= 0x600 && c <= 0x605) ||
    c == 0x61C ||
    c == 0x6DD ||
    c == 0x70F ||
    (c >= 0x890 && c <= 0x891) ||
    c == 0x8E2 ||
    c == 0x180E ||
    (c >= 0x200B && c <= 0x200F) ||
    (c >= 0x202A && c <= 0x202E) ||
    (c >= 0x2060 && c <= 0x2064) ||
    (c >= 0x2066 && c <= 0x206F) ||
    c == 0xFEFF ||
    (c >= 0xFFF9 && c <= 0xFFFB) ||
    c == 0x110BD ||
    c == 0x110CD ||
    (c >= 0x13430 && c <= 0x1343F) ||
    (c >= 0x1BCA0 && c <= 0x1BCA3) ||
    (c >= 0x1D173 && c <= 0x1D17A) ||
    c == 0xE0001 ||
    (c >= 0xE0020 && c <= 0xE007F) ||
    c == 0x034F ||
    (c >= 0x115F && c <= 0x1160) ||
    (c >= 0x17B4 && c <= 0x17B5) ||
    (c >= 0x180B && c <= 0x180D) ||
    c == 0x2800 ||
    c == 0x3164 ||
    (c >= 0xFE00 && c <= 0xFE0D) ||
    c == 0xFFA0 ||
    c == 0xFFFC ||
    (c >= 0xE0100 && c <= 0xE01EF);

bool _shouldPreserve(int c) =>
    c == 0x034F ||
    c == 0x200D ||
    (c >= 0x17B4 && c <= 0x17B5) ||
    (c >= 0x180B && c <= 0x180D) ||
    (c >= 0xE0061 && c <= 0xE007A) ||
    c == 0xE007F;
