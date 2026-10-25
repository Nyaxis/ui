#ifndef RUNNER_DESKTOP_CAPTURE_H_
#define RUNNER_DESKTOP_CAPTURE_H_

#include <windows.h>

#include <d3d11.h>
#include <dxgi1_2.h>
#include <wrl/client.h>

// Keeps a GPU copy of one monitor's composed desktop via DXGI Desktop
// Duplication. Windows excluded from capture (WDA_EXCLUDEFROMCAPTURE) are
// absent from the image, so the app can sample what lies behind itself.
class DesktopCapture {
 public:
  // Starts duplicating the output showing |monitor|. The output has to live on
  // the same adapter as |device|; returns false if it doesn't or if
  // duplication is unavailable (secure desktop, too many duplications, ...).
  bool Start(ID3D11Device* device, HMONITOR monitor);
  void Stop();

  bool active() const { return duplication_ != nullptr; }
  bool has_frame() const { return has_frame_; }
  HMONITOR monitor() const { return monitor_; }

  // Virtual-desktop rectangle of the captured monitor, in physical pixels.
  const RECT& desktop_rect() const { return desktop_rect_; }

  // The latest desktop image, monitor-sized BGRA; null until the first frame.
  ID3D11Texture2D* frame() const { return frame_.Get(); }

  // Pulls the newest desktop image into frame(). Returns true if it changed.
  // On lost access (mode change, secure desktop) capture stops and the caller
  // is expected to Start() again.
  bool Update(UINT timeout_ms);

 private:
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> context_;
  Microsoft::WRL::ComPtr<IDXGIOutputDuplication> duplication_;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> frame_;
  HMONITOR monitor_ = nullptr;
  RECT desktop_rect_{};
  bool has_frame_ = false;
};

#endif  // RUNNER_DESKTOP_CAPTURE_H_
