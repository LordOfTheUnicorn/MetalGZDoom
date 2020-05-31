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
/*
** gl_renderstate.cpp
** Render state maintenance
**
*/

#include "templates.h"
#include "doomstat.h"
#include "r_data/colormaps.h"
#include "gl_load/gl_system.h"
#include "gl_load/gl_interface.h"
#include "hwrenderer/utility/hw_cvars.h"
#include "hwrenderer/data/flatvertices.h"
#include "hwrenderer/textures/hw_material.h"
#include "hwrenderer/scene/hw_skydome.h"
#include "metal/shaders/ml_shader.h"
#include "metal/renderer/ml_renderer.h"
#include "hwrenderer/dynlights/hw_lightbuffer.h"
#include "metal/renderer/ml_renderbuffers.h"
#include "metal/renderer/ml_renderstate.h"
#include "metal/textures/ml_hwtexture.h"
#include "metal/system/ml_buffer.h"
#include "hwrenderer/utility/hw_clock.h"
#include "hwrenderer/data/hw_viewpointbuffer.h"
#include <simd/simd.h>
#include <math.h>

namespace MetalRenderer
{

typedef struct
{
    //float4x4 ModelMatrix;
    //float4x4 TextureMatrix;
    //float4x4 NormalModelMatrix;
    
    matrix_float4x4 ModelMatrix;
    matrix_float4x4 TextureMatrix;
    matrix_float4x4 NormalModelMatrix;
} PerView;

//static MlRenderState ml_RenderState;

static VSMatrix identityMatrix(1);

//static void matrixToGL(const VSMatrix &mat, int loc)
//{
//    glUniformMatrix4fv(loc, 1, false, (float*)&mat);
//}

//==========================================================================
//
// This only gets called once upon setup.
// With OpenGL the state is persistent and cannot be cleared, once set up.
//
//==========================================================================

void MlRenderState::Reset()
{
    FRenderState::Reset();
    mVertexBuffer = mCurrentVertexBuffer = nullptr;
    mGlossiness = 0.0f;
    mSpecularLevel = 0.0f;
    mShaderTimer = 0.0f;

    stRenderStyle = DefaultRenderStyle();
    stSrcBlend = stDstBlend = -1;
    stBlendEquation = -1;
    stAlphaTest = 0;
    mLastDepthClamp = true;

    mEffectState = 0;
    activeShader = nullptr;

    mCurrentVertexBuffer = nullptr;
    mCurrentVertexOffsets[0] = mVertexOffsets[0] = 0;
    mCurrentIndexBuffer = nullptr;

}


//==========================================================================
//
// Apply State
//
//==========================================================================

void MlRenderState::ApplyState()
{
    if (mRenderStyle != stRenderStyle)
    {
        stRenderStyle = mRenderStyle;
    }

    if (mSplitEnabled != stSplitEnabled)
    {
        stSplitEnabled = mSplitEnabled;
    }

    if (mMaterial.mChanged)
    {
        ApplyMaterial(mMaterial.mMaterial, mMaterial.mClampMode, mMaterial.mTranslation, mMaterial.mOverrideShader);
        mMaterial.mChanged = false;
    }
    
    //commandBuffer = [commandQueue commandBuffer];
    //commandBuffer.label = @"RenderStateCommandBuffer";

    //Is this need or not?
    //if (mBias.mChanged)
    //{
    //    if (mBias.mFactor == 0 && mBias.mUnits == 0)
    //    {
    //        glDisable(GL_POLYGON_OFFSET_FILL);
    //    }
    //    else
    //    {
    //        glEnable(GL_POLYGON_OFFSET_FILL);
    //    }
    //    glPolygonOffset(mBias.mFactor, mBias.mUnits);
    //    mBias.mChanged = false;
    //}
}

typedef struct
{
    float uDesaturationFactor;
    vector_float4 uCameraPos;
    float uGlobVis;
    int uPalLightLevels;
    int uFogEnabled;
    vector_float4 uGlowTopColor;
    vector_float4 uGlowBottomColor;
    int uTextureMode;
    vector_float4 uFogColor;
    vector_float4 uObjectColor;
    vector_float4 uObjectColor2;
    vector_float4 uAddColor;
    vector_float4 uDynLightColor;
    float timer;
    id<MTLTexture> tex;
    
    //#define uLightLevel uLightAttr.a
    //#define uFogDensity uLightAttr.b
    //#define uLightFactor uLightAttr.g
    //#define uLightDist uLightAttr.r
    vector_float4 uLightAttr;
} Uniforms;

typedef struct
{
    vector_float2 uClipSplit;
    vector_float4 uSplitTopPlane;
    float         uInterpolationFactor;
    vector_float4 uGlowTopColor;
    vector_float4 uGlowTopPlane;
    vector_float4 uGlowBottomPlane;
    vector_float4 uObjectColor2;
    vector_float4 uSplitBottomPlane;
    vector_float4 uGradientBottomPlane;
    vector_float4 uGlowBottomColor;
    vector_float4 uGradientTopPlane;
} VSUniforms;

typedef struct
{
    vector_float4   uClipLine;
    float           uClipHeight;
    float           uClipHeightDirection;
    simd::float4x4  ProjectionMatrix;
    simd::float4x4  ViewMatrix;
    simd::float4x4  NormalViewMatrix;
} ViewpointUBO;

matrix_float4x4 matrix_perspective_right_hand(float fovyRadians, float aspect, float nearZ, float farZ)
{
    float ys = 1 / tanf(fovyRadians * 0.5);
    float xs = ys / aspect;
    float zs = farZ / (nearZ - farZ);
    
    return (matrix_float4x4) {{
        { xs,   0,          0,  0 },
        {  0,  ys,          0,  0 },
        {  0,   0,         zs, -1 },
        {  0,   0, nearZ * zs,  0 }
    }};
}

matrix_float4x4 matrix_perspective_left_hand(float fovyRadians, float aspect, float nearZ, float farZ)
{
        const float yScale = 1.0f / std::tan((float)fovyRadians / 2.0f);
        const float xScale = yScale / aspect;
        const float farNearDiff = farZ - nearZ;

        //Left handed projection matrix
    return matrix_float4x4{vector_float4{xScale, 0.0f, 0.0f, 0.0f},
                           vector_float4{0.0f, yScale, 0.0f, 0.0f},
                           vector_float4{0.0f, 0.0f, 1.f / farNearDiff, 1.0f},
                           vector_float4{0.0f, 0.0f, (-nearZ * farZ) / farNearDiff, 0.0f}};
}

bool MlRenderState::ApplyShader()
{
    static const float nulvec[] = { 0.f, 0.f, 0.f, 0.f };
    activeShader = new MlShader();
    activeShader->Load();
    //if (mSpecialEffect > EFF_NONE)
    //{
    //    activeShader = GLRenderer->mShaderManager->BindEffect(mSpecialEffect, mPassType);
    //}
    //else
    //{
    //    activeShader = GLRenderer->mShaderManager->Get(mTextureEnabled ? mEffectState : SHADER_NoTexture, mAlphaThreshold >= 0.f, mPassType);
    //    activeShader->Bind();
    //}

    int fogset = 0;

    if (mFogEnabled)
    {
        if (mFogEnabled == 2)
        {
            fogset = -3;    // 2D rendering with 'foggy' overlay.
        }
        else if ((GetFogColor() & 0xffffff) == 0)
        {
            fogset = gl_fogmode;
        }
        else
        {
            fogset = -gl_fogmode;
        }
    }

   // MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
   // if (MLRenderer->mScreenBuffers)
   // {
   //     // Color render target
   //     renderPassDescriptor.colorAttachments[0].texture = MLRenderer->mScreenBuffers->mSceneFB;
   //     renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
   //     renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;

   //     // Depth render target
   //     renderPassDescriptor.depthAttachment.texture = MLRenderer->mScreenBuffers->mSceneDepthStencilTex;
   //     renderPassDescriptor.depthAttachment.loadAction = MTLLoadActionDontCare;
   //     renderPassDescriptor.depthAttachment.storeAction = MTLStoreActionDontCare;
   //

   //     // Stencil render target
   //     //renderPassDescriptor.stencilAttachment.texture = mScreenBuffers->mSceneDepthStencilTex;
   //     //renderPassDescriptor.stencilAttachment.loadAction = MTLLoadActionDontCare;
   //     //renderPassDescriptor.stencilAttachment.storeAction = MTLStoreActionDontCare;
   // }
   //
   // renderPassDescriptor.renderTargetWidth = 1920;
   // renderPassDescriptor.renderTargetHeight = 1080;
   // renderPassDescriptor.defaultRasterSampleCount = 1;
   //
   // //[renderCommandEncoder endEncoding];
   // //renderCommandEncoder = nil;
   //
   // renderCommandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
   // DefRenderPassDescriptor = renderPassDescriptor;
    
    
    id <MTLBuffer> buff = [device newBufferWithBytes:&mStreamData.uVertexColor length:sizeof(FVector4) options:MTLResourceStorageModeShared];
    //[renderCommandEncoder setVertexBuffer:buff offset:0 atIndex:VATTR_COLOR];
    
    activeShader->muDesaturation.Set(mStreamData.uDesaturationFactor);
    activeShader->muFogEnabled.Set(fogset);
    activeShader->muTextureMode.Set(mTextureMode == TM_NORMAL && mTempTM == TM_OPAQUE ? TM_OPAQUE : mTextureMode);
    activeShader->muLightParms.Set(vector_float4{mLightParms[0],mLightParms[1],mLightParms[2],mLightParms[3]});
    activeShader->muFogColor.Set(mStreamData.uFogColor);
    activeShader->muObjectColor.Set(mStreamData.uObjectColor);
    activeShader->muDynLightColor.Set(mStreamData.uDynLightColor.X);
    activeShader->muInterpolationFactor.Set(mStreamData.uInterpolationFactor);
    activeShader->muTimer.Set((double)(screen->FrameTime - firstFrame) * (double)mShaderTimer / 1000.);
    activeShader->muAlphaThreshold.Set(mAlphaThreshold);
    activeShader->muLightIndex.Set(-1);
    activeShader->muClipSplit.Set(vector_float2{mClipSplit[0],mClipSplit[1]});
    activeShader->muSpecularMaterial.Set(vector_float2{mGlossiness, mSpecularLevel});
    activeShader->muAddColor.Set(mStreamData.uAddColor);

    if (mGlowEnabled || activeShader->currentglowstate)
    {
        activeShader->muGlowTopColor.Set(vector_float4{mStreamData.uGlowTopColor.X,mStreamData.uGlowTopColor.Y,mStreamData.uGlowTopColor.Z,mStreamData.uGlowTopColor.W});
        activeShader->muGlowBottomColor.Set(vector_float4{mStreamData.uGlowBottomColor.X,mStreamData.uGlowBottomColor.Y,mStreamData.uGlowBottomColor.Z,mStreamData.uGlowBottomColor.W});
        activeShader->muGlowTopPlane.Set(vector_float4{mStreamData.uGlowTopPlane.X,mStreamData.uGlowTopPlane.Y,mStreamData.uGlowTopPlane.Z,mStreamData.uGlowTopPlane.W});
        activeShader->muGlowBottomPlane.Set(vector_float4{mStreamData.uGlowBottomPlane.X,mStreamData.uGlowBottomPlane.Y,mStreamData.uGlowBottomPlane.Z,mStreamData.uGlowBottomPlane.W});
        activeShader->currentglowstate = mGlowEnabled;
    }

    if (mGradientEnabled || activeShader->currentgradientstate)
    {
        activeShader->muObjectColor2.Set(mStreamData.uObjectColor2);
        activeShader->muGradientTopPlane.Set(vector_float4{mStreamData.uGradientTopPlane.X, mStreamData.uGradientTopPlane.Y, mStreamData.uGradientTopPlane.Z, mStreamData.uGradientTopPlane.W});
        activeShader->muGradientBottomPlane.Set(vector_float4{mStreamData.uGradientBottomPlane.X, mStreamData.uGradientBottomPlane.Y, mStreamData.uGradientBottomPlane.Z, mStreamData.uGradientBottomPlane.W});
        activeShader->currentgradientstate = mGradientEnabled;
    }

    if (mSplitEnabled || activeShader->currentsplitstate)
    {
        activeShader->muSplitTopPlane.Set(vector_float4{mStreamData.uSplitTopPlane.X, mStreamData.uSplitTopPlane.Y, mStreamData.uSplitTopPlane.Z, mStreamData.uSplitTopPlane.W});
        activeShader->muSplitBottomPlane.Set(vector_float4{mStreamData.uSplitBottomPlane.X, mStreamData.uSplitBottomPlane.Y, mStreamData.uSplitBottomPlane.Z, mStreamData.uSplitBottomPlane.W});
        activeShader->currentsplitstate = mSplitEnabled;
    }

    if (mTextureMatrixEnabled)
    {
        activeShader->texturematrix.matrixToMetal(mTextureMatrix);
        activeShader->currentTextureMatrixState = true;
    }
    else if (activeShader->currentTextureMatrixState)
    {
        activeShader->currentTextureMatrixState = false;
        activeShader->texturematrix.matrixToMetal(identityMatrix);
    }

    if (mModelMatrixEnabled)
    {
        activeShader->modelmatrix.matrixToMetal(mModelMatrix);
        VSMatrix norm;
        norm.computeNormalMatrix(mModelMatrix);
        activeShader->normalmodelmatrix.matrixToMetal(norm);
        activeShader->currentModelMatrixState = true;
    }
    else if (activeShader->currentModelMatrixState)
    {
        activeShader->currentModelMatrixState = false;
        activeShader->modelmatrix.matrixToMetal(identityMatrix);
        activeShader->normalmodelmatrix.matrixToMetal(identityMatrix);
    }
    
    //float2 uClipSplit;
    //float4 uSplitTopPlane;
    //float  uInterpolationFactor;
    //float4 uGlowTopColor;
    //float4 uGlowTopPlane;
    //float4 uGlowBottomPlane;
    //float4 uObjectColor2;
    //float4 uSplitBottomPlane;
    //float4 uGradientBottomPlane;
    //float4 uGlowBottomColor;
    //float4 uGradientTopPlane;
    
    MlDataBuffer* dataBuffer = (MlDataBuffer*)screen->mViewpoints;
    
    //float4x4 ModelMatrix;
    //float4x4 TextureMatrix;
    //float4x4 NormalModelMatrix;
    
    PerView data[6];
    data[0].ModelMatrix       = /*simd_transpose*/(activeShader->modelmatrix.mat);
    data[0].TextureMatrix     = /*simd_transpose*/(activeShader->texturematrix.mat);
    data[0].NormalModelMatrix = /*simd_transpose*/(activeShader->normalmodelmatrix.mat);
    auto fb = GetMetalFrameBuffer();
    
    data[1] = data[2] = data[3] = data[4] = data[5] = data[0];
    
    id <MTLBuffer> buff2 = [device newBufferWithBytes:&data length:sizeof(PerView)*6 options:MTLResourceStorageModeShared];
    [renderCommandEncoder setVertexBuffer:buff2 offset:0 atIndex:3];
    
    int index = mLightIndex;
    // Mess alert for crappy AncientGL!
    if (!screen->mLights->GetBufferType() && index >= 0)
    {
        size_t start, size;
        index = screen->mLights->GetBinding(index, &start, &size);

        if (start != mLastMappedLightIndex)
        {
            mLastMappedLightIndex = start;
            //static_cast<GLDataBuffer*>(screen->mLights->GetBuffer())->BindRange(nullptr, start, size);
        }
    }
    Uniforms uniforms;
    uniforms.timer = activeShader->muTimer.val;
    uniforms.uAddColor = {activeShader->muAddColor.mBuffer.r,activeShader->muAddColor.mBuffer.g,activeShader->muAddColor.mBuffer.b,activeShader->muAddColor.mBuffer.a};
    uniforms.uDesaturationFactor = mStreamData.uDesaturationFactor;
    uniforms.uDynLightColor = activeShader->muDynLightColor.val;
    uniforms.uFogColor = {activeShader->muFogColor.mBuffer.r,activeShader->muFogColor.mBuffer.g,activeShader->muFogColor.mBuffer.b,activeShader->muFogColor.mBuffer.a};
    uniforms.uFogEnabled = activeShader->muFogEnabled.val;
    uniforms.uGlowBottomColor = activeShader->muGlowBottomColor.val;
    uniforms.uGlowTopColor = activeShader->muGlowTopColor.val;
    uniforms.uObjectColor = {activeShader->muObjectColor.mBuffer.r,activeShader->muObjectColor.mBuffer.g,activeShader->muObjectColor.mBuffer.b,activeShader->muObjectColor.mBuffer.a};
    uniforms.uObjectColor2 = {activeShader->muObjectColor2.mBuffer.r,activeShader->muObjectColor2.mBuffer.g,activeShader->muObjectColor2.mBuffer.b,activeShader->muObjectColor2.mBuffer.a};
    
    id<MTLBuffer> uniformsData = [device newBufferWithBytes:&uniforms length:sizeof(Uniforms) options:MTLResourceStorageModeShared];
    [renderCommandEncoder setFragmentBuffer:uniformsData offset:0 atIndex:7];
    
    mtlHWViewpointUniforms hw[6];
    if(MLRenderer->mHWViewpointUniforms != nullptr)
    {
        //size_t size = sizeof(*MLRenderer->mHWViewpointUniforms);
        hw[0] = *MLRenderer->mHWViewpointUniforms;
        hw[1] = hw[2] = hw[3] = hw[4] = hw[5] = hw[0];
        
        id<MTLBuffer> buff = [device newBufferWithBytes:&hw length:sizeof(mtlHWViewpointUniforms)*6 options:MTLResourceStorageModeShared];
        [renderCommandEncoder setVertexBuffer:buff offset:0 atIndex:4];
        //[renderCommandEncoder setVertexBytes:&hw[0] length:sizeof(hw) atIndex:4];
    }
    
    VSUniforms VSUniform [6];
    VSUniform[0].uClipSplit = activeShader->muClipSplit.val;
    VSUniform[0].uSplitTopPlane = activeShader->muSplitTopPlane.val;
    VSUniform[0].uInterpolationFactor = activeShader->muInterpolationFactor.val;
    VSUniform[0].uGlowTopColor = activeShader->muGlowTopColor.val;
    VSUniform[0].uGlowTopPlane = activeShader->muGlowTopPlane.val;
    VSUniform[0].uGlowBottomPlane = activeShader->muGlowBottomPlane.val;
    VSUniform[0].uObjectColor2 = {activeShader->muObjectColor2.mBuffer.r,activeShader->muObjectColor2.mBuffer.g,activeShader->muObjectColor2.mBuffer.b,activeShader->muObjectColor2.mBuffer.a};
    VSUniform[0].uSplitBottomPlane = activeShader->muSplitBottomPlane.val;
    VSUniform[0].uGradientBottomPlane = activeShader->muGradientBottomPlane.val;
    VSUniform[0].uGlowBottomColor = activeShader->muGlowBottomColor.val;
    VSUniform[0].uGradientTopPlane = activeShader->muGradientTopPlane.val;
    
    VSUniform[1] = VSUniform[2] = VSUniform[3] = VSUniform[4] = VSUniform[5] = VSUniform[0];
    
    id<MTLBuffer> VSUniformsData = [device newBufferWithBytes:&VSUniform length:sizeof(VSUniform)*6 options:MTLResourceStorageModeShared];
    [renderCommandEncoder setVertexBuffer:VSUniformsData offset:0 atIndex:5];
    
    activeShader->muLightIndex.Set(index);
    return true;
    
}

void MlRenderState::ApplyBuffers()
{
    //if (mVertexBuffer != mCurrentVertexBuffer || mVertexOffsets[0] != mCurrentVertexOffsets[0] || mVertexOffsets[1] != mCurrentVertexOffsets[1])
    if (mVertexBuffer != nullptr)
    {
        assert(mVertexBuffer != nullptr);
        MlVertexBuffer* mtlBuffer = static_cast<MlVertexBuffer*>(mVertexBuffer);
        mtlBuffer->Bind(mVertexOffsets,renderCommandEncoder);        
        mCurrentVertexBuffer = mVertexBuffer;
        mCurrentVertexOffsets[0] = mVertexOffsets[0];
        mCurrentVertexOffsets[1] = mVertexOffsets[1];
    }
    if (mIndexBuffer != mCurrentIndexBuffer)
    {
       // if (mIndexBuffer) static_cast<GLIndexBuffer*>(mIndexBuffer)->Bind();
        mCurrentIndexBuffer = mIndexBuffer;
    }
}

void MlRenderState::Apply()
{
    ApplyShader();
    ApplyState();
    ApplyBuffers();
}

void MlRenderState::CreateRenderState(MTLRenderPassDescriptor * renderPassDescriptor)
{
    commandBuffer = [commandQueue commandBuffer];
    renderCommandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    renderCommandEncoder.label = @"renderCommandEncoder";
    [renderCommandEncoder setFrontFacingWinding:MTLWindingClockwise];
    [renderCommandEncoder setCullMode:MTLCullModeNone];
    [renderCommandEncoder setViewport:(MTLViewport){0.0, 0.0, 1440.0, 900.0, 0.0, 1.0 }];
    
    if (activeShader == nullptr)
    {
        activeShader = new MlShader();
        activeShader->Load();
    }
    
    
    [renderCommandEncoder setRenderPipelineState:activeShader->pipelineState];
    [renderCommandEncoder setDepthStencilState:activeShader->depthState];

}

void MlRenderState::setVertexBuffer(id<MTLBuffer> buffer, size_t index, size_t offset /*= 0*/)
{
    [ml_RenderState.renderCommandEncoder setVertexBuffer:buffer offset:offset atIndex:index];
}

void MlRenderState::EndFrame()
{
        if (MLRenderer->mScreenBuffers->mDrawable)
            //[commandBuffer presentDrawable:MLRenderer->mScreenBuffers->mDrawable];
        
        [renderCommandEncoder endEncoding];
        [commandBuffer commit];
}

//===========================================================================
//
//    Binds a texture to the renderer
//
//====================================================me=======================

void MlRenderState::ApplyMaterial(FMaterial *mat, int clampmode, int translation, int overrideshader)
{
    if (mat->tex->isHardwareCanvas())
    {
        mTempTM = TM_OPAQUE;
    }
    else
    {
        mTempTM = TM_NORMAL;
    }
    mEffectState = overrideshader >= 0 ? overrideshader : mat->GetShaderIndex();
    mShaderTimer = mat->tex->shaderspeed;
    SetSpecular(mat->tex->Glossiness, mat->tex->SpecularLevel);

    auto tex = mat->tex;
    if (tex->UseType == ETextureType::SWCanvas) clampmode = CLAMP_NOFILTER;
    if (tex->isHardwareCanvas()) clampmode = CLAMP_CAMTEX;
    else if ((tex->isWarped() || tex->shaderindex >= FIRST_USER_SHADER) && clampmode <= CLAMP_XY) clampmode = CLAMP_NONE;
    
    // avoid rebinding the same texture multiple times.
   // if (mat == lastMaterial && lastClamp == clampmode && translation == lastTranslation) return;
    lastMaterial = mat;
    lastClamp = clampmode;
    lastTranslation = translation;

    int usebright = false;
    int maxbound = 0;

    // Textures that are already scaled in the texture lump will not get replaced by hires textures.
    int flags = mat->isExpanded() ? CTF_Expand : (gl_texture_usehires && !tex->isScaled() && clampmode <= CLAMP_XY) ? CTF_CheckHires : 0;
    int numLayers = mat->GetLayers();
    auto base = static_cast<MlHardwareTexture*>(mat->GetLayer(0, translation));

    if (base->BindOrCreate(tex, 0, clampmode, translation, flags, renderCommandEncoder))
    {
        for (int i = 1; i<numLayers; i++)
        {
            FTexture *layer;
            auto systex = static_cast<MlHardwareTexture*>(mat->GetLayer(i, 0, &layer));
            systex->BindOrCreate(layer, i, clampmode, 0, mat->isExpanded() ? CTF_Expand : 0, renderCommandEncoder);
            maxbound = i;
        }
    }
    // unbind everything from the last texture that's still active
    for (int i = maxbound + 1; i <= maxBoundMaterial; i++)
    {
    //    MlHardwareTexture::Unbind(i);
        maxBoundMaterial = maxbound;
    }
}

//==========================================================================
//
// Apply blend mode from RenderStyle
//
//==========================================================================

void MlRenderState::ApplyBlendMode()
{
    static int blendstyles[] = { GL_ZERO, GL_ONE, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_SRC_COLOR, GL_ONE_MINUS_SRC_COLOR, GL_DST_COLOR, GL_ONE_MINUS_DST_COLOR, };
    static int renderops[] = { 0, GL_FUNC_ADD, GL_FUNC_SUBTRACT, GL_FUNC_REVERSE_SUBTRACT, -1, -1, -1, -1,
        -1, -1, -1, -1, -1, -1, -1, -1 };

    int srcblend = blendstyles[mRenderStyle.SrcAlpha%STYLEALPHA_MAX];
    int dstblend = blendstyles[mRenderStyle.DestAlpha%STYLEALPHA_MAX];
    int blendequation = renderops[mRenderStyle.BlendOp & 15];

    if (blendequation == -1)    // This was a fuzz style.
    {
        srcblend = GL_DST_COLOR;
        dstblend = GL_ONE_MINUS_SRC_ALPHA;
        blendequation = GL_FUNC_ADD;
    }

    // Checks must be disabled until all draw code has been converted.
    //if (srcblend != stSrcBlend || dstblend != stDstBlend)
    {
        stSrcBlend = srcblend;
        stDstBlend = dstblend;
        glBlendFunc(srcblend, dstblend);
    }
    //if (blendequation != stBlendEquation)
    {
        stBlendEquation = blendequation;
        glBlendEquation(blendequation);
    }

}

//==========================================================================
//
// API dependent draw calls
//
//==========================================================================

static MTLPrimitiveType dt2ml[] = { MTLPrimitiveTypePoint, MTLPrimitiveTypeLine, MTLPrimitiveTypeTriangle, MTLPrimitiveTypeTriangle, MTLPrimitiveTypeTriangleStrip };

void MlRenderState::Draw(int dt, int index, int count, bool apply)
{
    if (apply)
    {
        Apply();
    }
    
    drawcalls.Clock();
    glDrawArrays(dt2ml[dt], index, count);
    drawcalls.Unclock();
}

void MlRenderState::DrawIndexed(int dt, int index, int count, bool apply)
{
    if (apply)
    {
        Apply();
    }
    drawcalls.Clock();
    MlVertexBuffer* mtlBuffer = static_cast<MlVertexBuffer*>(mVertexBuffer);
    [renderCommandEncoder drawPrimitives:dt2ml[dt] vertexStart:0 vertexCount:count];
    [renderCommandEncoder popDebugGroup];

    drawcalls.Unclock();
}

void MlRenderState::SetDepthMask(bool on)
{
    glDepthMask(on);
}

void MlRenderState::SetDepthFunc(int func)
{
    static int df2gl[] = { GL_LESS, GL_LEQUAL, GL_ALWAYS };
    glDepthFunc(df2gl[func]);
}

void MlRenderState::SetDepthRange(float min, float max)
{
    glDepthRange(min, max);
}

void MlRenderState::SetColorMask(bool r, bool g, bool b, bool a)
{
    glColorMask(r, g, b, a);
}

void MlRenderState::SetStencil(int offs, int op, int flags = -1)
{
    static int op2gl[] = { GL_KEEP, GL_INCR, GL_DECR };

    glStencilFunc(GL_EQUAL, screen->stencilValue + offs, ~0);        // draw sky into stencil
    glStencilOp(GL_KEEP, GL_KEEP, op2gl[op]);        // this stage doesn't modify the stencil

    if (flags != -1)
    {
        bool cmon = !(flags & SF_ColorMaskOff);
        glColorMask(cmon, cmon, cmon, cmon);                        // don't write to the graphics buffer
        glDepthMask(!(flags & SF_DepthMaskOff));
    }
}

void MlRenderState::ToggleState(int state, bool on)
{
    if (on)
    {
        glEnable(state);
    }
    else
    {
        glDisable(state);
    }
}

void MlRenderState::SetCulling(int mode)
{
    if (mode != Cull_None)
    {
        glEnable(GL_CULL_FACE);
        glFrontFace(mode == Cull_CCW ? GL_CCW : GL_CW);
    }
    else
    {
        glDisable(GL_CULL_FACE);
    }
}

void MlRenderState::EnableClipDistance(int num, bool state)
{
    // Update the viewpoint-related clip plane setting.
    //if (!(gl.flags & RFL_NO_CLIP_PLANES))
    //{
    //    ToggleState(GL_CLIP_DISTANCE0 + num, state);
    //}
}

void MlRenderState::Clear(int targets)
{
    // This always clears to default values.
    int gltarget = 0;
    if (targets & CT_Depth)
    {
        gltarget |= GL_DEPTH_BUFFER_BIT;
        glClearDepth(1);
    }
    if (targets & CT_Stencil)
    {
        gltarget |= GL_STENCIL_BUFFER_BIT;
        glClearStencil(0);
    }
    if (targets & CT_Color)
    {
        gltarget |= GL_COLOR_BUFFER_BIT;
        glClearColor(screen->mSceneClearColor[0], screen->mSceneClearColor[1], screen->mSceneClearColor[2], screen->mSceneClearColor[3]);
    }
    glClear(gltarget);
}

void MlRenderState::EnableStencil(bool on)
{
    ToggleState(GL_STENCIL_TEST, on);
}

void MlRenderState::SetScissor(int x, int y, int w, int h)
{
    mScissorX = x;
    mScissorY = y;
    mScissorWidth = w;
    mScissorHeight = h;
    //mScissorChanged = true;
    //mNeedApply = true;
}

void MlRenderState::SetViewport(int x, int y, int w, int h)
{
    m_Viewport.originX = x;
    m_Viewport.originY = y;
    m_Viewport.height = h;
    m_Viewport.width = w;
    
    [renderCommandEncoder setViewport:m_Viewport];
}

void MlRenderState::EnableDepthTest(bool on)
{
    //ToggleState(GL_DEPTH_TEST, on);
}

void MlRenderState::EnableMultisampling(bool on)
{
    //ToggleState(GL_MULTISAMPLE, on);
}

void MlRenderState::EnableLineSmooth(bool on)
{
    //ToggleState(GL_LINE_SMOOTH, on);
}

//==========================================================================
//
//
//
//==========================================================================
void MlRenderState::ClearScreen()
{
    bool multi = !!glIsEnabled(GL_MULTISAMPLE);

    screen->mViewpoints->Set2D(*this, SCREENWIDTH, SCREENHEIGHT);
    SetColor(0, 0, 0);
    Apply();

    glDisable(GL_MULTISAMPLE);
    glDisable(GL_DEPTH_TEST);

    glDrawArrays(GL_TRIANGLE_STRIP, FFlatVertexBuffer::FULLSCREEN_INDEX, 4);

    glEnable(GL_DEPTH_TEST);
    if (multi) glEnable(GL_MULTISAMPLE);
}



//==========================================================================
//
// Below are less frequently altrered state settings which do not get
// buffered by the state object, but set directly instead.
//
//==========================================================================

bool MlRenderState::SetDepthClamp(bool on)
{
    bool res = mLastDepthClamp;
    if (!on) glDisable(GL_DEPTH_CLAMP);
    else glEnable(GL_DEPTH_CLAMP);
    mLastDepthClamp = on;
    return res;
}

}

