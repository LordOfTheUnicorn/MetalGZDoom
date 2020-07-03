//
//---------------------------------------------------------------------------
//
// Copyright(C) 2009-2016 Christoph Oelckers
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

#pragma once

#import "Metal/Metal.h"
#import "MetalKit/MetalKit.h"

#include <string.h>
#include "matrix.h"
#include "hwrenderer/scene/hw_drawstructs.h"
#include "hwrenderer/scene/hw_renderstate.h"
#include "hwrenderer/textures/hw_material.h"
#include "c_cvars.h"
#include "r_defs.h"
#include "r_data/r_translate.h"
#include "g_levellocals.h"
#include "metal/shaders/ml_shader.h"
#include "metal/system/ml_framebuffer.h"
#include "metal/system/MetalCocoaView.h"


namespace MetalRenderer
{

class MlRenderBuffers;
class MlShader;
struct HWSectorPlane;

class MlRenderState : public FRenderState
{
    uint8_t mLastDepthClamp : 1;

    float mGlossiness, mSpecularLevel;
    float mShaderTimer;

    int mEffectState;
    int mTempTM = TM_NORMAL;

    FRenderStyle stRenderStyle;
    int stSrcBlend, stDstBlend;
    bool stAlphaTest;
    bool stSplitEnabled;
    int stBlendEquation;
    MTLRenderPassDescriptor* DefRenderPassDescriptor;
    //id<MTLRenderPipelineState>

    int mNumDrawBuffers = 1;

    bool ApplyShader();
    void ApplyState();

    // Texture binding state
    FMaterial *lastMaterial = nullptr;
    int lastClamp = 0;
    int lastTranslation = 0;
    int maxBoundMaterial = -1;
    size_t mLastMappedLightIndex = SIZE_MAX;
    int mScissorX;
    int mScissorY;
    int mScissorWidth;
    int mScissorHeight;

    IVertexBuffer *mCurrentVertexBuffer;
    int mCurrentVertexOffsets[2];    // one per binding point
    IIndexBuffer *mCurrentIndexBuffer;
    MlRenderBuffers *buffers;
    MTLViewport m_Viewport;


public:
    MlShader *activeShader;
    int val =0;
    id <MTLCommandQueue> commandQueue;
    id <MTLCommandBuffer> commandBuffer;
    id <MTLRenderCommandEncoder> renderCommandEncoder;
    void CreateRenderState(MTLRenderPassDescriptor * renderPassDescriptor);
    void setVertexBuffer(id<MTLBuffer> buffer, size_t index, size_t offset = 0);
    
    MlRenderState()
    {
        Reset();
        //activeShader = new MlShader();
        commandQueue = [device newCommandQueueWithMaxCommandBufferCount:512];
    }
    
    MlRenderState(MlRenderBuffers *buffers) : buffers(buffers)
    {
        activeShader = new MlShader();
    }
    
    ~MlRenderState()
    {
        delete activeShader;
    }
    
    void Reset();

    void ClearLastMaterial()
    {
        lastMaterial = nullptr;
    }

    void ApplyMaterial(FMaterial *mat, int clampmode, int translation, int overrideshader);

    void EndFrame();
    void Apply();
    void ApplyBuffers();
    void ApplyBlendMode();
    
    void ResetVertexBuffer()
    {
        // forces rebinding with the next 'apply' call.
        mCurrentVertexBuffer = nullptr;
        mCurrentIndexBuffer = nullptr;
    }

    void SetSpecular(float glossiness, float specularLevel)
    {
        mGlossiness = glossiness;
        mSpecularLevel = specularLevel;
    }

    void EnableDrawBuffers(int count) override
    {
        count = MIN(count, 3);
        if (mNumDrawBuffers != count)
        {
            mNumDrawBuffers = count;
        }
    }

    void ToggleState(int state, bool on);

    void ClearScreen() override;
    void Draw(int dt, int index, int count, bool apply = true) override;
    void DrawIndexed(int dt, int index, int count, bool apply = true) override;

    bool SetDepthClamp(bool on) override;
    void SetDepthMask(bool on) override;
    void SetDepthFunc(int func) override;
    void SetDepthRange(float min, float max) override;
    void SetColorMask(bool r, bool g, bool b, bool a) override;
    void SetStencil(int offs, int op, int flags) override;
    void SetCulling(int mode) override;
    void EnableClipDistance(int num, bool state) override;
    void Clear(int targets) override;
    void EnableStencil(bool on) override;
    void SetScissor(int x, int y, int w, int h) override;
    void SetViewport(int x, int y, int w, int h) override;
    void EnableDepthTest(bool on) override;
    void EnableMultisampling(bool on) override;
    void EnableLineSmooth(bool on) override;

};

static MlRenderState ml_RenderState;
static MetalCocoaView* m_view;

}


