#include "desktop_capture.h"

#include <unknwn.h>

#include <dxgi.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <winrt/Windows.Graphics.DirectX.h>

using Microsoft::WRL::ComPtr;

namespace capture = winrt::Windows::Graphics::Capture;
namespace directx = winrt::Windows::Graphics::DirectX;

struct DesktopCapture::Impl {
  directx::Direct3D11::IDirect3DDevice device{nullptr};
  capture::GraphicsCaptureItem item{nullptr};
  capture::Direct3D11CaptureFramePool pool{nullptr};
  capture::GraphicsCaptureSession session{nullptr};
};

DesktopCapture::DesktopCapture() = default;
DesktopCapture::~DesktopCapture() { Stop(); }

bool DesktopCapture::Start(ID3D11Device* device, HMONITOR monitor) {
  Stop();

  MONITORINFO monitor_info{sizeof(monitor_info)};
  if (!GetMonitorInfo(monitor, &monitor_info)) {
    return false;
  }

  auto impl = std::make_unique<Impl>();
  try {
    ComPtr<IDXGIDevice> dxgi_device;
    winrt::check_hresult(device->QueryInterface(IID_PPV_ARGS(&dxgi_device)));
    winrt::com_ptr<::IInspectable> inspectable;
    winrt::check_hresult(CreateDirect3D11DeviceFromDXGIDevice(
        dxgi_device.Get(), inspectable.put()));
    impl->device = inspectable.as<directx::Direct3D11::IDirect3DDevice>();

    auto interop = winrt::get_activation_factory<capture::GraphicsCaptureItem,
                                                 IGraphicsCaptureItemInterop>();
    winrt::check_hresult(interop->CreateForMonitor(
        monitor, winrt::guid_of<capture::GraphicsCaptureItem>(),
        winrt::put_abi(impl->item)));

    const auto size = impl->item.Size();
    impl->pool = capture::Direct3D11CaptureFramePool::CreateFreeThreaded(
        impl->device, directx::DirectXPixelFormat::B8G8R8A8UIntNormalized, 2,
        size);
    impl->session = impl->pool.CreateCaptureSession(impl->item);
    impl->session.IsCursorCaptureEnabled(false);
    try {
      // Needs borderless access, which Windows may refuse an unpackaged app;
      // the capture then just shows the system's capture border.
      impl->session.IsBorderRequired(false);
    } catch (const winrt::hresult_error&) {
    }

    D3D11_TEXTURE2D_DESC texture_desc{};
    texture_desc.Width = static_cast<UINT>(size.Width);
    texture_desc.Height = static_cast<UINT>(size.Height);
    texture_desc.MipLevels = 1;
    texture_desc.ArraySize = 1;
    texture_desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    texture_desc.SampleDesc.Count = 1;
    texture_desc.Usage = D3D11_USAGE_DEFAULT;
    texture_desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    winrt::check_hresult(device->CreateTexture2D(&texture_desc, nullptr, &frame_));

    impl->session.StartCapture();
  } catch (const winrt::hresult_error&) {
    frame_.Reset();
    return false;
  }

  device->GetImmediateContext(&context_);
  monitor_ = monitor;
  desktop_rect_ = monitor_info.rcMonitor;
  has_frame_ = false;
  impl_ = std::move(impl);
  return true;
}

void DesktopCapture::Stop() {
  if (impl_) {
    try {
      impl_->session.Close();
      impl_->pool.Close();
    } catch (const winrt::hresult_error&) {
    }
    impl_.reset();
  }
  frame_.Reset();
  context_.Reset();
  monitor_ = nullptr;
  has_frame_ = false;
}

bool DesktopCapture::Update() {
  if (!impl_) {
    return false;
  }

  try {
    // Only the newest frame matters; older ones are released unused.
    auto latest = impl_->pool.TryGetNextFrame();
    if (!latest) {
      return false;
    }
    while (auto next = impl_->pool.TryGetNextFrame()) {
      latest = next;
    }

    auto access = latest.Surface()
                      .as<::Windows::Graphics::DirectX::Direct3D11::
                              IDirect3DDxgiInterfaceAccess>();
    ComPtr<ID3D11Texture2D> image;
    winrt::check_hresult(access->GetInterface(IID_PPV_ARGS(&image)));

    D3D11_TEXTURE2D_DESC image_desc{};
    D3D11_TEXTURE2D_DESC frame_desc{};
    image->GetDesc(&image_desc);
    frame_->GetDesc(&frame_desc);
    if (image_desc.Width != frame_desc.Width ||
        image_desc.Height != frame_desc.Height) {
      // Display mode changed; start over at the new size.
      Stop();
      return false;
    }
    context_->CopyResource(frame_.Get(), image.Get());
    has_frame_ = true;
    return true;
  } catch (const winrt::hresult_error&) {
    Stop();
    return false;
  }
}
