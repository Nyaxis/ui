#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr UINT_PTR kTransitionTimer = 1;
constexpr UINT kTransitionMs = 350;
constexpr UINT kRestoreMs = 100;

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  shadow_window_ = std::make_unique<ShadowWindow>();
  if (shadow_window_->Create(GetHandle())) {
    ShadowWindow::SetActive(shadow_window_.get());
  } else {
    shadow_window_ = nullptr;
  }

  backdrop_window_ = std::make_unique<HostBackdropWindow>();
  if (backdrop_window_->Create(GetHandle())) {
    HostBackdropWindow::SetActive(backdrop_window_.get());
  } else {
    backdrop_window_ = nullptr;
  }

  RECT frame = GetClientArea();

  // the size must match the window to avoid recreating the surface at startup
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // the first frame can finish before the show callback is registered, so
  // force a pending one (a no-op if it hasn't completed yet)
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  backdrop_window_ = nullptr;
  shadow_window_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_WINDOWPOSCHANGING:
      if (shadow_window_) {
        shadow_window_->Follow(*reinterpret_cast<WINDOWPOS*>(lparam));
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_WINDOWPOSCHANGED:
    case WM_SHOWWINDOW:
      // windows animates the window when it maximizes, minimizes or restores,
      // and the shadow and the backdrop are windows of their own that would
      // jump to the end of it, so they stay away until it is over
      if ((IsZoomed(hwnd) != FALSE) != zoomed_ ||
          (IsIconic(hwnd) != FALSE) != iconic_) {
        const bool zoomed = IsZoomed(hwnd) != FALSE;
        // a window that comes back from the taskbar keeps its place, so only
        // a short wait keeps the backdrop from showing while it still grows
        const UINT delay = zoomed != zoomed_ ? kTransitionMs : kRestoreMs;
        zoomed_ = zoomed;
        iconic_ = IsIconic(hwnd) != FALSE;
        if (shadow_window_) {
          shadow_window_->SetSuspended(true);
        }
        if (backdrop_window_) {
          backdrop_window_->SetSuspended(true);
        }
        SetTimer(hwnd, kTransitionTimer, delay, nullptr);
      }
      // the shadow goes first so the backdrop ends up directly beneath the
      // target, above the shadow
      if (shadow_window_) {
        shadow_window_->Sync();
      }
      if (backdrop_window_) {
        backdrop_window_->Sync();
      }
      break;
    case WM_TIMER:
      if (wparam == kTransitionTimer) {
        KillTimer(hwnd, kTransitionTimer);
        if (shadow_window_) {
          shadow_window_->SetSuspended(false);
          shadow_window_->Sync();
        }
        if (backdrop_window_) {
          backdrop_window_->SetSuspended(false);
          backdrop_window_->Sync();
        }
        return 0;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
