#include "shadow_window.h"

#include <algorithm>
#include <cmath>

namespace {

constexpr const wchar_t kWindowClassName[] = L"NYAXIS_SHADOW_WINDOW";

// logical pixels
constexpr float kBlur = 24.0f;
constexpr float kOffsetY = 4.0f;
constexpr float kMaxAlpha = 0.45f;
constexpr float kHoleInset = 10.0f;

ShadowWindow* g_active = nullptr;

float SmoothStep(float edge0, float edge1, float x) {
  const float t = std::clamp((x - edge0) / (edge1 - edge0), 0.0f, 1.0f);
  return t * t * (3.0f - 2.0f * t);
}

// signed distance to a rounded rectangle centered on the origin, negative
// inside
float RoundedRectDistance(float x, float y, float half_w, float half_h,
                          float radius) {
  const float qx = std::fabs(x) - (half_w - radius);
  const float qy = std::fabs(y) - (half_h - radius);
  const float outside = std::hypot(std::max(qx, 0.0f), std::max(qy, 0.0f));
  return outside + std::min(std::max(qx, qy), 0.0f) - radius;
}

// draws the shadow of a window of [width] x [height] pixels into a buffer that
// has [pad] pixels around it
void FillShadow(UINT32* pixels, UINT width, UINT height, UINT pad, float radius,
                float scale) {
  const UINT full_width = width + 2 * pad;
  const UINT full_height = height + 2 * pad;
  const float blur = kBlur * scale;
  const float offset_y = kOffsetY * scale;
  const float half_w = width / 2.0f;
  const float half_h = height / 2.0f;
  const float r = std::min(radius, std::min(half_w, half_h));

  for (UINT y = 0; y < full_height; ++y) {
    for (UINT x = 0; x < full_width; ++x) {
      const float px = x + 0.5f - pad - half_w;
      const float py = y + 0.5f - pad - half_h;

      // the shadow is the window's shape shifted down; the window's own area
      // is cut out so a translucent window doesn't show it through, short of
      // its edge, because the shadow trails the window while it is dragged
      // and the desktop would show through the gap
      const float shadow_d =
          RoundedRectDistance(px, py - offset_y, half_w, half_h, r);
      const float inside_d = RoundedRectDistance(px, py, half_w, half_h, r);

      const float falloff = 1.0f - SmoothStep(-blur * 0.5f, blur, shadow_d);
      const float alpha =
          kMaxAlpha * falloff * falloff *
          std::clamp(inside_d + kHoleInset * scale + 0.5f, 0.0f, 1.0f);

      // premultiplied black, so only the alpha channel carries data
      pixels[y * full_width + x] =
          static_cast<UINT32>(alpha * 255.0f + 0.5f) << 24;
    }
  }
}

}  // namespace

extern "C" __declspec(dllexport) void NyaxisShadowConfigure(double radius) {
  if (g_active) {
    g_active->Configure(static_cast<float>(radius));
  }
}

void ShadowWindow::SetActive(ShadowWindow* window) {
  g_active = window;
}

ShadowWindow::ShadowWindow() = default;

ShadowWindow::~ShadowWindow() {
  if (g_active == this) {
    g_active = nullptr;
  }
  if (hwnd_) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
  if (bitmap_) {
    DeleteObject(bitmap_);
    bitmap_ = nullptr;
  }
}

bool ShadowWindow::Create(HWND target) {
  target_ = target;

  WNDCLASS window_class{};
  window_class.lpszClassName = kWindowClassName;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpfnWndProc = DefWindowProc;
  RegisterClass(&window_class);

  // only a layered, transparent window passes clicks through to other
  // processes
  hwnd_ = CreateWindowEx(
      WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED | WS_EX_TRANSPARENT,
      kWindowClassName, L"", WS_POPUP, 0, 0, 1, 1, nullptr, nullptr,
      GetModuleHandle(nullptr), nullptr);
  return hwnd_ != nullptr;
}

void ShadowWindow::Configure(float radius) {
  radius_ = std::max(0.0f, radius);
  Sync();
}

void ShadowWindow::Render(UINT width, UINT height, UINT pad, float radius) {
  const UINT full_width = width + 2 * pad;
  const UINT full_height = height + 2 * pad;

  if (bitmap_) {
    DeleteObject(bitmap_);
    bitmap_ = nullptr;
    bits_ = nullptr;
  }

  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(info.bmiHeader);
  info.bmiHeader.biWidth = static_cast<LONG>(full_width);
  info.bmiHeader.biHeight = -static_cast<LONG>(full_height);
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  bitmap_ =
      CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &bits_, nullptr, 0);
  if (!bitmap_) {
    return;
  }

  const float scale = rendered_dpi_ / 96.0f;
  auto* pixels = static_cast<UINT32*>(bits_);

  // further than this from the window's corners the shadow is the same all
  // along an edge, so a small one is drawn once, and a window of any size
  // takes its corners and repeats its edges; that is quick enough to keep up
  // with a window that is being resized
  const UINT zone =
      pad + static_cast<UINT>(std::ceil(radius + kOffsetY * scale)) + 4;
  const UINT tile = 2 * zone + 2;
  if (full_width <= tile || full_height <= tile) {
    FillShadow(pixels, width, height, pad, radius, scale);
    return;
  }

  if (tile_.size() != static_cast<size_t>(tile) * tile ||
      tile_dpi_ != rendered_dpi_ || tile_radius_ != radius) {
    tile_.resize(static_cast<size_t>(tile) * tile);
    FillShadow(tile_.data(), tile - 2 * pad, tile - 2 * pad, pad, radius,
               scale);
    tile_dpi_ = rendered_dpi_;
    tile_radius_ = radius;
  }

  for (UINT y = 0; y < full_height; ++y) {
    const UINT source_y =
        y < zone ? y
                 : (y >= full_height - zone ? y - (full_height - tile) : zone);
    const UINT32* source = tile_.data() + static_cast<size_t>(source_y) * tile;
    UINT32* row = pixels + static_cast<size_t>(y) * full_width;
    std::copy(source, source + zone, row);
    std::fill(row + zone, row + full_width - zone, source[zone]);
    std::copy(source + tile - zone, source + tile, row + full_width - zone);
  }
}

void ShadowWindow::Follow(const WINDOWPOS& pending) {
  if (!hwnd_ || !bitmap_ || (pending.flags & SWP_NOMOVE) ||
      !IsWindowVisible(hwnd_)) {
    return;
  }
  SetWindowPos(hwnd_, nullptr, pending.x - static_cast<LONG>(rendered_pad_),
               pending.y - static_cast<LONG>(rendered_pad_), 0, 0,
               SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
}

void ShadowWindow::Sync() {
  if (!hwnd_ || !target_) {
    return;
  }
  RECT rect;
  if (!GetWindowRect(target_, &rect)) {
    return;
  }
  if (!IsWindowVisible(target_) || IsIconic(target_) || IsZoomed(target_)) {
    ShowWindow(hwnd_, SW_HIDE);
    return;
  }

  const UINT width =
      static_cast<UINT>(std::max<LONG>(1, rect.right - rect.left));
  const UINT height =
      static_cast<UINT>(std::max<LONG>(1, rect.bottom - rect.top));
  const UINT dpi = GetDpiForWindow(target_);
  const float radius = radius_ * dpi / 96.0f;
  const UINT pad = static_cast<UINT>(std::ceil(kBlur * dpi / 96.0f));

  if (!bitmap_ || width != rendered_width_ || height != rendered_height_ ||
      dpi != rendered_dpi_ || radius != rendered_radius_) {
    rendered_width_ = width;
    rendered_height_ = height;
    rendered_dpi_ = dpi;
    rendered_pad_ = pad;
    rendered_radius_ = radius;
    Render(width, height, pad, radius);
    if (!bitmap_) {
      return;
    }

    HDC screen = GetDC(nullptr);
    HDC memory = CreateCompatibleDC(screen);
    HGDIOBJ previous = SelectObject(memory, bitmap_);

    SIZE size{static_cast<LONG>(width + 2 * pad),
              static_cast<LONG>(height + 2 * pad)};
    POINT source{0, 0};
    BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
    UpdateLayeredWindow(hwnd_, screen, nullptr, &size, memory, &source, 0,
                        &blend, ULW_ALPHA);

    SelectObject(memory, previous);
    DeleteDC(memory);
    ReleaseDC(nullptr, screen);
  }

  // moving needs no redraw; inserting after the target keeps this window
  // directly beneath it
  SetWindowPos(hwnd_, target_, rect.left - static_cast<LONG>(pad),
               rect.top - static_cast<LONG>(pad), 0, 0,
               SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER |
                   SWP_SHOWWINDOW);
}
