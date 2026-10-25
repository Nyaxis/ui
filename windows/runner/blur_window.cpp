#include "blur_window.h"

#include <algorithm>

namespace {

constexpr const wchar_t kBlurWindowClassName[] = L"NYAXIS_BLUR_WINDOW";

BlurWindow* g_active = nullptr;

// Missing from SDKs older than 10.0.19041.
constexpr DWORD kWdaExcludeFromCapture = 0x11;

constexpr UINT_PTR kCaptureTimer = 1;
constexpr UINT kCaptureIntervalMs = 8;

}  // namespace

extern "C" __declspec(dllexport) void NyaxisBlurConfigure(
    int enabled, double radius, double size, int passes, double strength,
    double noise, double contrast, double brightness, double vibrancy) {
  if (!g_active) {
    return;
  }
  BlurParams params;
  params.size = static_cast<float>(size);
  params.passes = passes;
  params.strength = static_cast<float>(strength);
  params.noise = static_cast<float>(noise);
  params.contrast = static_cast<float>(contrast);
  params.brightness = static_cast<float>(brightness);
  params.vibrancy = static_cast<float>(vibrancy);
  g_active->Configure(enabled != 0, static_cast<float>(radius), params);
}

// static
void BlurWindow::SetActive(BlurWindow* window) { g_active = window; }

BlurWindow::~BlurWindow() {
  if (g_active == this) {
    g_active = nullptr;
  }
  // Release graphics objects before the window they target goes away.
  capture_.Stop();
  clip_.Reset();
  visual_.Reset();
  dcomp_target_.Reset();
  dcomp_.Reset();
  swap_chain_.Reset();
  context_.Reset();
  d3d_.Reset();
  if (hwnd_) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
}

bool BlurWindow::Create(HWND target) {
  target_ = target;

  WNDCLASS window_class{};
  window_class.lpszClassName = kBlurWindowClassName;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpfnWndProc = BlurWindow::WndProc;
  RegisterClass(&window_class);

  // No redirection bitmap: DirectComposition supplies every pixel. Click-
  // through and non-activating so it never steals input from Flutter.
  hwnd_ = CreateWindowEx(
      WS_EX_NOREDIRECTIONBITMAP | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE |
          WS_EX_TRANSPARENT,
      kBlurWindowClassName, L"", WS_POPUP, 0, 0, 1, 1, nullptr, nullptr,
      GetModuleHandle(nullptr), this);
  if (!hwnd_) {
    return false;
  }
  return InitGraphics();
}

bool BlurWindow::InitGraphics() {
  using Microsoft::WRL::ComPtr;

  if (FAILED(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
                               D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0,
                               D3D11_SDK_VERSION, &d3d_, nullptr,
                               &context_))) {
    return false;
  }

  ComPtr<IDXGIDevice> dxgi_device;
  ComPtr<IDXGIAdapter> adapter;
  ComPtr<IDXGIFactory2> factory;
  if (FAILED(d3d_.As(&dxgi_device)) ||
      FAILED(dxgi_device->GetAdapter(&adapter)) ||
      FAILED(adapter->GetParent(IID_PPV_ARGS(&factory)))) {
    return false;
  }

  if (FAILED(DCompositionCreateDevice(dxgi_device.Get(),
                                      IID_PPV_ARGS(&dcomp_))) ||
      FAILED(dcomp_->CreateTargetForHwnd(hwnd_, TRUE, &dcomp_target_)) ||
      FAILED(dcomp_->CreateVisual(&visual_)) ||
      FAILED(dcomp_->CreateRectangleClip(&clip_))) {
    return false;
  }

  RECT rect;
  GetWindowRect(target_, &rect);
  width_ = static_cast<UINT>(std::max<LONG>(1, rect.right - rect.left));
  height_ = static_cast<UINT>(std::max<LONG>(1, rect.bottom - rect.top));

  DXGI_SWAP_CHAIN_DESC1 desc{};
  desc.Width = width_;
  desc.Height = height_;
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
  desc.BufferCount = 2;
  desc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
  // The frosted backdrop is opaque; the translucent tint is Flutter's, on top.
  desc.AlphaMode = DXGI_ALPHA_MODE_IGNORE;
  if (FAILED(factory->CreateSwapChainForComposition(d3d_.Get(), &desc, nullptr,
                                                    &swap_chain_))) {
    return false;
  }

  if (!blur_.Init(d3d_.Get())) {
    return false;
  }

  visual_->SetContent(swap_chain_.Get());
  visual_->SetClip(clip_.Get());
  dcomp_target_->SetRoot(visual_.Get());
  ApplyClip();
  return true;
}

void BlurWindow::Configure(bool enabled, float radius,
                           const BlurParams& params) {
  params_ = params;
  active_ = enabled && !params_.IsIdentity();
  radius_ = std::max(0.0f, radius);
  content_dirty_ = true;

  // While the effect is on, both windows must be invisible to capture or
  // their own pixels would feed back into the backdrop. The side effect is
  // that screenshots and screen recordings skip them too, so it is only set
  // while needed.
  const DWORD affinity = active_ ? kWdaExcludeFromCapture : WDA_NONE;
  SetWindowDisplayAffinity(hwnd_, affinity);
  SetWindowDisplayAffinity(target_, affinity);

  ApplyClip();
  Sync();
}

float BlurWindow::ScaledRadius() const {
  return radius_ * GetDpiForWindow(target_) / 96.0f;
}

void BlurWindow::UpdateTargetRegion(UINT width, UINT height) {
  const float radius = ScaledRadius();
  if (width == region_width_ && height == region_height_ &&
      radius == region_radius_) {
    return;
  }
  region_width_ = width;
  region_height_ = height;
  region_radius_ = radius;
  ApplyClip();

  if (radius <= 0.0f) {
    SetWindowRgn(target_, nullptr, TRUE);
    return;
  }
  // The ellipse arguments are diameters, and the lower-right edge of a region
  // is exclusive, hence 2 * radius and the extra pixel.
  const int diameter = static_cast<int>(radius * 2.0f + 0.5f);
  HRGN region = CreateRoundRectRgn(0, 0, width + 1, height + 1, diameter,
                                   diameter);
  // On success the system owns the region; on failure we do.
  if (region && !SetWindowRgn(target_, region, TRUE)) {
    DeleteObject(region);
  }
}

void BlurWindow::Sync() {
  if (!hwnd_ || !target_) {
    return;
  }
  RECT rect;
  if (!GetWindowRect(target_, &rect)) {
    return;
  }
  const UINT width = static_cast<UINT>(std::max<LONG>(1, rect.right - rect.left));
  const UINT height = static_cast<UINT>(std::max<LONG>(1, rect.bottom - rect.top));

  UpdateTargetRegion(width, height);

  if (!active_ || !IsWindowVisible(target_) || IsIconic(target_)) {
    StopCapture();
    ShowWindow(hwnd_, SW_HIDE);
    return;
  }

  EnsureCapture();

  // Stay hidden until there is something to show; the timer re-syncs when
  // the first frame arrives.
  if (!capture_.has_frame()) {
    ShowWindow(hwnd_, SW_HIDE);
    return;
  }

  const RECT& monitor = capture_.desktop_rect();
  const UINT monitor_width = static_cast<UINT>(monitor.right - monitor.left);
  const UINT monitor_height = static_cast<UINT>(monitor.bottom - monitor.top);
  if (monitor_width != width_ || monitor_height != height_) {
    Resize(monitor_width, monitor_height);
  }

  // A move only touches the clip; pixels are redrawn when the capture changes.
  clip_rect_ = {rect.left - monitor.left, rect.top - monitor.top,
                rect.right - monitor.left, rect.bottom - monitor.top};
  ApplyClip();
  if (content_dirty_) {
    RenderContent();
  }

  // Inserting after the target parks this window directly beneath it, however
  // the target is raised or lowered.
  SetWindowPos(hwnd_, target_, monitor.left, monitor.top, monitor_width,
               monitor_height,
               SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_SHOWWINDOW);
}

void BlurWindow::EnsureCapture() {
  HMONITOR monitor = MonitorFromWindow(target_, MONITOR_DEFAULTTONEAREST);
  if (!capture_.active() || capture_.monitor() != monitor) {
    capture_.Start(d3d_.Get(), monitor);
  }
  SetTimer(hwnd_, kCaptureTimer, kCaptureIntervalMs, nullptr);
}

void BlurWindow::StopCapture() {
  KillTimer(hwnd_, kCaptureTimer);
  capture_.Stop();
}

void BlurWindow::OnCaptureTimer() {
  if (!capture_.active()) {
    // Access lost or not yet available; Sync restarts it.
    Sync();
    return;
  }
  // Wait briefly for the first image; a static desktop may not produce one
  // on its own. After that, poll without blocking.
  if (capture_.Update(capture_.has_frame() ? 0 : 50)) {
    content_dirty_ = true;
    Sync();
  }
}

void BlurWindow::Resize(UINT width, UINT height) {
  width_ = width;
  height_ = height;
  if (!swap_chain_) {
    return;
  }
  if (SUCCEEDED(swap_chain_->ResizeBuffers(0, width, height,
                                           DXGI_FORMAT_UNKNOWN, 0))) {
    content_dirty_ = true;
  }
}

void BlurWindow::ApplyClip() {
  if (!clip_ || !dcomp_) {
    return;
  }
  const float clip_width = static_cast<float>(clip_rect_.right - clip_rect_.left);
  const float clip_height = static_cast<float>(clip_rect_.bottom - clip_rect_.top);
  const float radius =
      std::min(ScaledRadius(), std::min(clip_width, clip_height) / 2.0f);
  clip_->SetLeft(static_cast<float>(clip_rect_.left));
  clip_->SetTop(static_cast<float>(clip_rect_.top));
  clip_->SetRight(static_cast<float>(clip_rect_.right));
  clip_->SetBottom(static_cast<float>(clip_rect_.bottom));
  clip_->SetTopLeftRadiusX(radius);
  clip_->SetTopLeftRadiusY(radius);
  clip_->SetTopRightRadiusX(radius);
  clip_->SetTopRightRadiusY(radius);
  clip_->SetBottomLeftRadiusX(radius);
  clip_->SetBottomLeftRadiusY(radius);
  clip_->SetBottomRightRadiusX(radius);
  clip_->SetBottomRightRadiusY(radius);
  dcomp_->Commit();
}

// Blurs the captured monitor into the swap chain, 1:1 with the desktop.
void BlurWindow::RenderContent() {
  using Microsoft::WRL::ComPtr;
  if (!swap_chain_ || !capture_.frame()) {
    return;
  }
  ComPtr<ID3D11Texture2D> back_buffer;
  ComPtr<ID3D11RenderTargetView> rtv;
  if (FAILED(swap_chain_->GetBuffer(0, IID_PPV_ARGS(&back_buffer))) ||
      FAILED(d3d_->CreateRenderTargetView(back_buffer.Get(), nullptr, &rtv))) {
    return;
  }
  D3D11_TEXTURE2D_DESC source_desc{};
  D3D11_TEXTURE2D_DESC target_desc{};
  capture_.frame()->GetDesc(&source_desc);
  back_buffer->GetDesc(&target_desc);
  if (source_desc.Width != target_desc.Width ||
      source_desc.Height != target_desc.Height) {
    return;
  }
  blur_.Render(context_.Get(), capture_.frame(), rtv.Get(), target_desc.Width,
               target_desc.Height, params_);
  swap_chain_->Present(0, 0);
  content_dirty_ = false;
}

// static
LRESULT CALLBACK BlurWindow::WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                     LPARAM lparam) {
  if (message == WM_NCCREATE) {
    SetWindowLongPtr(
        hwnd, GWLP_USERDATA,
        reinterpret_cast<LONG_PTR>(
            reinterpret_cast<CREATESTRUCT*>(lparam)->lpCreateParams));
  } else if (message == WM_NCHITTEST) {
    return HTTRANSPARENT;
  } else if (message == WM_TIMER && wparam == kCaptureTimer) {
    if (auto* self = reinterpret_cast<BlurWindow*>(
            GetWindowLongPtr(hwnd, GWLP_USERDATA))) {
      self->OnCaptureTimer();
    }
    return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}
