#ifndef RUNNER_DESKTOP_CAPTURE_H_
#define RUNNER_DESKTOP_CAPTURE_H_

#include <windows.h>

#include <d3d11.h>
#include <wrl/client.h>

#include <memory>

// Keeps a GPU copy of one monitor's composed desktop via Windows.Graphics.
// Capture, without the cursor. Windows excluded from capture
// (WDA_EXCLUDEFROMCAPTURE) are absent from the image, so the app can sample
// what lies behind itself. Unlike Desktop Duplication, an initial frame is
// delivered even when the desktop is static.
class DesktopCapture {
 public:
  DesktopCapture();
  ~DesktopCapture();

  DesktopCapture(const DesktopCapture&) = delete;
  DesktopCapture& operator=(const DesktopCapture&) = delete;

  // Starts capturing |monitor|; false if capture is unavailable.
  bool Start(ID3D11Device* device, HMONITOR monitor);
  void Stop();

  bool active() const { return impl_ != nullptr; }
  bool has_frame() const { return has_frame_; }
  HMONITOR monitor() const { return monitor_; }

  // Virtual-desktop rectangle of the captured monitor, in physical pixels.
  const RECT& desktop_rect() const { return desktop_rect_; }

  // The latest desktop image, monitor-sized BGRA; null until started.
  ID3D11Texture2D* frame() const { return frame_.Get(); }

  // Pulls the newest desktop image into frame(). Returns true if it changed.
  // If the monitor's size changes, capture stops and the caller is expected
  // to Start() again.
  bool Update();

 private:
  struct Impl;

  std::unique_ptr<Impl> impl_;
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> context_;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> frame_;
  HMONITOR monitor_ = nullptr;
  RECT desktop_rect_{};
  bool has_frame_ = false;
};

#endif  // RUNNER_DESKTOP_CAPTURE_H_
