#ifndef RUNNER_KAWASE_BLUR_H_
#define RUNNER_KAWASE_BLUR_H_

#include <windows.h>

#include <d3d11.h>
#include <wrl/client.h>

#include <vector>

// Backdrop blur settings; names and defaults follow Hyprland's blur section.
struct BlurParams {
  float size = 8.0f;  // Kawase sample offset per pass
  int passes = 1;     // down/up levels, 0..8
  float strength = 1.0f;  // 0 = sharp backdrop, 1 = fully blurred
  float noise = 0.0117f;
  float contrast = 0.8916f;
  float brightness = 0.8172f;
  float vibrancy = 0.1696f;

  // True when rendering would reproduce the backdrop unchanged, so the
  // capture can be skipped and the plain transparent window used instead.
  bool IsIdentity() const;
};

// Dual Kawase blur (the algorithm Hyprland uses): `passes` downsamples, each
// halving the resolution, then upsamples back. The last upsample is folded
// into a final pass that also mixes in the sharp backdrop and applies
// vibrancy, contrast, brightness and noise.
class KawaseBlur {
 public:
  bool Init(ID3D11Device* device);

  // Blurs |source| (BGRA, shader-resource) into |target|; both |width| x
  // |height|.
  void Render(ID3D11DeviceContext* context, ID3D11Texture2D* source,
              ID3D11RenderTargetView* target, UINT width, UINT height,
              const BlurParams& params);

 private:
  struct Level {
    Microsoft::WRL::ComPtr<ID3D11Texture2D> texture;
    Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> srv;
    Microsoft::WRL::ComPtr<ID3D11RenderTargetView> rtv;
    UINT width = 0;
    UINT height = 0;
  };

  struct Constants;

  void EnsureSource(ID3D11Texture2D* source);
  void EnsureLevels(UINT width, UINT height, int passes);
  void Draw(ID3D11DeviceContext* context, ID3D11RenderTargetView* target,
            UINT width, UINT height, ID3D11PixelShader* shader,
            ID3D11ShaderResourceView* first, ID3D11ShaderResourceView* second,
            const Constants& constants);

  Microsoft::WRL::ComPtr<ID3D11Device> device_;
  Microsoft::WRL::ComPtr<ID3D11VertexShader> vertex_shader_;
  Microsoft::WRL::ComPtr<ID3D11PixelShader> down_shader_;
  Microsoft::WRL::ComPtr<ID3D11PixelShader> up_shader_;
  Microsoft::WRL::ComPtr<ID3D11PixelShader> final_shader_;
  Microsoft::WRL::ComPtr<ID3D11SamplerState> sampler_;
  Microsoft::WRL::ComPtr<ID3D11Buffer> constants_;

  Microsoft::WRL::ComPtr<ID3D11Texture2D> source_;
  Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> source_srv_;

  // levels_[i] is the (i + 1)th downsample.
  std::vector<Level> levels_;
  UINT levels_width_ = 0;
  UINT levels_height_ = 0;
};

#endif  // RUNNER_KAWASE_BLUR_H_
