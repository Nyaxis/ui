#include "host_backdrop_window.h"

#include <unknwn.h>

#include <DispatcherQueue.h>
#include <windows.ui.composition.interop.h>

#include <winrt/Windows.Foundation.Numerics.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.System.h>
#include <winrt/Windows.UI.Composition.Desktop.h>
#include <winrt/Windows.UI.Composition.h>

#include <algorithm>

namespace composition = winrt::Windows::UI::Composition;
namespace numerics = winrt::Windows::Foundation::Numerics;

namespace {

constexpr const wchar_t kWindowClassName[] = L"NYAXIS_BACKDROP_WINDOW";

HostBackdropWindow* g_active = nullptr;

// undocumented api: without the host backdrop accent, the host backdrop brush
// renders black instead of sampling what is behind the window
constexpr DWORD kWcaAccentPolicy = 19;
constexpr int kAccentEnableHostBackdrop = 5;

struct AccentPolicy {
  int accent_state;
  int accent_flags;
  DWORD gradient_color;
  int animation_id;
};

struct CompositionAttributeData {
  DWORD attribute;
  void* data;
  SIZE_T size;
};

void EnableHostBackdrop(HWND hwnd) {
  using SetWindowCompositionAttributeFn =
      BOOL(WINAPI*)(HWND, CompositionAttributeData*);
  static const auto set_attribute =
      reinterpret_cast<SetWindowCompositionAttributeFn>(GetProcAddress(
          GetModuleHandle(L"user32.dll"), "SetWindowCompositionAttribute"));
  if (!set_attribute) {
    return;
  }
  AccentPolicy policy{kAccentEnableHostBackdrop, 0, 0, 0};
  CompositionAttributeData data{kWcaAccentPolicy, &policy, sizeof(policy)};
  set_attribute(hwnd, &data);
}

}  // namespace

struct HostBackdropWindow::Impl {
  winrt::Windows::System::DispatcherQueueController queue_controller{nullptr};
  composition::Compositor compositor{nullptr};
  composition::Desktop::DesktopWindowTarget window_target{nullptr};
  composition::ContainerVisual root{nullptr};
  composition::SpriteVisual backdrop{nullptr};
  composition::CompositionRoundedRectangleGeometry clip_geometry{nullptr};
};

extern "C" __declspec(dllexport) void NyaxisBlurConfigure(int enabled,
                                                          double radius) {
  if (g_active) {
    g_active->Configure(enabled != 0, static_cast<float>(radius));
  }
}

void HostBackdropWindow::SetActive(HostBackdropWindow* window) {
  g_active = window;
}

HostBackdropWindow::HostBackdropWindow() = default;

HostBackdropWindow::~HostBackdropWindow() {
  if (g_active == this) {
    g_active = nullptr;
  }
  // the visual tree must go before the window it targets
  impl_.reset();
  if (hwnd_) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
}

bool HostBackdropWindow::Create(HWND target) {
  target_ = target;

  WNDCLASS window_class{};
  window_class.lpszClassName = kWindowClassName;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpfnWndProc = DefWindowProc;
  RegisterClass(&window_class);

  // only a layered, transparent window passes clicks through to other
  // processes; the composition tree draws every pixel, so no redirection bitmap
  hwnd_ = CreateWindowEx(
      WS_EX_NOREDIRECTIONBITMAP | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE |
          WS_EX_LAYERED | WS_EX_TRANSPARENT,
      kWindowClassName, L"", WS_POPUP, 0, 0, 1, 1, nullptr, nullptr,
      GetModuleHandle(nullptr), nullptr);
  if (!hwnd_) {
    return false;
  }
  SetLayeredWindowAttributes(hwnd_, 0, 255, LWA_ALPHA);
  EnableHostBackdrop(hwnd_);
  return true;
}

// a thread holds one dispatcher queue, and the webview plugin fails to start
// when this one already took it, so the composition is only built once the
// backdrop is switched on, and reuses a queue that exists by then
bool HostBackdropWindow::EnsureComposition() {
  if (impl_) {
    return true;
  }
  try {
    auto impl = std::make_unique<Impl>();

    // composition needs a dispatcher queue on this thread
    if (!winrt::Windows::System::DispatcherQueue::GetForCurrentThread()) {
      DispatcherQueueOptions options{sizeof(options), DQTYPE_THREAD_CURRENT,
                                     DQTAT_COM_NONE};
      ABI::Windows::System::IDispatcherQueueController* controller = nullptr;
      winrt::check_hresult(
          CreateDispatcherQueueController(options, &controller));
      winrt::attach_abi(impl->queue_controller, controller);
    }

    impl->compositor = composition::Compositor();

    auto interop =
        impl->compositor.as<ABI::Windows::UI::Composition::Desktop::
                                ICompositorDesktopInterop>();
    winrt::check_hresult(interop->CreateDesktopWindowTarget(
        hwnd_, FALSE,
        reinterpret_cast<ABI::Windows::UI::Composition::Desktop::
                             IDesktopWindowTarget**>(
            winrt::put_abi(impl->window_target))));

    impl->root = impl->compositor.CreateContainerVisual();
    impl->window_target.Root(impl->root);

    impl->backdrop = impl->compositor.CreateSpriteVisual();
    impl->backdrop.Brush(impl->compositor.CreateHostBackdropBrush());
    impl->clip_geometry = impl->compositor.CreateRoundedRectangleGeometry();
    impl->backdrop.Clip(
        impl->compositor.CreateGeometricClip(impl->clip_geometry));
    impl->root.Children().InsertAtTop(impl->backdrop);

    impl_ = std::move(impl);
  } catch (const winrt::hresult_error&) {
    impl_.reset();
    return false;
  }
  return true;
}

float HostBackdropWindow::ScaledRadius() const {
  return radius_ * GetDpiForWindow(target_) / 96.0f;
}

void HostBackdropWindow::Configure(bool enabled, float radius) {
  enabled_ = enabled;
  radius_ = std::max(0.0f, radius);
  if (enabled_) {
    EnsureComposition();
  }
  Sync();
}

void HostBackdropWindow::UpdateTargetRegion(UINT width, UINT height) {
  const float radius = ScaledRadius();
  if (width == region_width_ && height == region_height_ &&
      radius == region_radius_) {
    return;
  }
  region_width_ = width;
  region_height_ = height;
  region_radius_ = radius;

  if (radius <= 0.0f) {
    SetWindowRgn(target_, nullptr, TRUE);
    return;
  }
  // the ellipse arguments are diameters, and a region's lower-right edge is
  // exclusive, hence 2 * radius and the extra pixel
  const int diameter = static_cast<int>(radius * 2.0f + 0.5f);
  HRGN region = CreateRoundRectRgn(0, 0, width + 1, height + 1, diameter,
                                   diameter);
  // the system owns the region after a successful call
  if (region && !SetWindowRgn(target_, region, TRUE)) {
    DeleteObject(region);
  }
}

void HostBackdropWindow::UpdateVisuals(UINT width, UINT height) {
  if (!impl_) {
    return;
  }
  const numerics::float2 size{static_cast<float>(width),
                              static_cast<float>(height)};
  const float radius =
      std::min(ScaledRadius(), std::min(size.x, size.y) / 2.0f);
  impl_->backdrop.Size(size);
  impl_->clip_geometry.Size(size);
  impl_->clip_geometry.CornerRadius({radius, radius});
}

void HostBackdropWindow::Sync() {
  if (!hwnd_ || !target_) {
    return;
  }
  RECT rect;
  if (!GetWindowRect(target_, &rect)) {
    return;
  }
  const UINT width =
      static_cast<UINT>(std::max<LONG>(1, rect.right - rect.left));
  const UINT height =
      static_cast<UINT>(std::max<LONG>(1, rect.bottom - rect.top));

  UpdateTargetRegion(width, height);

  if (!enabled_ || !IsWindowVisible(target_) || IsIconic(target_)) {
    ShowWindow(hwnd_, SW_HIDE);
    return;
  }

  UpdateVisuals(width, height);

  // inserting after the target keeps this window directly beneath it
  SetWindowPos(hwnd_, target_, rect.left, rect.top, width, height,
               SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_SHOWWINDOW);
}
