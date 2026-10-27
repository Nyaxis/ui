import 'dart:ffi';
import 'dart:io';
import 'dart:math';

/// the runner owns the acrylic backdrop and the drop shadow; this only
/// switches them on and off
class WindowEffects {
  WindowEffects._();

  // exported by the runner executable itself (host_backdrop_window.cpp)
  static final void Function(int, double) _configure =
      DynamicLibrary.executable().lookupFunction<
        Void Function(Int32, Double),
        void Function(int, double)
      >('NyaxisBlurConfigure');

  // exported by the runner executable itself (shadow_window.cpp)
  static final void Function(double) _configureShadow =
      DynamicLibrary.executable()
          .lookupFunction<Void Function(Double), void Function(double)>(
            'NyaxisShadowConfigure',
          );

  /// [cornerRadius] is in logical pixels; the runner scales it per monitor.
  /// the runner draws round corners only, so it gets the radius of the circle
  /// that meets the window's corner, of [roundingPower], in the middle of it,
  /// which stays inside the window's shape, so that neither the backdrop nor
  /// the shadow show in the corners the window has cut away
  static void apply({
    required bool acrylic,
    required double cornerRadius,
    required double roundingPower,
  }) {
    if (!Platform.isWindows) {
      return;
    }
    final power = roundingPower.clamp(1.0, 10.0);
    final radius = cornerRadius * (1 - pow(2, -1 / power)) / (1 - sqrt1_2);
    _configureShadow(radius);
    _configure(acrylic ? 1 : 0, radius);
  }
}
