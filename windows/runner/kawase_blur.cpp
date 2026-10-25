#include "kawase_blur.h"

#include <d3dcompiler.h>

#include <algorithm>
#include <cmath>

using Microsoft::WRL::ComPtr;

namespace {

constexpr int kMaxPasses = 8;

constexpr char kShaderSource[] = R"hlsl(
cbuffer Params : register(b0) {
  float2 halfpixel;
  float offset;
  float strength;
  float noise;
  float contrast;
  float brightness;
  float vibrancy;
  float use_blur;
  float3 pad;
};

Texture2D tex0 : register(t0);
Texture2D tex1 : register(t1);
SamplerState samp : register(s0);

struct VSOut {
  float4 pos : SV_Position;
  float2 uv : TEXCOORD0;
};

VSOut VS(uint id : SV_VertexID) {
  VSOut o;
  float2 uv = float2((id << 1) & 2, id & 2);
  o.pos = float4(uv * float2(2, -2) + float2(-1, 1), 0, 1);
  o.uv = uv;
  return o;
}

float4 DownTaps(Texture2D t, float2 uv) {
  float2 h = halfpixel * offset;
  float4 sum = t.Sample(samp, uv) * 4.0;
  sum += t.Sample(samp, uv - h);
  sum += t.Sample(samp, uv + h);
  sum += t.Sample(samp, uv + float2(h.x, -h.y));
  sum += t.Sample(samp, uv - float2(h.x, -h.y));
  return sum / 8.0;
}

float4 UpTaps(Texture2D t, float2 uv) {
  float2 h = halfpixel * offset;
  float4 sum = t.Sample(samp, uv + float2(-h.x * 2.0, 0.0));
  sum += t.Sample(samp, uv + float2(-h.x, h.y)) * 2.0;
  sum += t.Sample(samp, uv + float2(0.0, h.y * 2.0));
  sum += t.Sample(samp, uv + float2(h.x, h.y)) * 2.0;
  sum += t.Sample(samp, uv + float2(h.x * 2.0, 0.0));
  sum += t.Sample(samp, uv + float2(h.x, -h.y)) * 2.0;
  sum += t.Sample(samp, uv + float2(0.0, -h.y * 2.0));
  sum += t.Sample(samp, uv + float2(-h.x, -h.y)) * 2.0;
  return sum / 12.0;
}

float4 Down(VSOut i) : SV_Target { return DownTaps(tex0, i.uv); }

float4 Up(VSOut i) : SV_Target { return UpTaps(tex0, i.uv); }

float Hash(float2 p) {
  return frac(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

// tex0 = sharp backdrop, tex1 = smallest blurred level.
float4 Final(VSOut i) : SV_Target {
  float3 sharp = tex0.Sample(samp, i.uv).rgb;
  float3 c = sharp;
  if (use_blur > 0.5) {
    c = lerp(sharp, UpTaps(tex1, i.uv).rgb, strength);
  }
  float luma = dot(c, float3(0.2126, 0.7152, 0.0722));
  c = lerp(luma.xxx, c, 1.0 + vibrancy);
  c = (c - 0.5) * contrast + 0.5;
  c *= brightness;
  c += (Hash(i.pos.xy) - 0.5) * noise;
  return float4(saturate(c), 1.0);
}
)hlsl";

bool Near(float a, float b) { return std::fabs(a - b) < 1e-4f; }

ComPtr<ID3DBlob> Compile(const char* entry, const char* profile) {
  ComPtr<ID3DBlob> code;
  ComPtr<ID3DBlob> errors;
  const HRESULT hr =
      D3DCompile(kShaderSource, sizeof(kShaderSource) - 1, nullptr, nullptr,
                 nullptr, entry, profile, D3DCOMPILE_OPTIMIZATION_LEVEL3, 0,
                 &code, &errors);
  if (FAILED(hr)) {
    if (errors) {
      OutputDebugStringA(static_cast<const char*>(errors->GetBufferPointer()));
    }
    return nullptr;
  }
  return code;
}

}  // namespace

// Must match the `Params` cbuffer: three 16-byte rows.
struct KawaseBlur::Constants {
  float halfpixel[2];
  float offset;
  float strength;
  float noise;
  float contrast;
  float brightness;
  float vibrancy;
  float use_blur;
  float pad[3];
};

bool BlurParams::IsIdentity() const {
  return passes == 0 && Near(noise, 0.0f) && Near(contrast, 1.0f) &&
         Near(brightness, 1.0f) && Near(vibrancy, 0.0f);
}

bool KawaseBlur::Init(ID3D11Device* device) {
  device_ = device;

  const auto vs = Compile("VS", "vs_5_0");
  const auto down = Compile("Down", "ps_5_0");
  const auto up = Compile("Up", "ps_5_0");
  const auto final_pass = Compile("Final", "ps_5_0");
  if (!vs || !down || !up || !final_pass) {
    return false;
  }
  if (FAILED(device->CreateVertexShader(vs->GetBufferPointer(),
                                        vs->GetBufferSize(), nullptr,
                                        &vertex_shader_)) ||
      FAILED(device->CreatePixelShader(down->GetBufferPointer(),
                                       down->GetBufferSize(), nullptr,
                                       &down_shader_)) ||
      FAILED(device->CreatePixelShader(up->GetBufferPointer(),
                                       up->GetBufferSize(), nullptr,
                                       &up_shader_)) ||
      FAILED(device->CreatePixelShader(final_pass->GetBufferPointer(),
                                       final_pass->GetBufferSize(), nullptr,
                                       &final_shader_))) {
    return false;
  }

  D3D11_SAMPLER_DESC sampler{};
  sampler.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
  sampler.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP;
  sampler.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP;
  sampler.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
  if (FAILED(device->CreateSamplerState(&sampler, &sampler_))) {
    return false;
  }

  D3D11_BUFFER_DESC buffer{};
  buffer.ByteWidth = sizeof(Constants);
  buffer.Usage = D3D11_USAGE_DEFAULT;
  buffer.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
  return SUCCEEDED(device->CreateBuffer(&buffer, nullptr, &constants_));
}

void KawaseBlur::EnsureSource(ID3D11Texture2D* source) {
  if (source == source_.Get()) {
    return;
  }
  source_ = source;
  source_srv_.Reset();
  device_->CreateShaderResourceView(source, nullptr, &source_srv_);
}

void KawaseBlur::EnsureLevels(UINT width, UINT height, int passes) {
  if (width == levels_width_ && height == levels_height_ &&
      static_cast<size_t>(passes) == levels_.size()) {
    return;
  }
  levels_.clear();
  levels_width_ = width;
  levels_height_ = height;

  UINT level_width = width;
  UINT level_height = height;
  for (int i = 0; i < passes; ++i) {
    level_width = std::max<UINT>(1, level_width / 2);
    level_height = std::max<UINT>(1, level_height / 2);

    Level level;
    level.width = level_width;
    level.height = level_height;

    D3D11_TEXTURE2D_DESC desc{};
    desc.Width = level_width;
    desc.Height = level_height;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    if (FAILED(device_->CreateTexture2D(&desc, nullptr, &level.texture)) ||
        FAILED(device_->CreateShaderResourceView(level.texture.Get(), nullptr,
                                                 &level.srv)) ||
        FAILED(device_->CreateRenderTargetView(level.texture.Get(), nullptr,
                                               &level.rtv))) {
      levels_.clear();
      levels_width_ = 0;
      return;
    }
    levels_.push_back(std::move(level));
  }
}

void KawaseBlur::Draw(ID3D11DeviceContext* context,
                      ID3D11RenderTargetView* target, UINT width, UINT height,
                      ID3D11PixelShader* shader,
                      ID3D11ShaderResourceView* first,
                      ID3D11ShaderResourceView* second,
                      const Constants& constants) {
  context->UpdateSubresource(constants_.Get(), 0, nullptr, &constants, 0, 0);

  // Bind the target before the sources: a texture read by the previous pass
  // may be this pass's target.
  context->OMSetRenderTargets(1, &target, nullptr);
  const D3D11_VIEWPORT viewport = {0.0f, 0.0f, static_cast<float>(width),
                                   static_cast<float>(height), 0.0f, 1.0f};
  context->RSSetViewports(1, &viewport);
  context->PSSetShader(shader, nullptr, 0);
  ID3D11ShaderResourceView* sources[2] = {first, second};
  context->PSSetShaderResources(0, 2, sources);
  context->Draw(3, 0);

  ID3D11ShaderResourceView* none[2] = {nullptr, nullptr};
  context->PSSetShaderResources(0, 2, none);
}

void KawaseBlur::Render(ID3D11DeviceContext* context, ID3D11Texture2D* source,
                        ID3D11RenderTargetView* target, UINT width,
                        UINT height, const BlurParams& params) {
  if (!constants_ || !source) {
    return;
  }
  EnsureSource(source);
  if (!source_srv_) {
    return;
  }
  const int passes = std::clamp(params.passes, 0, kMaxPasses);
  EnsureLevels(width, height, passes);
  if (levels_.size() != static_cast<size_t>(passes)) {
    return;
  }

  context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  context->IASetInputLayout(nullptr);
  context->VSSetShader(vertex_shader_.Get(), nullptr, 0);
  context->PSSetSamplers(0, 1, sampler_.GetAddressOf());
  context->PSSetConstantBuffers(0, 1, constants_.GetAddressOf());
  context->OMSetBlendState(nullptr, nullptr, 0xffffffff);

  const float offset = std::max(0.0f, params.size);
  auto pass_constants = [&](UINT dest_width, UINT dest_height) {
    Constants c{};
    c.halfpixel[0] = 0.5f / static_cast<float>(dest_width);
    c.halfpixel[1] = 0.5f / static_cast<float>(dest_height);
    c.offset = offset;
    c.strength = std::clamp(params.strength, 0.0f, 1.0f);
    c.noise = params.noise;
    c.contrast = params.contrast;
    c.brightness = params.brightness;
    c.vibrancy = params.vibrancy;
    c.use_blur = passes > 0 ? 1.0f : 0.0f;
    return c;
  };

  // Down: source -> level 1 -> ... -> level N. The half-pixel is the
  // destination's, i.e. one texel of the finer source.
  for (int i = 0; i < passes; ++i) {
    ID3D11ShaderResourceView* from =
        i == 0 ? source_srv_.Get() : levels_[i - 1].srv.Get();
    const Level& to = levels_[i];
    Draw(context, to.rtv.Get(), to.width, to.height, down_shader_.Get(), from,
         nullptr, pass_constants(to.width, to.height));
  }

  // Up: level N -> ... -> level 1. The half-pixel is the smaller source's.
  for (int i = passes - 1; i >= 1; --i) {
    const Level& from = levels_[i];
    const Level& to = levels_[i - 1];
    Draw(context, to.rtv.Get(), to.width, to.height, up_shader_.Get(),
         from.srv.Get(), nullptr, pass_constants(from.width, from.height));
  }

  // Final: last upsample from level 1, mixed with the sharp backdrop.
  ID3D11ShaderResourceView* blurred =
      passes > 0 ? levels_[0].srv.Get() : nullptr;
  const UINT blurred_width = passes > 0 ? levels_[0].width : width;
  const UINT blurred_height = passes > 0 ? levels_[0].height : height;
  Draw(context, target, width, height, final_shader_.Get(), source_srv_.Get(),
       blurred, pass_constants(blurred_width, blurred_height));
}
