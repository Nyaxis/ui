#ifndef RUNNER_HOST_BACKDROP_WINDOW_H_
#define RUNNER_HOST_BACKDROP_WINDOW_H_

#include <windows.h>

#include <memory>

// A click-through window parked directly beneath the Flutter window whose
// content is a Windows.UI.Composition host-backdrop brush, clipped to a
// rounded rectangle at the theme radius. DWM samples and composes the
// backdrop itself, so there is no capture: it stays in step with the window,
// and screenshots and recordings see it like any other window.
class HostBackdropWindow {
 public:
  HostBackdropWindow();
  ~HostBackdropWindow();

  HostBackdropWindow(const HostBackdropWindow&) = delete;
  HostBackdropWindow& operator=(const HostBackdropWindow&) = delete;

  // Creates the window and visual tree for |target|, the Flutter window.
  bool Create(HWND target);

  // Re-aligns position, size, visibility and z-order with the target and
  // rebuilds the target's window region when size or DPI changed.
  void Sync();

  // |radius| is the theme corner radius in logical pixels; it is scaled by
  // the target's current DPI.
  void Configure(bool enabled, float radius);

  // The instance reachable from the exported FFI entry points.
  static void SetActive(HostBackdropWindow* window);

 private:
  struct Impl;

  void UpdateTargetRegion(UINT width, UINT height);
  float ScaledRadius() const;
  void UpdateVisuals(UINT width, UINT height);

  std::unique_ptr<Impl> impl_;
  HWND target_ = nullptr;
  HWND hwnd_ = nullptr;
  bool enabled_ = false;
  float radius_ = 0.0f;  // logical pixels
  UINT region_width_ = 0;
  UINT region_height_ = 0;
  float region_radius_ = -1.0f;
};

#endif  // RUNNER_HOST_BACKDROP_WINDOW_H_
