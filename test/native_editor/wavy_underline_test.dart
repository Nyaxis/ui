import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/editor_core/buffer.dart';
import 'package:ui/editor_core/patch.dart' show Bias;
import 'package:ui/native_editor/editor_controller.dart';
import 'package:ui/native_editor/editor_style.dart';
import 'package:ui/native_editor/editor_view.dart';
import 'package:ui/native_editor/wavy_underline.dart';
import 'package:ui/ui/device_pixels.dart';

/// the alpha of each pixel of what [draw] paints on a canvas of [width] by
/// [height] device pixels, row by row, with the canvas in logical pixels of
/// [ratio] device pixels
Future<List<int>> _alphas(
  int width,
  int height,
  double ratio,
  void Function(Canvas canvas) draw,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(ratio);
  draw(canvas);
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  image.dispose();
  final bytes = data!.buffer.asUint8List();
  return [for (var i = 3; i < bytes.length; i += 4) bytes[i]];
}

void main() {
  group('the places of pixels', () {
    test('are rounded to the nearest, and the middle goes toward zero', () {
      expect(roundHalfTowardZero(0.5), 0);
      expect(roundHalfTowardZero(1.5), 1);
      expect(roundHalfTowardZero(2.5), 2);
      expect(roundHalfTowardZero(-0.5), 0);
      expect(roundHalfTowardZero(-1.5), -1);
      expect(roundHalfTowardZero(1.5001), 2);
      expect(roundHalfTowardZero(1.4999), 1);
      expect(roundHalfTowardZero(-1.5001), -2);
      expect(roundHalfTowardZero(3), 3);
      expect(roundHalfTowardZero(-3), -3);
    });

    test('are those of the screen: a logical place times the ratio', () {
      expect(roundToDevicePixel(1, 1.5), 1);
      expect(roundToDevicePixel(0.3, 2), 1);
      expect(roundToDevicePixel(3.4, 1), 3);
      expect(roundToDevicePixel(4.1, 1.25), 5);
    });

    test('a stroke is a whole number of pixels, and not less than one', () {
      expect(snapStroke(1, 1), 1);
      expect(snapStroke(1, 1.25), 1);
      expect(snapStroke(1, 1.5), 1);
      expect(snapStroke(1, 2), 2);
      expect(snapStroke(1, 2.5), 2);
      expect(snapStroke(0.2, 1), 1);
      expect(snapStroke(0, 2), 0);
    });
  });

  group('how much of each pixel the wave covers', () {
    test('is all of a pixel in the middle of the stroke, and none far off', () {
      final coverage = wavyUnderlineCoverage(36, 1);
      expect(coverage, hasLength(36 * 3));
      // the middle row, where the wave crosses its middle line
      expect(coverage[1 * 36 + 4], closeTo(1, 1e-9));
      // little in the top row at that place, and in the bottom: the wave is
      // slanted there, and the distance is across it
      expect(coverage[0 * 36 + 4], lessThan(0.2));
      expect(coverage[2 * 36 + 4], lessThan(0.2));
      // and none at all where the wave is far from them
      expect(coverage[0 * 36 + 0], 0);
      expect(coverage.every((c) => c >= 0 && c <= 1), isTrue);
    });

    test('repeats every nine strokes', () {
      for (final thickness in [1, 2, 3]) {
        final period = 9 * thickness;
        final width = period * 3;
        final coverage = wavyUnderlineCoverage(width, thickness);
        for (var y = 0; y < 3 * thickness; y++) {
          for (var x = 0; x + period < width; x++) {
            expect(
              coverage[y * width + x],
              closeTo(coverage[y * width + x + period], 1e-9),
              reason: 'thickness $thickness at $x, $y',
            );
          }
        }
      }
    });

    test('has as much on the pixels as the length of the stroke has area', () {
      // 36 pixels of a stroke of one, a little more than that as it is a wave
      final total = wavyUnderlineCoverage(36, 1).fold(0.0, (a, b) => a + b);
      expect(total, closeTo(38.91, 0.05));
    });

    test('goes down first from the middle, and then up', () {
      final coverage = wavyUnderlineCoverage(36, 1);
      double row(int y, int x) => coverage[y * 36 + x];
      // a quarter into the period it is at its lowest: the bottom row has more
      // of it than the top
      expect(row(2, 2), greaterThan(row(0, 2)));
      // and three quarters in it is at its highest
      expect(row(0, 6), greaterThan(row(2, 6)));
    });
  });

  group('the painted wave', () {
    test('is the coverage, pixel for pixel, at a ratio of one', () async {
      final alphas = await _alphas(
        40,
        5,
        1,
        (canvas) => paintWavyUnderline(
          canvas,
          const Offset(2, 1),
          36,
          const Color(0xFF000000),
        ),
      );
      final coverage = wavyUnderlineCoverage(36, 1);
      for (var y = 0; y < 3; y++) {
        for (var x = 0; x < 36; x++) {
          expect(
            alphas[(y + 1) * 40 + x + 2],
            closeTo((coverage[y * 36 + x] * 255).round(), 1),
            reason: 'at $x, $y',
          );
        }
      }
      // and nothing else
      var elsewhere = 0;
      for (var y = 0; y < 5; y++) {
        for (var x = 0; x < 40; x++) {
          final inside = y >= 1 && y < 4 && x >= 2 && x < 38;
          if (!inside && alphas[y * 40 + x] != 0) {
            elsewhere++;
          }
        }
      }
      expect(elsewhere, 0);
    });

    test(
      'has a thickness and a width of whole pixels on a larger screen',
      () async {
        // 1 logical pixel is 2 device pixels at a ratio of 2, a width of 18
        // logical is 36
        final alphas = await _alphas(
          80,
          10,
          2,
          (canvas) => paintWavyUnderline(
            canvas,
            const Offset(2, 1),
            18,
            const Color(0xFF000000),
            ratio: 2,
          ),
        );
        final coverage = wavyUnderlineCoverage(36, 2);
        for (var y = 0; y < 6; y++) {
          for (var x = 0; x < 36; x++) {
            expect(
              alphas[(y + 2) * 80 + x + 4],
              closeTo((coverage[y * 36 + x] * 255).round(), 1),
              reason: 'at $x, $y',
            );
          }
        }
      },
    );

    test(
      'is a pixel thick at a ratio of 1.25, where 1 would be 1.25',
      () async {
        final alphas = await _alphas(
          60,
          8,
          1.25,
          (canvas) => paintWavyUnderline(
            canvas,
            const Offset(0, 0),
            20,
            const Color(0xFF000000),
            ratio: 1.25,
          ),
        );
        // 20 logical pixels are 25 device pixels, the thickness is 1
        final coverage = wavyUnderlineCoverage(25, 1);
        for (var y = 0; y < 3; y++) {
          for (var x = 0; x < 25; x++) {
            expect(
              alphas[y * 60 + x],
              closeTo((coverage[y * 25 + x] * 255).round(), 1),
              reason: 'at $x, $y',
            );
          }
        }
        // and not past its 25 pixels
        for (var y = 0; y < 8; y++) {
          for (var x = 25; x < 60; x++) {
            expect(alphas[y * 60 + x], 0, reason: 'at $x, $y');
          }
        }
      },
    );

    test('starts on a pixel, where the place of it is not on one', () async {
      final alphas = await _alphas(
        50,
        4,
        1,
        (canvas) => paintWavyUnderline(
          canvas,
          const Offset(3.4, 0.2),
          30,
          const Color(0xFF000000),
        ),
      );
      int firstColumn() {
        for (var x = 0; x < 50; x++) {
          for (var y = 0; y < 4; y++) {
            if (alphas[y * 50 + x] != 0) {
              return x;
            }
          }
        }
        return -1;
      }

      int firstRow() {
        for (var y = 0; y < 4; y++) {
          for (var x = 0; x < 50; x++) {
            if (alphas[y * 50 + x] != 0) {
              return y;
            }
          }
        }
        return -1;
      }

      // 3.4 is on pixel 3, and 0.2 is on the first row
      expect(firstColumn(), 3);
      expect(firstRow(), 0);
    });

    test('goes by where the canvas is on the window, for its pixels', () async {
      // the canvas is half a pixel in, and the wave 3.2 into it: it is at 3.7
      // on the window, which is the pixel 4, so 3.5 into the canvas
      final alphas = await _alphas(50, 4, 1, (canvas) {
        canvas.translate(0.5, 0);
        paintWavyUnderline(
          canvas,
          const Offset(3.2, 0),
          30,
          const Color(0xFF000000),
          globalOrigin: const Offset(0.5, 0),
        );
      });
      int first() {
        for (var x = 0; x < 50; x++) {
          for (var y = 0; y < 4; y++) {
            if (alphas[y * 50 + x] != 0) {
              return x;
            }
          }
        }
        return -1;
      }

      expect(first(), 4);
    });

    test(
      'has the color of the underline, and its opacity in what it covers',
      () async {
        const color = Color(0x80FF0000);
        final shown = ui.PictureRecorder();
        paintWavyUnderline(Canvas(shown), Offset.zero, 18, color);
        final image = await shown.endRecording().toImage(20, 3);
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        image.dispose();
        final bytes = data!.buffer.asUint8List();
        final coverage = wavyUnderlineCoverage(18, 1);
        var checked = 0;
        for (var y = 0; y < 3; y++) {
          for (var x = 0; x < 18; x++) {
            final c = coverage[y * 18 + x];
            if (c < 0.999) {
              continue;
            }
            final i = (y * 20 + x) * 4;
            // a pixel that is all covered has the color, at the opacity it has
            expect(bytes[i], 255);
            expect(bytes[i + 1], 0);
            expect(bytes[i + 2], 0);
            expect(bytes[i + 3], closeTo(0x80, 1));
            checked++;
          }
        }
        expect(checked, greaterThan(0));
      },
    );

    test('is not painted for a width that is none', () async {
      final alphas = await _alphas(
        20,
        4,
        1,
        (canvas) =>
            paintWavyUnderline(canvas, Offset.zero, 0, const Color(0xFF000000)),
      );
      expect(alphas.every((a) => a == 0), isTrue);
    });
  });

  testWidgets('an editor with diagnostics paints their waves', (tester) async {
    final controller = EditorController(text: 'local x = nope\nlocal y = 1\n');
    AnchorRange range(int start, int end) => AnchorRange(
      controller.buffer.anchorAt(start, Bias.right),
      controller.buffer.anchorAt(end, Bias.left),
    );
    final boundary = GlobalKey();
    Future<ByteData> shown() async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: boundary,
              child: SizedBox(
                width: 400,
                height: 200,
                child: EditorView(
                  controller: controller,
                  style: const EditorStyle(
                    textStyle: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  softWrap: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return (await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage();
        final data = await image.toByteData();
        image.dispose();
        return data!;
      }))!;
    }

    final before = await shown();
    controller.setDiagnostics(
      DiagnosticRanges(errors: [range(10, 14)], warnings: [range(21, 22)]),
    );
    final after = await shown();
    expect(tester.takeException(), isNull);
    var changed = 0;
    for (var i = 0; i < before.lengthInBytes; i++) {
      if (before.getUint8(i) != after.getUint8(i)) {
        changed++;
      }
    }
    // the waves are drawn: pixels are not what they were without them
    expect(changed, greaterThan(20));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
