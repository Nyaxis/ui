#ifndef RUNNER_HOST_BACKDROP_WINDOW_H_
#define RUNNER_HOST_BACKDROP_WINDOW_H_

#include <windows.h>

#include <memory>

// click-through window kept directly beneath the flutter window, showing a
// host backdrop brush clipped to the theme's rounded corners. dwm composes the
// backdrop itself, so nothing is captured and the window stays screenshot-able.
class HostBackdropWindow {
 public:
  HostBackdropWindow();
  ~HostBackdropWindow();

  HostBackdropWindow(const HostBackdropWindow&) = delete;
  HostBackdropWindow& operator=(const HostBackdropWindow&) = delete;

  bool Create(HWND target);

  void Sync();

  // radius is in logical pixels and scaled by the target's dpi
  void Configure(bool enabled, float radius);

  // the instance the exported ffi entry point talks to
  static void SetActive(HostBackdropWindow* window);

 private:
  struct Impl;

  bool EnsureComposition();
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
