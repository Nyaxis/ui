import 'dart:ffi';
import 'dart:io';

/// the runner owns the acrylic backdrop and the window region that crops the
/// flutter window to the same rounded shape; this only switches it on and off
class WindowEffects {
  WindowEffects._();

  // exported by the runner executable itself (host_backdrop_window.cpp)
  static final void Function(int, double) _configure = DynamicLibrary.executable()
      .lookupFunction<Void Function(Int32, Double), void Function(int, double)>(
        'NyaxisBlurConfigure',
      );

  /// [cornerRadius] is in logical pixels; the runner scales it per monitor
  static void apply({required bool acrylic, required double cornerRadius}) {
    if (!Platform.isWindows) {
      return;
    }
    _configure(acrylic ? 1 : 0, cornerRadius);
  }
}
