import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ui/editor/text_encoding.dart';

void main() {
  test('every encoding is detected from its own bytes and round trips', () {
    const text = 'print("héllo")';
    for (final encoding in TextEncoding.values) {
      final bytes = encoding.encode(text);
      final detected = TextEncoding.detect(bytes);
      // latin-1 has no mark, and its é is not valid utf-8
      expect(detected, encoding, reason: encoding.label);
      expect(detected.decode(bytes), text, reason: encoding.label);
    }
  });

  test('plain ascii is utf-8', () {
    expect(
      TextEncoding.detect(Uint8List.fromList('print(1)'.codeUnits)),
      TextEncoding.utf8,
    );
  });

  test('latin-1 text with characters it cannot hold is saved as utf-8', () {
    expect(TextEncoding.latin1.fit('日本'), TextEncoding.utf8);
  });
}
