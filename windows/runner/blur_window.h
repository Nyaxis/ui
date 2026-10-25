#ifndef RUNNER_BLUR_WINDOW_H_
#define RUNNER_BLUR_WINDOW_H_

#include <windows.h>

#include <d3d11.h>
#include <dcomp.h>
#include <dxgi1_2.h>
#include <wrl/client.h>

#include "desktop_capture.h"
#include "kawase_blur.h"

// A click-through window parked directly beneath the Flutter window. It owns
// a DirectComposition visual whose content is the backdrop effect, clipped to
// a rounded rectangle at the theme radius. Flutter paints transparently on
// top, so the frost follows the painted curve exactly.
class BlurWindow {
 public:
  BlurWindow() = default;
  ~BlurWindow();

  BlurWindow(const BlurWindow&) = delete;
  BlurWindow& operator=(const BlurWindow&) = delete;

  // Creates the window and graphics objects for |target|, the Flutter window.
  bool Create(HWND target);

  // Re-aligns position, size, visibility and z-order with the target.
  void Sync();

  // |radius| is the theme corner radius in logical pixels; it is scaled by
  // the target's current DPI.
  void Configure(bool enabled, float radius, const BlurParams& params);

  // The instance reachable from the exported FFI entry points.
  static void SetActive(BlurWindow* window);

 private:
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam);

  bool InitGraphics();
  void Resize(UINT width, UINT height);
  void ApplyClip();
  void RenderContent();
  void EnsureCapture();
  void StopCapture();
  void OnCaptureTimer();

  // Crops the target's silhouette (and hit-testing) to the rounded shape.
  // Rebuilt whenever size or scaled radius change, e.g. on a DPI change.
  void UpdateTargetRegion(UINT width, UINT height);
  float ScaledRadius() const;

  HWND target_ = nullptr;
  HWND hwnd_ = nullptr;
  // The effect is on and would change the backdrop; otherwise the plain
  // transparent window shows through and no capture runs.
  bool active_ = false;
  float radius_ = 0.0f;  // logical pixels
  BlurParams params_;
  // This window covers the captured monitor and never moves with the target;
  // only the clip below follows it, so the image can't slide against the
  // desktop while the target is dragged.
  UINT width_ = 0;
  UINT height_ = 0;
  RECT clip_rect_{};  // target window, relative to this window
  bool content_dirty_ = true;
  UINT region_width_ = 0;
  UINT region_height_ = 0;
  float region_radius_ = -1.0f;

  Microsoft::WRL::ComPtr<ID3D11Device> d3d_;
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> context_;
  Microsoft::WRL::ComPtr<IDXGISwapChain1> swap_chain_;
  Microsoft::WRL::ComPtr<IDCompositionDevice> dcomp_;
  Microsoft::WRL::ComPtr<IDCompositionTarget> dcomp_target_;
  Microsoft::WRL::ComPtr<IDCompositionVisual> visual_;
  Microsoft::WRL::ComPtr<IDCompositionRectangleClip> clip_;

  DesktopCapture capture_;
  KawaseBlur blur_;
};

#endif  // RUNNER_BLUR_WINDOW_H_
