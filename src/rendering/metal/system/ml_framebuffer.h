#pragma once

#import <Metal/Metal.h>

#include "gl_sysfb.h"
#include "metal/system/ml_buffer.h"
#include "metal/renderer/ml_streambuffer.h"
#include "metal/renderer/ml_renderer.h"

namespace MetalRenderer
{

class MlRenderer;

class MetalFrameBuffer : public SystemBaseFrameBuffer
{
    typedef SystemBaseFrameBuffer Super;
    
public:
    
    bool cur_vsync;
    bool needCreateRenderState : 1;
    MTLRenderPassDescriptor* renderPassDescriptor = nullptr;
    const NSUInteger maxBuffers = 3;
    id <MTLRenderPipelineState> piplineState;
    //id<MTLRenderCommandEncoder> renderCommandEncoder;
    
    MlDataBuffer *ViewpointUBO = nullptr;
    MlDataBuffer *LightBufferSSO = nullptr;
    MlStreamBuffer *MatrixBuffer = nullptr;
    MlStreamBuffer *StreamBuffer = nullptr;
    
    MlDataBuffer *LightNodes = nullptr;
    MlDataBuffer *LightLines = nullptr;
    MlDataBuffer *LightList = nullptr;
    
    int camtexcount = 0;
    
    MetalFrameBuffer(void *hMonitor, bool fullscreen);
    ~MetalFrameBuffer();
    
    void InitializeState() override;
    IDataBuffer *CreateDataBuffer(int bindingpoint, bool ssbo, bool needsresize) override;
    void Update() override;
    void Swap();
    IVertexBuffer *CreateVertexBuffer() override;
    IIndexBuffer *CreateIndexBuffer() override;
    id <MTLDevice> GetDevice()
    {
        return device;
    };

    void CleanForRestart() override;
    //void UpdatePalette() override;
    uint32_t GetCaps() override;
    //const char* DeviceName() const override;
    //void WriteSavePic(player_t *player, FileWriter *file, int width, int height) override;
    sector_t *RenderView(player_t *player) override;
    //void SetTextureFilterMode() override;
    IHardwareTexture *CreateHardwareTexture() override;
    //void PrecacheMaterial(FMaterial *mat, int translation) override;
    //FModelRenderer *CreateModelRenderer(int mli) override;
    //void TextureFilterChanged() override;
    void BeginFrame() override;
    //void SetViewportRects(IntRect *bounds) override;
    //void BlurScene(float amount) override;
    //IIndexBuffer *CreateIndexBuffer() override;

    //// Retrieves a buffer containing image data for a screenshot.
    //// Hint: Pitch can be negative for upside-down images, in which case buffer
    //// points to the last row in the buffer, which will be the first row output.
    //virtual TArray<uint8_t> GetScreenshotBuffer(int &pitch, ESSType &color_type, float &gamma) override;
    //
    void Draw2D() override;
    //void PostProcessScene(int fixedcm, const std::function<void()> &afterBloomDrawEndScene2D) override;
    //
    //FTexture *WipeStartScreen() override;
    //FTexture *WipeEndScreen() override;
    bool IsHWGammaActive() const { return HWGammaActive; }
    bool HWGammaActive = false;            // Are we using hardware or software gamma?
    
    void SetVSync(bool vsync);

    
};

inline MetalFrameBuffer *GetMetalFrameBuffer() { return static_cast<MetalFrameBuffer*>(screen); }
}
