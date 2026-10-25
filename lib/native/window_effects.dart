import 'dart:ffi';
import 'dart:io';

import '../theme/app_theme.dart';

/// Window effects behind the Flutter surface.
///
/// The OS acrylic layers (WCA accent, DWM system backdrop, blur-behind) all
/// ignore window shape, so the frost is instead drawn by the runner's own
/// `BlurWindow`: it captures the desktop, runs a dual Kawase blur on the GPU
/// and presents the result clipped to a rounded rectangle at the theme
/// radius. Flutter stays per-pixel transparent on top (sheet of glass, set up
/// by the runner), painting only the tint.
///
/// The runner also owns the window region that crops the Flutter window to
/// the same curve, rebuilding it on size and DPI changes.
class WindowEffects {
  WindowEffects._();

  // Exported by the runner executable itself (blur_window.cpp).
  static final void Function(
    int,
    double,
    double,
    int,
    double,
    double,
    double,
    double,
    double,
  )
  _blurConfigure = DynamicLibrary.executable()
      .lookupFunction<
        Void Function(
          Int32,
          Double,
          Double,
          Int32,
          Double,
          Double,
          Double,
          Double,
          Double,
        ),
        void Function(
          int,
          double,
          double,
          int,
          double,
          double,
          double,
          double,
          double,
        )
      >('NyaxisBlurConfigure');

  /// Applies the effect; safe to call repeatedly with the same inputs.
  /// [cornerRadius] is in logical pixels, the runner scales it per monitor.
  static void apply({
    required bool acrylic,
    required double cornerRadius,
    required BlurSettings blur,
  }) {
    if (!Platform.isWindows) {
      return;
    }
    _blurConfigure(
      acrylic ? 1 : 0,
      cornerRadius,
      blur.size,
      blur.passes,
      blur.strength,
      blur.noise,
      blur.contrast,
      blur.brightness,
      blur.vibrancy,
    );
  }
}
