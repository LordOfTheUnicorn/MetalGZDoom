#pragma once

#include "metal/textures/ml_samplers.h"
#include "metal/textures/ml_hwtexture.h"
#include "hwrenderer/postprocessing/hw_postprocess.h"
#include <QuartzCore/QuartzCore.h>

namespace MetalRenderer
{

class MlHardwareTexture;

class MlRenderBuffers
{
public:
    MlRenderBuffers();
    ~MlRenderBuffers();

    void BeginFrame(int width, int height, int sceneWidth, int sceneHeight);

    int GetWidth() const { return mWidth; }
    int GetHeight() const { return mHeight; }
    int GetSceneWidth() const { return mSceneWidth; }
    int GetSceneHeight() const { return mSceneHeight; }
    int GetSceneSamples() const { return mSamples; }
    int & CurrentEye() { return mCurrentEye; }
    int NextEye(int eyeCount) {raise(SIGTRAP);};
    void Setup(int width, int height, int sceneWidth, int sceneHeight);
    void BindDitherTexture(int texunit);
    id<MTLTexture> CreateRenderBuffer(const char *name, MTLPixelFormat format, int width, int height, const void* data = nullptr);
    id<MTLTexture> CreateDepthTexture(const char *name, MTLPixelFormat format, int width, int height, int samples, bool fixedSampleLocations);
    void ClearScene();
    
    id<MTLTexture> SceneColor;
    id<MTLDepthStencilState> SceneDepthStencil;
    id<MTLTexture> SceneNormal;
    id<MTLTexture> SceneFog;

    void BlitSceneToTexture();
    //MTLRenderPassStencilAttachmentDescriptor SceneDepthStencilFormat = VK_FORMAT_D24_UNORM_S8_UINT;

    static const int NumPipelineImages = 2;
    id<MTLTexture> PipelineImage[NumPipelineImages];
    
    int mCurrentEye = 0;

    id<MTLTexture> Shadowmap;
   // MlSamplerManager ShadowmapSampler;
    // Buffers for the scene
    id<MTLTexture> mSceneMultisampleTex;
    id<MTLTexture> mSceneDepthStencilTex;
    id<MTLTexture> mSceneDepthTex;
    id<MTLTexture> mSceneFogTex;
    id<MTLTexture> mSceneNormalTex;
    id<MTLTexture> mSceneMultisampleBuf;
    id<MTLTexture> mSceneDepthStencilBuf;
    id<MTLTexture> mSceneFogBuf;
    id<MTLTexture> mSceneNormalBuf;
    id<MTLTexture> mSceneFB;
    id<CAMetalDrawable> mDrawable;
    id<MTLTexture> mSceneDataFB;
    bool mSceneUsesTextures = false;

private:
    void CreatePipeline(int width, int height);
    void CreateScene(int width, int height, int samples, bool needsSceneTextures);
    void CreateSceneColor(int width, int height);// VkSampleCountFlagBits samples);
    void CreateSceneDepthStencil(int width, int height);// VkSampleCountFlagBits samples);
    void CreateSceneFog(int width, int height) {};// VkSampleCountFlagBits samples);
    void CreateSceneNormal(int width, int height) {};// VkSampleCountFlagBits samples);
    void CreateShadowmap() {raise(SIGTRAP);};
    int  GetBestSampleCount() {raise(SIGTRAP);};
    id<MTLTexture> Create2DTexture(const char *name, MTLPixelFormat format, int width, int height, const void* data = nullptr);
    id<MTLTexture> Create2DMultisampleTexture(const char *name, MTLPixelFormat format, int width, int height, int samples, bool fixedSampleLocations);
    id<MTLTexture> CreateFrameBuffer(const char *name, id<MTLTexture> colorbuffer);

    int mWidth = 0;
    int mHeight = 0;
    int mSceneWidth = 0;
    int mSceneHeight = 0;
    int mSamples = 0;
    
    //id<MTLDevice> device;
    
    id<MTLTexture> mPipelineTexture[2];
    id<MTLTexture> mPipelineFB[2];
    
    bool                m_VsyncEnabled;
    bool                m_TripleBufferEnabled;
    id<MTLTexture>      m_DisplayBuffers[2];
    uint                m_CurrentBufferId;
    //id<CAMetalDrawable> m_Drawable;
    
    id<MTLTexture> mDitherTexture;
};

class MLPPRenderState : public PPRenderState
{
public:
    MLPPRenderState(MlRenderBuffers *buffers) : buffers(buffers) { }

    void PushGroup(const FString &name) override {raise(SIGTRAP);};
    void PopGroup() override {raise(SIGTRAP);};
    void Draw() override;

private:
    id<MTLTexture> *GetMLTexture(PPTexture *texture);
    //FShaderProgram *GetGLShader(PPShader *shader);

    MlRenderBuffers *buffers;
};
}
