#include "ml_framebuffer.h"

#include "v_video.h"
#include "r_videoscale.h"

#include "hwrenderer/data/flatvertices.h"
#include "hwrenderer/scene/hw_skydome.h"
#include "hwrenderer/data/hw_viewpointbuffer.h"
#include "hwrenderer/dynlights/hw_lightbuffer.h"
#include "hwrenderer/data/shaderuniforms.h"
#include "hwrenderer/utility/hw_clock.h"
#include "hwrenderer/utility/hw_vrmodes.h"
#include "hwrenderer/models/hw_models.h"

#include "metal/system/ml_buffer.h"
#include "metal/renderer/ml_renderer.h"
#include "metal/renderer/ml_renderstate.h"

void Draw2D(F2DDrawer *drawer, FRenderState &state);
MetalCocoaView* GetMacWindow();

namespace MetalRenderer
{
//void Draw2D(F2DDrawer *drawer, FRenderState &state);

MetalFrameBuffer::MetalFrameBuffer(void *hMonitor, bool fullscreen) :
    Super(hMonitor, false)
{
    //semaphore = dispatch_semaphore_create(maxBuffers);
    needCreateRenderState = true;
}

MetalFrameBuffer::~MetalFrameBuffer()
{
    if (mSkyData != nullptr)
        delete mSkyData;
    //[device release];
}

void MetalFrameBuffer::Draw2D()
{
    if (MLRenderer != nullptr)
    {
        ::Draw2D(&m2DDrawer, ml_RenderState);
    }
}

void MetalFrameBuffer::BeginFrame()
{
    SetViewportRects(nullptr);
    if (MLRenderer != nullptr)
    {
        MLRenderer->BeginFrame();
        MetalCocoaView* const window = GetMacWindow();
        MLRenderer->mScreenBuffers->mDrawable = [window getDrawable];
        
        if (true)
        {
            renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
            if (MLRenderer->mScreenBuffers)
            {
                MLRenderer->mScreenBuffers->mSceneFB = MLRenderer->mScreenBuffers->mDrawable.texture;
                
                // Color render target
                renderPassDescriptor.colorAttachments[0].texture = MLRenderer->mScreenBuffers->mDrawable.texture;
                renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
                renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionDontCare;
                // Depth render target
                renderPassDescriptor.depthAttachment.texture = MLRenderer->mScreenBuffers->mSceneDepthStencilTex;
                renderPassDescriptor.stencilAttachment.texture = MLRenderer->mScreenBuffers->mSceneDepthStencilTex;
            }
            
            renderPassDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
            renderPassDescriptor.depthAttachment.clearDepth = 1.f;
            //renderPassDescriptor.stencilAttachment.loadAction = MTLLoadActionClear;
            //renderPassDescriptor.stencilAttachment.clearStencil = 0.f;
            auto fb = GetMetalFrameBuffer();
            
            renderPassDescriptor.renderTargetWidth = 1440;//fb->GetClientWidth();
            renderPassDescriptor.renderTargetHeight = 900;//fb->GetClientHeight();
            renderPassDescriptor.defaultRasterSampleCount = 1;
            //float* val = (float*)malloc(40000000);
            //ml_RenderState.mtl_vertexBuffer = [device newBufferWithBytes:val length:sizeof(*val) options:MTLResourceStorageModeShared];
            //free(val);
            needCreateRenderState = false;
        }
        ml_RenderState.CreateRenderState(renderPassDescriptor);
        
    }
}

IHardwareTexture *MetalFrameBuffer::CreateHardwareTexture()
{
    return new MlHardwareTexture();
}

sector_t *MetalFrameBuffer::RenderView(player_t *player)
{
    if (MLRenderer != nullptr)
        return MLRenderer->RenderView(player);
    return nullptr;
}

void MetalFrameBuffer::InitializeState()
{
   
    SetViewportRects(nullptr);

    mVertexData = new FFlatVertexBuffer(GetWidth(), GetHeight());
    mSkyData = new FSkyVertexBuffer;
    mViewpoints = new HWViewpointBuffer;
    mLights = new FLightBuffer();

    MLRenderer = new MlRenderer(this);
    MLRenderer->Initialize(GetWidth(), GetHeight(),this->GetDevice());
    
    //static_cast<MlDataBuffer*>(mLights->GetBuffer())->BindBase();
}

IVertexBuffer *MetalFrameBuffer::CreateVertexBuffer()
{
    return new MlVertexBuffer();
}

IIndexBuffer *MetalFrameBuffer::CreateIndexBuffer()
{
    return new MlIndexBuffer();
}

void MetalFrameBuffer::SetVSync(bool vsync)
{
    cur_vsync = vsync;
}

IDataBuffer *MetalFrameBuffer::CreateDataBuffer(int bindingpoint, bool ssbo, bool needsresize)
{
    auto buffer = new MlDataBuffer();

    //auto fb = GetVulkanFrameBuffer();
    switch (bindingpoint)
    {
    case LIGHTBUF_BINDINGPOINT: LightBufferSSO = buffer; break;
    case VIEWPOINT_BINDINGPOINT: ViewpointUBO = buffer; break;
    case LIGHTNODES_BINDINGPOINT: LightNodes = buffer; break;
    case LIGHTLINES_BINDINGPOINT: LightLines = buffer; break;
    case LIGHTLIST_BINDINGPOINT: LightList = buffer; break;
    case POSTPROCESS_BINDINGPOINT: break;
    default: break;
    }

    return buffer;
}

void MetalFrameBuffer::Swap()
{
    //bool swapbefore = gl_finishbeforeswap && camtexcount == 0;
    Finish.Reset();
    Finish.Clock();
    //ml_RenderState.
    FPSLimit();
    //SwapBuffers();
    //if (!swapbefore) glFinish();
    Finish.Unclock();
    camtexcount = 0;
    //FHardwareTexture::UnbindAll();
    //mDebug->Update();
}

void MetalFrameBuffer::Update()
{
    twoD.Reset();
    Flush3D.Reset();

    Flush3D.Clock();
    MLRenderer->Flush();
    Flush3D.Unclock();
    Swap();
    ml_RenderState.EndFrame();
    Super::Update();
}

}
