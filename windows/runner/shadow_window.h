#ifndef RUNNER_SHADOW_WINDOW_H_
#define RUNNER_SHADOW_WINDOW_H_

#include <windows.h>

#include <vector>

// soft drop shadow drawn in its own window beneath the flutter window
class ShadowWindow {
 public:
  ShadowWindow();
  ~ShadowWindow();

  ShadowWindow(const ShadowWindow&) = delete;
  ShadowWindow& operator=(const ShadowWindow&) = delete;

  bool Create(HWND target);

  void Sync();

  // moves ahead of a pending target move so the two land in the same frame
  void Follow(const WINDOWPOS& pending);

  // radius is in logical pixels and scaled by the target's dpi
  void Configure(float radius);

  // keeps the shadow hidden while the target changes state
  void SetSuspended(bool suspended) { suspended_ = suspended; }
  // the instance the exported ffi entry point talks to
  static void SetActive(ShadowWindow* window);

 private:
  void Render(UINT width, UINT height, UINT pad, float radius);

  HWND target_ = nullptr;
  HWND hwnd_ = nullptr;
  float radius_ = 0.0f;  // logical pixels
  bool suspended_ = false;
  UINT rendered_width_ = 0;
  UINT rendered_height_ = 0;
  UINT rendered_dpi_ = 0;
  UINT rendered_pad_ = 0;
  float rendered_radius_ = -1.0f;
  // a small shadow that windows of any size are made from
  std::vector<UINT32> tile_;
  UINT tile_dpi_ = 0;
  float tile_radius_ = -1.0f;
  HBITMAP bitmap_ = nullptr;
  void* bits_ = nullptr;
};

#endif  // RUNNER_SHADOW_WINDOW_H_
