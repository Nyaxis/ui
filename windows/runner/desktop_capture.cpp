#include "desktop_capture.h"

using Microsoft::WRL::ComPtr;

bool DesktopCapture::Start(ID3D11Device* device, HMONITOR monitor) {
  Stop();

  ComPtr<IDXGIDevice> dxgi_device;
  ComPtr<IDXGIAdapter> adapter;
  if (FAILED(device->QueryInterface(IID_PPV_ARGS(&dxgi_device))) ||
      FAILED(dxgi_device->GetAdapter(&adapter))) {
    return false;
  }

  ComPtr<IDXGIOutput> output;
  DXGI_OUTPUT_DESC output_desc{};
  for (UINT i = 0; adapter->EnumOutputs(i, &output) != DXGI_ERROR_NOT_FOUND;
       ++i) {
    if (SUCCEEDED(output->GetDesc(&output_desc)) &&
        output_desc.Monitor == monitor) {
      break;
    }
    output.Reset();
  }
  if (!output) {
    return false;
  }

  ComPtr<IDXGIOutput1> output1;
  if (FAILED(output.As(&output1)) ||
      FAILED(output1->DuplicateOutput(device, &duplication_))) {
    duplication_.Reset();
    return false;
  }

  DXGI_OUTDUPL_DESC duplication_desc{};
  duplication_->GetDesc(&duplication_desc);

  D3D11_TEXTURE2D_DESC texture_desc{};
  texture_desc.Width = duplication_desc.ModeDesc.Width;
  texture_desc.Height = duplication_desc.ModeDesc.Height;
  texture_desc.MipLevels = 1;
  texture_desc.ArraySize = 1;
  texture_desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  texture_desc.SampleDesc.Count = 1;
  texture_desc.Usage = D3D11_USAGE_DEFAULT;
  texture_desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
  if (FAILED(device->CreateTexture2D(&texture_desc, nullptr, &frame_))) {
    duplication_.Reset();
    return false;
  }

  device->GetImmediateContext(&context_);
  monitor_ = monitor;
  desktop_rect_ = output_desc.DesktopCoordinates;
  has_frame_ = false;
  return true;
}

void DesktopCapture::Stop() {
  duplication_.Reset();
  frame_.Reset();
  context_.Reset();
  monitor_ = nullptr;
  has_frame_ = false;
}

bool DesktopCapture::Update(UINT timeout_ms) {
  if (!duplication_) {
    return false;
  }

  DXGI_OUTDUPL_FRAME_INFO info{};
  ComPtr<IDXGIResource> resource;
  const HRESULT hr =
      duplication_->AcquireNextFrame(timeout_ms, &info, &resource);
  if (hr == DXGI_ERROR_WAIT_TIMEOUT) {
    return false;
  }
  if (FAILED(hr)) {
    Stop();
    return false;
  }

  // Pointer-only updates carry no new desktop image.
  bool changed = false;
  ComPtr<ID3D11Texture2D> image;
  if ((info.LastPresentTime.QuadPart != 0 || !has_frame_) &&
      SUCCEEDED(resource.As(&image))) {
    context_->CopyResource(frame_.Get(), image.Get());
    has_frame_ = true;
    changed = true;
  }
  duplication_->ReleaseFrame();
  return changed;
}
