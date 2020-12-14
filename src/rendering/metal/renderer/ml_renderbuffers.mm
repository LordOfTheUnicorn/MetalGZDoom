#include "ml_renderbuffers.h"
#include "metal/system/ml_framebuffer.h"
#include "hwrenderer/utility/hw_cvars.h"
#include "metal/renderer/ml_renderstate.h"
#import <Metal/Metal.h>

MetalCocoaView* GetMacWindow();

namespace MetalRenderer
{


MlRenderBuffers::MlRenderBuffers()
{
    mDrawable = nil;
}

MlRenderBuffers::~MlRenderBuffers()
{
    [mSceneMultisampleTex release];
    [mSceneDepthStencilTex release];
    [mSceneFogTex release];
    [mSceneNormalTex release];
    [mSceneMultisampleBuf release];
    [mSceneDepthStencilBuf release];
    [mSceneFogBuf release];
    [mSceneNormalBuf release];
    [mSceneFB release];
    [mSceneDataFB release];
    [PipelineImage[0] release];
    [PipelineImage[1] release];
    [mDitherTexture release];
}

void MlRenderBuffers::BeginFrame(int width, int height, int sceneWidth, int sceneHeight)
{
    
}

void MlRenderBuffers::CreatePipeline(int width, int height)
{
    auto fb = GetMetalFrameBuffer();

    for (int i = 0; i < NumPipelineImages; i++)
    {
        MTLTextureDescriptor *desc = [MTLTextureDescriptor new];
        desc.width = fb->GetClientWidth();
        desc.height = fb->GetClientHeight();
        desc.pixelFormat = MTLPixelFormatRGBA16Float;//MTLPixelFormatRGBA16Float;
        desc.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
        PipelineImage[i] = [device newTextureWithDescriptor:desc];
        
        [desc release];
    }
}

void MlRenderBuffers::BindDitherTexture(int texunit)
{
    if (!mDitherTexture)
    {
        static const float data[64] =
        {
             .0078125, .2578125, .1328125, .3828125, .0234375, .2734375, .1484375, .3984375,
             .7578125, .5078125, .8828125, .6328125, .7734375, .5234375, .8984375, .6484375,
             .0703125, .3203125, .1953125, .4453125, .0859375, .3359375, .2109375, .4609375,
             .8203125, .5703125, .9453125, .6953125, .8359375, .5859375, .9609375, .7109375,
             .0390625, .2890625, .1640625, .4140625, .0546875, .3046875, .1796875, .4296875,
             .7890625, .5390625, .9140625, .6640625, .8046875, .5546875, .9296875, .6796875,
             .1015625, .3515625, .2265625, .4765625, .1171875, .3671875, .2421875, .4921875,
             .8515625, .6015625, .9765625, .7265625, .8671875, .6171875, .9921875, .7421875,
        };
        //mDitherTexture = Create2DTexture("DitherTexture", MTLPixelFormatRG32Float, 8, 8, data);
        
        MTLTextureDescriptor *desc = [MTLTextureDescriptor new];
        desc.width = 8;
        desc.height = 8;
        desc.pixelFormat = MTLPixelFormatRG32Float;
        //desc.storageMode = MTLStorageModePrivate;
        desc.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
        
        mDitherTexture = [device newTextureWithDescriptor:desc];
        
        [desc release];
        
        MTLRegion region = MTLRegionMake2D(0, 0, 8, 8);
        [mDitherTexture replaceRegion:region mipmapLevel:0 withBytes:data bytesPerRow:(8*8)];
    }
    MLRenderer->mSamplerManager->SetRepeatAddressMode(true);
}

id<MTLTexture> MlRenderBuffers::Create2DTexture(const char *name, MTLPixelFormat format, int width, int height, const void* data /*= nullptr*/)
{
    MTLTextureDescriptor *desc = [MTLTextureDescriptor new];
    desc.width = width;
    desc.height = height;
    desc.pixelFormat = format;
    desc.storageMode = MTLStorageModePrivate;
    desc.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
   
    id<MTLTexture> dummy = [device newTextureWithDescriptor:desc];
    
    [desc release];
    return dummy;
}

id<MTLTexture> MlRenderBuffers::Create2DMultisampleTexture(const char *name, MTLPixelFormat format, int width, int height, int samples, bool fixedSampleLocations)
{
    MTLTextureDescriptor *desc = [MTLTextureDescriptor new];
    desc.width = width;
    desc.height = height;
    desc.pixelFormat = format;
    desc.storageMode = MTLStorageModePrivate;
    desc.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
    desc.textureType = MTLTextureType2DMultisample;
    desc.sampleCount = samples;
    
   // printf(name);
   // printf(" is created(Create2DMultisampleTexture)\n");
    id<MTLTexture> dummy = [device newTextureWithDescriptor:desc];
    [desc release];
    return dummy;
}

id<MTLTexture> MlRenderBuffers::CreateFrameBuffer(const char *name, id<MTLTexture> colorbuffer)
{
    MTLTextureDescriptor *desc = [MTLTextureDescriptor new];
    desc.usage = MTLTextureUsageRenderTarget;
    desc.storageMode = MTLStorageModePrivate;
       
    id<MTLTexture> dummy = [device newTextureWithDescriptor:desc];
    [desc release];
    return dummy;
}

static id<MTLTexture> CreateRenderBuffer(const char *name, int width, int height, const void* data /* = nullptr */)
{
    MTLTextureDescriptor *desc = [MTLTextureDescriptor new];
    desc.width = width;
    desc.height = height;
    desc.textureType = MTLTextureType2D;
    desc.storageMode = MTLStorageModePrivate;
    desc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    desc.pixelFormat = MTLPixelFormatRGBA16Float;
    
    id<MTLTexture> dummy = [device newTextureWithDescriptor:desc];
    [desc release];
    return dummy;
}

id<MTLTexture> MlRenderBuffers::CreateDepthTexture(const char *name, MTLPixelFormat format, int width, int height, int samples, bool fixedSampleLocations)
{
    MTLTextureDescriptor *desc = [MTLTextureDescriptor new];
    desc.width = width;
    desc.height = height;
    desc.pixelFormat = format;
    desc.storageMode = MTLStorageModePrivate;
    desc.usage = MTLTextureUsageRenderTarget;
    desc.textureType = MTLTextureType2D;
    
    id<MTLTexture> dummy = [device newTextureWithDescriptor:desc];
    [desc release];
    return dummy;
}

void MlRenderBuffers::ClearScene()
{
    //if (mSceneFB)

    //    [mSceneFB release];
    //if (mSceneDataFB)
    //    [mSceneDataFB release];
    //
    //if (mSceneUsesTextures)
    //{
    //    [mSceneMultisampleTex release];
    //    [mSceneFogTex release];
    //    [mSceneNormalTex release];
    //    [mSceneDepthStencilTex release];
    //}
    //else
    //{
    //    [mSceneMultisampleBuf release];
    //    [mSceneFogBuf release];
    //    [mSceneNormalBuf release];
    //    [mSceneDepthStencilBuf release];
    //}
}

void MlRenderBuffers::CreateScene(int width, int height, int samples, bool needsSceneTextures)
{
    ClearScene();

      //  if (samples > 1)
      //  {
      //      if (needsSceneTextures)
      //      {
      //          mSceneMultisampleTex = Create2DMultisampleTexture("SceneMultisample", MTLPixelFormatRGBA16Float, width, height, samples, false);
      //          //need GL_RGBA8
      //          mSceneDepthStencilTex = Create2DMultisampleTexture("SceneDepthStencil", MTLPixelFormatRGBA16Float, width, height, samples, false);
      //          mSceneFogTex = Create2DMultisampleTexture("SceneFog", MTLPixelFormatRGBA16Float, width, height, samples, false);
      //          mSceneNormalTex = Create2DMultisampleTexture("SceneNormal", MTLPixelFormatRGB10A2Unorm, width, height, samples, false);
      //         // mSceneFB = CreateFrameBuffer("SceneFB", mSceneMultisampleTex, {}, {}, mSceneDepthStencilTex, true);
      //         // mSceneDataFB = CreateFrameBuffer("SceneGBufferFB", mSceneMultisampleTex, mSceneFogTex, mSceneNormalTex, mSceneDepthStencilTex, true);
      //      }
      //      //else
      //      //{
      //      //    mSceneMultisampleBuf = CreateRenderBuffer("SceneMultisample", GL_RGBA16F, width, height, samples);
      //      //    mSceneDepthStencilBuf = CreateRenderBuffer("SceneDepthStencil", GL_DEPTH24_STENCIL8, width, height, samples);
      //      //    mSceneFB = CreateFrameBuffer("SceneFB", mSceneMultisampleBuf, mSceneDepthStencilBuf);
      //      //    mSceneDataFB = CreateFrameBuffer("SceneGBufferFB", mSceneMultisampleBuf, mSceneDepthStencilBuf);
      //      //}
      //  }
      //  else
      //  {
      //      //if (needsSceneTextures)
      //      //{
      //      //    mSceneDepthStencilTex = Create2DTexture("SceneDepthStencil", GL_DEPTH24_STENCIL8, width, height);
      //      //    mSceneFogTex = Create2DTexture("SceneFog", GL_RGBA8, width, height);
      //      //    mSceneNormalTex = Create2DTexture("SceneNormal", GL_RGB10_A2, width, height);
      //      //    mSceneFB = CreateFrameBuffer("SceneFB", mPipelineTexture[0], {}, {}, mSceneDepthStencilTex, false);
      //      //    mSceneDataFB = CreateFrameBuffer("SceneGBufferFB", mPipelineTexture[0], mSceneFogTex, mSceneNormalTex, mSceneDepthStencilTex, false);
      //      //}
      //      //else
      //      //{
      //      //    mSceneDepthStencilBuf = CreateRenderBuffer("SceneDepthStencil", GL_DEPTH24_STENCIL8, width, height);
      //      //    mSceneFB = CreateFrameBuffer("SceneFB", mPipelineTexture[0], mSceneDepthStencilBuf);
      //      //    mSceneDataFB = CreateFrameBuffer("SceneGBufferFB", mPipelineTexture[0], mSceneDepthStencilBuf);
      //      //}
      //  }
    //}
    
    auto fb = GetMetalFrameBuffer();
    
    //mSceneDepthStencilTex = CreateRenderBuffer("SceneDepthStencil", MTLPixelFormatDepth32Float_Stencil8, fb->GetClientWidth(), fb->GetClientHeight());
    mSceneDepthStencilTex = CreateDepthTexture("mSceneDepthTex", MTLPixelFormatDepth32Float_Stencil8, fb->GetClientWidth(), fb->GetClientHeight(), 0, 0);
    mSceneFogTex = Create2DTexture("SceneFog", MTLPixelFormatRGBA8Unorm, width, height);
    mSceneNormalTex = Create2DTexture("SceneNormal", MTLPixelFormatRGB10A2Unorm, width, height);
    mSceneDepthStencilBuf = Create2DTexture("SceneDepthStencil", MTLPixelFormatDepth32Float_Stencil8, width, height);
    MetalCocoaView* const window = GetMacWindow();
    mSceneDataFB = Create2DTexture("SceneGBufferFB", MTLPixelFormatRGBA8Unorm, width, height);
}

void MlRenderBuffers::CreateSceneColor(int width, int height)//, VkSampleCountFlagBits samples)
{
    //auto fb = GetVulkanFrameBuffer();

    MTLTextureDescriptor *desc = [MTLTextureDescriptor new];
    desc.width = width;
    desc.height = height;
    desc.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    [SceneColor newTextureWithDescriptor:desc];
    
    [desc release];
}

void MlRenderBuffers::CreateSceneDepthStencil(int width, int height)//, VkSampleCountFlagBits samples)
{
    MTLDepthStencilDescriptor *desc = [MTLDepthStencilDescriptor new];
    desc.depthCompareFunction = MTLCompareFunctionLess;
    desc.depthWriteEnabled = YES;
    desc.frontFaceStencil.stencilCompareFunction = MTLCompareFunctionAlways;
    desc.backFaceStencil.stencilCompareFunction = MTLCompareFunctionAlways;
    
    
    [SceneDepthStencil newDepthStencilStateWithDescriptor:desc];
    
    [desc release];
}

void MlRenderBuffers::Setup(int width, int height, int sceneWidth, int sceneHeight)
{
    if (width <= 0 || height <= 0)
        I_FatalError("Requested invalid render buffer sizes: screen = %dx%d", width, height);

    int samples = 1;//clamp((int)gl_multisample, 0, mMaxSamples); mMaxSamples = 16;
    bool needsSceneTextures = false;//(gl_ssao != 0);

    if (width != mWidth || height != mHeight)
        CreatePipeline(width, height);

    if (width != mWidth || height != mHeight || mSamples != samples || mSceneUsesTextures != needsSceneTextures)
        CreateScene(width, height, samples, needsSceneTextures);

    auto fb = GetMetalFrameBuffer();
    
    mWidth = width;
    mHeight = height;
    mSamples = samples;
    mSceneUsesTextures = needsSceneTextures;
    mSceneWidth = sceneWidth;
    mSceneHeight = sceneHeight;


    if (/*FailedCreate*/0)
    {
        [mSceneDepthStencilTex release];
        [mSceneFogTex release];
        [mSceneNormalTex release];
        
        for (int i = 0; i < NumPipelineImages; i++)
            [PipelineImage[i] release];
        
        mWidth = 0;
        mHeight = 0;
        mSamples = 0;
        mSceneWidth = 0;
        mSceneHeight = 0;
        I_FatalError("Unable to create render buffers.");
    }
}

void MLPPRenderState::Draw()
{
    raise(SIGTRAP);
}


}
