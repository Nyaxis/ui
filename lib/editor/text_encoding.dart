import 'dart:convert';
import 'dart:typed_data';

/// how a script's bytes are read and written, found when it is opened so that
/// saving does not change it
enum TextEncoding {
  utf8('UTF-8'),
  utf8Bom('UTF-8 with BOM'),
  utf16le('UTF-16 LE'),
  utf16be('UTF-16 BE'),
  latin1('ISO 8859-1');

  const TextEncoding(this.label);

  final String label;

  /// a byte order mark decides, otherwise bytes that are not valid utf-8 are
  /// taken as latin-1, which accepts every byte
  static TextEncoding detect(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8Bom;
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return utf16le;
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return utf16be;
    }
    try {
      utf8Codec.decode(bytes);
      return utf8;
    } on FormatException {
      return latin1;
    }
  }

  static const utf8Codec = Utf8Codec();

  String decode(Uint8List bytes) {
    switch (this) {
      case utf8:
        return utf8Codec.decode(bytes);
      case utf8Bom:
        return utf8Codec.decode(bytes.sublist(3));
      case utf16le:
      case utf16be:
        final data = ByteData.sublistView(bytes, 2);
        final endian = this == utf16le ? Endian.little : Endian.big;
        return String.fromCharCodes([
          for (var i = 0; i + 1 < data.lengthInBytes; i += 2)
            data.getUint16(i, endian),
        ]);
      case latin1:
        return const Latin1Codec().decode(bytes);
    }
  }

  /// latin-1 cannot hold everything that can be typed, so text it cannot
  /// hold is saved as utf-8 instead
  TextEncoding fit(String text) {
    if (this == latin1 && text.codeUnits.any((unit) => unit > 0xFF)) {
      return utf8;
    }
    return this;
  }

  Uint8List encode(String text) {
    switch (this) {
      case utf8:
        return utf8Codec.encode(text);
      case utf8Bom:
        return Uint8List.fromList([
          0xEF,
          0xBB,
          0xBF,
          ...utf8Codec.encode(text),
        ]);
      case utf16le:
      case utf16be:
        final data = ByteData(2 + text.codeUnits.length * 2);
        final endian = this == utf16le ? Endian.little : Endian.big;
        data.setUint16(0, 0xFEFF, endian);
        for (var i = 0; i < text.codeUnits.length; i++) {
          data.setUint16(2 + i * 2, text.codeUnits[i], endian);
        }
        return data.buffer.asUint8List();
      case latin1:
        return const Latin1Codec().encode(text);
    }
  }
}
