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
        for (int i = 0; i < 6; i++)
        {
            aPosition[i] = {m2DDrawer.mVertices[i].x,m2DDrawer.mVertices[i].y,m2DDrawer.mVertices[i].z, 1};
            aColor[i] = {(float)m2DDrawer.mVertices[i].color0.b,
                              (float)m2DDrawer.mVertices[i].color0.g,
                              (float)m2DDrawer.mVertices[i].color0.r,
                              (float)m2DDrawer.mVertices[i].color0.a};
            aTexCoord[i] = {m2DDrawer.mVertices[i].u,m2DDrawer.mVertices[i].v};
        }
        
        //BGRA
        aColor[0] = aColor[1] = aColor[2] = aColor[3] = aColor[4] = aColor[5] = {0,0,0,255.f};
        [ml_RenderState.renderCommandEncoder setVertexBytes:&aPosition[0] length:sizeof(vector_float4) * 6 atIndex:0];
        [ml_RenderState.renderCommandEncoder setVertexBytes:&aTexCoord[0] length:sizeof(vector_float2) * 6 atIndex:1];
        [ml_RenderState.renderCommandEncoder setVertexBytes:&aColor[0]    length:sizeof(vector_float4) * 6 atIndex:2];
        
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
        
        MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
        if (MLRenderer->mScreenBuffers)
        {
            MLRenderer->mScreenBuffers->mSceneFB = MLRenderer->mScreenBuffers->mDrawable.texture;
            
            // Color render target
            renderPassDescriptor.colorAttachments[0].texture = MLRenderer->mScreenBuffers->mDrawable.texture;
            renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionLoad;
            //renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;

            // Depth render target
            renderPassDescriptor.depthAttachment.texture = MLRenderer->mScreenBuffers->mSceneDepthStencilTex;
            renderPassDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
            renderPassDescriptor.depthAttachment.clearDepth = 1.f;
            
            // Stencil render target
            renderPassDescriptor.stencilAttachment.texture = MLRenderer->mScreenBuffers->mSceneDepthStencilTex;
            renderPassDescriptor.stencilAttachment.loadAction = MTLLoadActionClear;
            renderPassDescriptor.stencilAttachment.clearStencil = 0.f;
        }
        auto fb = GetMetalFrameBuffer();
        
        renderPassDescriptor.renderTargetWidth = fb->GetClientWidth();
        renderPassDescriptor.renderTargetHeight = fb->GetClientHeight();
        renderPassDescriptor.defaultRasterSampleCount = 1;
    
        ml_RenderState.CreateRenderState(renderPassDescriptor);
        //ml_RenderState.commandBuffer = [ml_RenderState.commandQueue commandBuffer];
       // ml_RenderState.renderCommandEncoder = [ml_RenderState.commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
       // ml_RenderState.renderCommandEncoder.label = @"renderCommandEncoder";
       // [ml_RenderState.renderCommandEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
       // [ml_RenderState.renderCommandEncoder setCullMode:MTLCullModeBack];
       //
       // if (ml_RenderState.activeShader == nullptr)
       // {
       //     ml_RenderState.activeShader = new MlShader();
       //     ml_RenderState.activeShader->Load();
       // }
       //
       //
       // [ml_RenderState.renderCommandEncoder setRenderPipelineState:ml_RenderState.activeShader->pipelineState];
       // [ml_RenderState.renderCommandEncoder setDepthStencilState:ml_RenderState.activeShader->depthState];
    
        //[renderPassDescriptor release];
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
