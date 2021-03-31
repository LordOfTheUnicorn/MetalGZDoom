//
//---------------------------------------------------------------------------
//
// Copyright(C) 2020-2021 Eugene Grigorchuk
// All rights reserved.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with this program.  If not, see http://www.gnu.org/licenses/
//
//--------------------------------------------------------------------------
//

#include "ml_framebuffer.h"
#include "r_videoscale.h"

#include "hwrenderer/data/flatvertices.h"
#include "hwrenderer/scene/hw_skydome.h"
#include "hwrenderer/data/hw_viewpointbuffer.h"
#include "hwrenderer/dynlights/hw_lightbuffer.h"
#include "hwrenderer/data/shaderuniforms.h"
#include "hwrenderer/utility/hw_clock.h"
#include "hwrenderer/utility/hw_vrmodes.h"
#include "hwrenderer/models/hw_models.h"
#include "hwrenderer/utility/hw_cvars.h"

#include "metal/system/ml_buffer.h"
#include "metal/renderer/ml_renderer.h"
#include "metal/renderer/ml_renderstate.h"
#include "metal/renderer/ml_renderbuffers.h"

#include "v_text.h"

EXTERN_CVAR(Bool, r_drawvoxels)
EXTERN_CVAR(Int, gl_tonemap)
void Draw2D(F2DDrawer *drawer, FRenderState &state);
//MetalCocoaView* GetMacWindow();

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
        ::Draw2D(&m2DDrawer, *(MLRenderer->ml_RenderState));
    }
}

void MetalFrameBuffer::BeginFrame()
{
    SetViewportRects(nullptr);
    if (MLRenderer != nullptr)
    {
        //dispatch_semaphore_wait(MLRenderer->semaphore, DISPATCH_TIME_FOREVER);
        MLRenderer->BeginFrame();
        //printf("Begin Frame !\n");
        if (true)
        {
            renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
            @autoreleasepool
            {
            if (MLRenderer->mScreenBuffers)
            {
                if (MLRenderer->mScreenBuffers->mSceneFB == nil)
                {
                    MTLTextureDescriptor *desc = [MTLTextureDescriptor new];
                    desc.width  = GetMetalFrameBuffer()->GetClientWidth();
                    desc.height = GetMetalFrameBuffer()->GetClientHeight();
                    desc.pixelFormat = MTLPixelFormatRGBA16Float;
                    desc.storageMode = MTLStorageModePrivate;
                    desc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
                    desc.textureType = MTLTextureType2D;

                    MLRenderer->mScreenBuffers->mSceneFB = [device newTextureWithDescriptor:desc];
                    [desc release];
                }
                
                renderPassDescriptor.colorAttachments[0].texture = MLRenderer->mScreenBuffers->mSceneFB;
                
                // Color render target
                renderPassDescriptor.colorAttachments[0].loadAction  = MTLLoadActionClear;
                renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
                
                // Depth render target
                renderPassDescriptor.depthAttachment.texture = MLRenderer->mScreenBuffers->mSceneDepthStencilTex;
                renderPassDescriptor.stencilAttachment.texture = MLRenderer->mScreenBuffers->mSceneDepthStencilTex;
            }
            
            renderPassDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
            renderPassDescriptor.depthAttachment.clearDepth = 1.f;
            renderPassDescriptor.stencilAttachment.loadAction = MTLLoadActionClear;
            renderPassDescriptor.stencilAttachment.clearStencil = 0.f;
            auto fb = GetMetalFrameBuffer();
            
            auto val1 = fb->GetClientWidth();
            auto val2 = fb->GetClientHeight();
            
            renderPassDescriptor.renderTargetWidth = GetMetalFrameBuffer()->GetClientWidth();
            renderPassDescriptor.renderTargetHeight = GetMetalFrameBuffer()->GetClientHeight();
            renderPassDescriptor.defaultRasterSampleCount = 1;
    
            needCreateRenderState = false;
        }
        }
        
        MLRenderer->ml_RenderState->CreateRenderState(renderPassDescriptor);
    }
}

IHardwareTexture *MetalFrameBuffer::CreateHardwareTexture()
{
    return new MTLHardwareTexture();
}

sector_t *MetalFrameBuffer::RenderView(player_t *player)
{
    if (MLRenderer != nullptr)
        return MLRenderer->RenderView(player);
    return nullptr;
}

//void MetalFrameBuffer::PrecacheMaterial(FMaterial *mat, int translation)
//{
//    auto tex = mat->tex;
//    if (tex->isSWCanvas()) return;
//
//    // Textures that are already scaled in the texture lump will not get replaced by hires textures.
//    int flags = mat->isExpanded() ? CTF_Expand : (gl_texture_usehires && !tex->isScaled()) ? CTF_CheckHires : 0;
//    int numLayers = mat->GetLayers();
//    auto base = static_cast<MTLHardwareTexture*>(mat->GetLayer(0, translation));
//
//    if (base->BindOrCreate(tex, 0, CLAMP_NONE, translation, flags, nullptr))
//    {
//        for (int i = 1; i < numLayers; i++)
//        {
//            FTexture *layer;
//            auto systex = static_cast<MTLHardwareTexture*>(mat->GetLayer(i, 0, &layer));
//            systex->BindOrCreate(layer, i, CLAMP_NONE, 0, mat->isExpanded() ? CTF_Expand : 0, nullptr);
//        }
//    }
//    // unbind everything.
//    //MTLHardwareTexture::UnbindAll();
//}

void MetalFrameBuffer::InitializeState()
{
   
    SetViewportRects(nullptr);

    mVertexData = new FFlatVertexBuffer(GetWidth(), GetHeight());
    mSkyData = new FSkyVertexBuffer;
    mViewpoints = new HWViewpointBuffer;
    mLights = new FLightBuffer();

    MLRenderer = new MTLRenderer(this);
    MLRenderer->Initialize(GetWidth(), GetHeight(),this->GetDevice());
    
    static bool first = true;
    if (first)
    {
        Printf("Metal device:" TEXTCOLOR_ORANGE " %s\n",[[MLRenderer->framebuffer->GetDevice() name] UTF8String]);
        FString deviceType = "";
        if ([MLRenderer->framebuffer->GetDevice() isRemovable]) deviceType += "removable";
        if (!deviceType.IsEmpty()) deviceType += ", ";
        if ([MLRenderer->framebuffer->GetDevice() isLowPower]) deviceType = "integrated";
        else deviceType += "discrete";
        Printf("Metal device type: %s\n", deviceType.GetChars());
    }

    //static_cast<MTLDataBuffer*>(mLights->GetBuffer())->BindBase();
}

IVertexBuffer *MetalFrameBuffer::CreateVertexBuffer()
{
    return new MTLVertexBuffer();
}

void MetalFrameBuffer::TextureFilterChanged()
{
    if (MLRenderer != NULL && MLRenderer->mSamplerManager != NULL)
        MLRenderer->mSamplerManager->SetTextureFilterMode();
}

FModelRenderer* MetalFrameBuffer::CreateModelRenderer(int mli)
{
    return new FHWModelRenderer(nullptr, *MLRenderer->ml_RenderState, mli);
}

void MetalFrameBuffer::SetTextureFilterMode()
{
    if (MLRenderer != nullptr && MLRenderer->mSamplerManager != nullptr)
        MLRenderer->mSamplerManager->SetTextureFilterMode();
}

IIndexBuffer *MetalFrameBuffer::CreateIndexBuffer()
{
    return new MTLIndexBuffer();
}

void MetalFrameBuffer::SetVSync(bool vsync)
{
    cur_vsync = vsync;
}

void MetalFrameBuffer::PostProcessScene(int fixedcm, const std::function<void()> &afterBloomDrawEndScene2D)
{
    MLRenderer->PostProcessScene(fixedcm, afterBloomDrawEndScene2D);
}

IDataBuffer *MetalFrameBuffer::CreateDataBuffer(int bindingpoint, bool ssbo, bool needsresize)
{
    auto buffer = new MTLDataBuffer();

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
    //FPSLimit();
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
    //Swap();
    MLRenderer->ml_RenderState->EndFrame();
    Super::Update();
}

uint32_t MetalFrameBuffer::GetCaps()
{
    if (!V_IsHardwareRenderer())
        return Super::GetCaps();

    // describe our basic feature set
    ActorRenderFeatureFlags FlagSet = RFF_FLATSPRITES | RFF_MODELS | RFF_SLOPE3DFLOORS |
        RFF_TILTPITCH | RFF_ROLLSPRITES | RFF_POLYGONAL | RFF_MATSHADER | RFF_POSTSHADER | RFF_BRIGHTMAP;
    if (r_drawvoxels)
        FlagSet |= RFF_VOXELS;

    if (gl_tonemap != 5) // not running palette tonemap shader
        FlagSet |= RFF_TRUECOLOR;

    return (uint32_t)FlagSet;
}

FTexture* MetalFrameBuffer::WipeStartScreen()
{
    const auto &viewport = screen->mScreenViewport;
    
    auto tex = new FWrapperTexture(viewport.width, viewport.height, 1);
    auto systex = static_cast<MTLHardwareTexture*>(tex->GetSystemTexture());
    MTLRegion region = MTLRegionMake2D(0, 0, viewport.width, viewport.height);
  //  @autoreleasepool
    {
        OBJC_ID(MTLCommandBuffer)localCommandBuffer = [MLRenderer->ml_RenderState->commandQueue commandBuffer];
        OBJC_ID(MTLBlitCommandEncoder) blit = [localCommandBuffer blitCommandEncoder];
        OBJC_ID(MTLBuffer) buff = [device newBufferWithLength:viewport.width * viewport.height * 8 options:MTLResourceStorageModeShared];
        [blit copyFromTexture:MLRenderer->mScreenBuffers->mSceneFB
                  sourceSlice:0
                  sourceLevel:0
                 sourceOrigin:MTLOriginMake(0, 0, 0)
                   sourceSize:MTLSizeMake(viewport.width, viewport.height, 1)
                     toBuffer:buff
            destinationOffset:0
       destinationBytesPerRow:viewport.width * 8
     destinationBytesPerImage:viewport.width * viewport.height * 8];
        [blit endEncoding];
        [localCommandBuffer commit];
        [localCommandBuffer waitUntilCompleted];
        systex->CreateWipeScreen((unsigned char *)buff.contents, viewport.width, viewport.height, 0, false, "WipeStartScreen");
        [buff release];
    }
    
    return tex;
}

FTexture* MetalFrameBuffer::WipeEndScreen()
{
    //MLRenderer->Flush();
    [MLRenderer->ml_RenderState->renderCommandEncoder endEncoding];
    [MLRenderer->ml_RenderState->commandBuffer commit];
    const auto &viewport = screen->mScreenViewport;
    auto tex = new FWrapperTexture(viewport.width, viewport.height, 1);
    auto systex = static_cast<MTLHardwareTexture*>(tex->GetSystemTexture());
   // @autoreleasepool
    {
           OBJC_ID(MTLCommandBuffer)localCommandBuffer = [MLRenderer->ml_RenderState->commandQueue commandBuffer];
           OBJC_ID(MTLBlitCommandEncoder) blit = [localCommandBuffer blitCommandEncoder];
           OBJC_ID(MTLBuffer) buff = [device newBufferWithLength:viewport.width * viewport.height * 8 options:MTLResourceStorageModeShared];
           [blit copyFromTexture:MLRenderer->mScreenBuffers->mSceneFB
                     sourceSlice:0
                     sourceLevel:0
                    sourceOrigin:MTLOriginMake(0, 0, 0)
                      sourceSize:MTLSizeMake(viewport.width, viewport.height, 1)
                        toBuffer:buff
               destinationOffset:0
          destinationBytesPerRow:viewport.width * 8
        destinationBytesPerImage:viewport.width * viewport.height * 8];
           [blit endEncoding];
           [localCommandBuffer commit];
           [localCommandBuffer waitUntilCompleted];
           
           systex->CreateWipeScreen((unsigned char *)buff.contents, viewport.width, viewport.height, 0, false, "WipeEndScreen");
           [buff release];
    }
    //
    //screen->BeginFrame();
    return tex;
}

}
    
