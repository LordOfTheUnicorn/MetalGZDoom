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
    matrix_float4x4 ModelMatrix;
    matrix_float4x4 TextureMatrix;
    matrix_float4x4 NormalModelMatrix;
} PerView;

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
    MlVertexBuffer* vertexBuffer = static_cast<MlVertexBuffer*>(mVertexBuffer);
    
    if (vertexBuffer == nullptr || VertexBufferAttributeWasChange(vertexBuffer->mAttributeInfo))
    {
        bool isVertexBufferNull = vertexBuffer == nullptr;
        if (!isVertexBufferNull)
            CopyVertexBufferAttribute(vertexBuffer->mAttributeInfo);
        
        size_t stride = !isVertexBufferNull ? vertexBuffer->mStride : 24;
        const MLVertexBufferAttribute *attr = !isVertexBufferNull ? vertexBuffer->mAttributeInfo : nullptr;
        NSError* error = nil;
            
        //##########################ATTRIBUTE 0#########################
        vertexDesc.attributes[0].format = MTLVertexFormatFloat3;
        vertexDesc.attributes[0].offset = 0;
        vertexDesc.attributes[0].bufferIndex = 0;
        vertexDesc.layouts[0].stride = stride;
        vertexDesc.layouts[0].stepRate = 1;
        vertexDesc.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
        //##########################ATTRIBUTE 1#########################
        vertexDesc.attributes[1].format = MTLVertexFormatFloat2;
        vertexDesc.attributes[1].offset = attr == nullptr || attr[1].size > 0 ? 12 : 0;
        vertexDesc.attributes[1].bufferIndex = 0;
        vertexDesc.layouts[1].stride = 0;
        vertexDesc.layouts[1].stepRate = attr == nullptr || attr[1].size > 0 ? 1 : 0;;
        vertexDesc.layouts[1].stepFunction = MTLVertexStepFunctionPerVertex;
        //##########################ATTRIBUTE 2#########################
        vertexDesc.attributes[2].format = MTLVertexFormatFloat;
        vertexDesc.attributes[2].offset = attr == nullptr || attr[2].size > 0 ? 20 : 0;
        vertexDesc.attributes[2].bufferIndex = 0;
        vertexDesc.layouts[2].stride = 0;
        vertexDesc.layouts[2].stepRate  = attr == nullptr || attr[2].size > 0 ? 1 : 0;
        vertexDesc.layouts[2].stepFunction = MTLVertexStepFunctionPerVertex;
        vertexDesc.layouts[3].stepFunction = MTLVertexStepFunctionConstant;
        vertexDesc.layouts[4].stepFunction = MTLVertexStepFunctionConstant;
        vertexDesc.layouts[5].stepFunction = MTLVertexStepFunctionConstant;
        //##############################################################
            
        renderPipelineDesc.label = @"VertexMain";
        renderPipelineDesc.vertexFunction = VShader;
        renderPipelineDesc.fragmentFunction = FShader;
        renderPipelineDesc.vertexDescriptor = vertexDesc;
        renderPipelineDesc.sampleCount = 1;
            
        renderPipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
        renderPipelineDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
        renderPipelineDesc.stencilAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;

        renderPipelineDesc.colorAttachments[0].rgbBlendOperation           = MTLBlendOperationAdd;
        renderPipelineDesc.colorAttachments[0].alphaBlendOperation         = MTLBlendOperationAdd;
        renderPipelineDesc.colorAttachments[0].sourceRGBBlendFactor        = MTLBlendFactorOne;
        renderPipelineDesc.colorAttachments[0].sourceAlphaBlendFactor      = MTLBlendFactorOne;
        renderPipelineDesc.colorAttachments[0].destinationRGBBlendFactor   = MTLBlendFactorOneMinusSourceAlpha;
        renderPipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

        renderPipelineDesc.colorAttachments[0].blendingEnabled = YES;
        
        pipelineState = [device newRenderPipelineStateWithDescriptor:renderPipelineDesc  error:&error];
            
        if(!pipelineState || error)
        {
            NSLog(@"Failed to created pipeline state, error %@", error);
            assert(pipelineState);
        }
    }
    [ml_RenderState.renderCommandEncoder setRenderPipelineState:pipelineState];
    if (needCreateDepthState)
    {
        depthState = [device newDepthStencilStateWithDescriptor: depthStateDesc];
        [ml_RenderState.renderCommandEncoder setDepthStencilState:  depthState];
    }

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
    
    MlDataBuffer* dataBuffer = (MlDataBuffer*)screen->mViewpoints;
    
    PerView data;
    data.ModelMatrix       = (activeShader->modelmatrix.mat);
    data.TextureMatrix     = (activeShader->texturematrix.mat);
    data.NormalModelMatrix = (activeShader->normalmodelmatrix.mat);
    auto fb = GetMetalFrameBuffer();
    
    [ml_RenderState.renderCommandEncoder setVertexBytes:&data length:sizeof(data) atIndex:3];
    
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
    uniforms.uTextureMode = activeShader->muTextureMode.val;
    
    [ml_RenderState.renderCommandEncoder setFragmentBytes:&uniforms length:sizeof(Uniforms) atIndex:2];
    
    
    if(MLRenderer->mHWViewpointUniforms != nullptr)
        [ml_RenderState.renderCommandEncoder setVertexBytes:MLRenderer->mHWViewpointUniforms length:sizeof(mtlHWViewpointUniforms) atIndex:4];
    
    
    VSUniforms VSUniform;
    VSUniform.uClipSplit = activeShader->muClipSplit.val;
    VSUniform.uSplitTopPlane = activeShader->muSplitTopPlane.val;
    VSUniform.uInterpolationFactor = activeShader->muInterpolationFactor.val;
    VSUniform.uGlowTopColor = activeShader->muGlowTopColor.val;
    VSUniform.uGlowTopPlane = activeShader->muGlowTopPlane.val;
    VSUniform.uGlowBottomPlane = activeShader->muGlowBottomPlane.val;
    VSUniform.uObjectColor2 = {activeShader->muObjectColor2.mBuffer.r,activeShader->muObjectColor2.mBuffer.g,activeShader->muObjectColor2.mBuffer.b,activeShader->muObjectColor2.mBuffer.a};
    VSUniform.uSplitBottomPlane = activeShader->muSplitBottomPlane.val;
    VSUniform.uGradientBottomPlane = activeShader->muGradientBottomPlane.val;
    VSUniform.uGlowBottomColor = activeShader->muGlowBottomColor.val;
    VSUniform.uGradientTopPlane = activeShader->muGradientTopPlane.val;
    
    [ml_RenderState.renderCommandEncoder setVertexBytes:&VSUniform length:sizeof(VSUniform) atIndex:5];
    
    activeShader->muLightIndex.Set(index);
    return true;
    
}

void MlRenderState::ApplyBuffers()
{
    //if (mVertexBuffer != mCurrentVertexBuffer || mVertexOffsets[0] != mCurrentVertexOffsets[0] || mVertexOffsets[1] != mCurrentVertexOffsets[1])
    if (mVertexBuffer != nullptr)
    {
        //assert(mVertexBuffer != nullptr);
        MlVertexBuffer* mtlBuffer = static_cast<MlVertexBuffer*>(mVertexBuffer);
        //mtlBuffer->Bind(mVertexOffsets);
        //if (mtl_vertexBuffer.length < mtlBuffer->Size())
        //{
        //    //[mtl_vertexBuffer release];
        //    mtl_vertexBuffer = [device newBufferWithBytes:mtlBuffer->mBuffer length:mtlBuffer->Size() options:MTLResourceStorageModeShared];
        //}
        //else
        //{
        //assert(mtl_vertexBuffer.length < mtlBuffer->Size());
        
        float* val = (float*)mtl_vertexBuffer.contents;
        memcpy(val, (float*)mtlBuffer->mBuffer, mtlBuffer->Size());
        //}
        mCurrentVertexBuffer = mVertexBuffer;
        mCurrentVertexOffsets[0] = mVertexOffsets[0];
        mCurrentVertexOffsets[1] = mVertexOffsets[1];
    }
    if (mIndexBuffer != nullptr)
    {
        if (mIndexBuffer)
        {
            MlIndexBuffer* IndxBuffer = static_cast<MlIndexBuffer*>(mIndexBuffer);
            int* arr = (int*)(IndxBuffer->mBuffer);
        }
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
    ml_RenderState.renderCommandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    ml_RenderState.renderCommandEncoder.label = @"ml_RenderState.renderCommandEncoder";
    [ml_RenderState.renderCommandEncoder setFrontFacingWinding:MTLWindingClockwise];
    [ml_RenderState.renderCommandEncoder setCullMode:MTLCullModeNone];
    [ml_RenderState.renderCommandEncoder setViewport:(MTLViewport){0.0, 0.0, (double)GetMetalFrameBuffer()->GetClientWidth(), (double)GetMetalFrameBuffer()->GetClientHeight(), 0.0, 1.0 }];
    CreateFanToTrisIndexBuffer();
    
    if (activeShader == nullptr)
    {
        activeShader = new MlShader();
    }
}

void MlRenderState::CopyVertexBufferAttribute(const MLVertexBufferAttribute *attr)
{
    memcpy(prevAttributeInfo, attr, sizeof(MLVertexBufferAttribute)*6);
}

bool MlRenderState::VertexBufferAttributeWasChange(const MLVertexBufferAttribute *attr)
{
    for (int i = 0; i < 6; i++)
    {
        if (prevAttributeInfo[i].size != attr[i].size)
            return true;
    }
    return false;
}

void MlRenderState::setVertexBuffer(id<MTLBuffer> buffer, size_t index, size_t offset /*= 0*/)
{
    [ml_RenderState.renderCommandEncoder setVertexBuffer:buffer offset:offset atIndex:index];
}

void MlRenderState::EndFrame()
{
    if (MLRenderer->mScreenBuffers->mDrawable)
            [commandBuffer presentDrawable:MLRenderer->mScreenBuffers->mDrawable];
    
    [ml_RenderState.renderCommandEncoder endEncoding];
    [commandBuffer commit];
//    [MLRenderer->mScreenBuffers->mDrawable release];
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

    if (base->BindOrCreate(tex, 0, clampmode, translation, flags, ml_RenderState.renderCommandEncoder))
    {
        for (int i = 1; i<numLayers; i++)
        {
            FTexture *layer;
            auto systex = static_cast<MlHardwareTexture*>(mat->GetLayer(i, 0, &layer));
            systex->BindOrCreate(layer, i, clampmode, 0, mat->isExpanded() ? CTF_Expand : 0, ml_RenderState.renderCommandEncoder);
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
//static int dt2gl[] =            { GL_POINTS,             GL_LINES,             GL_TRIANGLES,             GL_TRIANGLE_FAN,          GL_TRIANGLE_STRIP };

void MlRenderState::Draw(int dt, int index, int count, bool apply)
{
    float* val = (float*)mtl_vertexBuffer.contents;
    MlVertexBuffer* mtlBuffer = static_cast<MlVertexBuffer*>(mVertexBuffer);
    float* vertexBuffer = (float*)mtlBuffer->mBuffer;
    if (apply)
    {
        Apply();
    }
    
    drawcalls.Clock();
    float* buffer = &(((float*)(mtlBuffer->mBuffer))[(mtlBuffer->mStride * index) / 4]);
    if (dt == 3)
    {
        //MlVertexBuffer* mtlBuffer = static_cast<MlVertexBuffer*>(mVertexBuffer);
        //[ml_RenderState.renderCommandEncoder setVertexBuffer:mtl_vertexBuffer offset:mtlBuffer->mStride * index atIndex:0];
        [ml_RenderState.renderCommandEncoder setVertexBytes:buffer length:count * mtlBuffer->mStride atIndex:0];
        [ml_RenderState.renderCommandEncoder drawIndexedPrimitives:dt2ml[dt] indexCount:(count - 2) * 3 indexType:MTLIndexTypeUInt32 indexBuffer:ml_RenderState.fanIndexBuffer indexBufferOffset:0];
    }
    else
    {
        id<MTLBuffer> buff = [device newBufferWithBytes:buffer length:count * mtlBuffer->mStride options:MTLResourceStorageModeShared];
        [ml_RenderState.renderCommandEncoder setVertexBuffer:/*mtl_vertexBuffer*/buff offset:0 atIndex:0];
        [ml_RenderState.renderCommandEncoder drawPrimitives:dt2ml[dt] vertexStart:/*index*/0 vertexCount:count];
        [buff release];
    }
    
    [ml_RenderState.renderCommandEncoder popDebugGroup];
    
    drawcalls.Unclock();
}

void MlRenderState::CreateFanToTrisIndexBuffer()
{
   TArray<uint32_t> data;
    for (int i = 2; i < 1000; i++)
    {
        data.Push(0);
        data.Push(i - 1);
        data.Push(i);
    }
    ml_RenderState.fanIndexBuffer = [device newBufferWithBytes:data.Data() length:sizeof(uint32_t) * data.Size() options:MTLResourceStorageModeShared];
}

void MlRenderState::DrawIndexed(int dt, int index, int count, bool apply)
{
    if (apply)
    {
        Apply();
    }
    drawcalls.Clock();
    
    MlIndexBuffer*  IndexBuffer    = static_cast<MlIndexBuffer*>(mIndexBuffer);
    id<MTLBuffer>   indexBuffer    = [device newBufferWithBytes:(float*)IndexBuffer->mBuffer  length:IndexBuffer->Size()  options:MTLResourceStorageModeShared];
    
    [ml_RenderState.renderCommandEncoder setVertexBuffer:mtl_vertexBuffer offset:0 atIndex:0];
    [ml_RenderState.renderCommandEncoder drawIndexedPrimitives:dt2ml[dt] indexCount:count indexType:MTLIndexTypeUInt32 indexBuffer:indexBuffer indexBufferOffset:(index * sizeof(uint32_t))];
    [ml_RenderState.renderCommandEncoder popDebugGroup];
    
    [indexBuffer release];

    drawcalls.Unclock();
}

void MlRenderState::SetDepthMask(bool on)
{
    if(!on)
    {
        //depthStateDesc.depthWriteEnabled = on;
        //depthStateDesc.depthCompareFunction = MTLCompareFunctionNever;
        //depthStateDesc.frontFaceStencil.stencilCompareFunction    = MTLCompareFunctionNever;
        //depthStateDesc.frontFaceStencil.stencilFailureOperation   = MTLStencilOperationZero;
        //depthStateDesc.frontFaceStencil.depthStencilPassOperation = MTLStencilOperationZero;
        //depthStateDesc.backFaceStencil.stencilCompareFunction    = MTLCompareFunctionNever;
        //depthStateDesc.backFaceStencil.stencilFailureOperation   = MTLStencilOperationZero;
        //depthStateDesc.backFaceStencil.depthStencilPassOperation = MTLStencilOperationZero;
    }
}

void MlRenderState::SetDepthFunc(int func)
{
    static MTLCompareFunction df2ml[] = { MTLCompareFunctionLess, MTLCompareFunctionLess, MTLCompareFunctionAlways };
    //                                  {         GL_LESS,                GL_LEQUAL,                   GL_ALWAYS };
    depthCompareFunc = df2ml[func];
    depthStateDesc.depthCompareFunction = depthCompareFunc;
    needCreateDepthState = true;
}

void MlRenderState::SetDepthRange(float min, float max)
{
    //glDepthRange(min, max);
}

void MlRenderState::SetColorMask(bool r, bool g, bool b, bool a)
{
    //glColorMask(r, g, b, a);
}

void MlRenderState::SetStencil(int offs, int op, int flags = -1)
{
    static MTLStencilOperation op2ml[] = { MTLStencilOperationKeep, MTLStencilOperationIncrementClamp, MTLStencilOperationDecrementClamp };
    //                                          { GL_KEEP,                        GL_INCR,                          GL_DECR };
    depthStateDesc.frontFaceStencil.stencilCompareFunction    = MTLCompareFunctionEqual;
    depthStateDesc.frontFaceStencil.stencilFailureOperation   = MTLStencilOperationKeep;
    depthStateDesc.frontFaceStencil.depthStencilPassOperation = op2ml[op];
    //depthStateDesc.frontFaceStencil.readMask  = 0xff;
    //depthStateDesc.frontFaceStencil.writeMask = 0xff;
    //depthStateDesc.backFaceStencil.readMask   = 0xff;
    //depthStateDesc.backFaceStencil.writeMask  = 0xff;
    depthStateDesc.backFaceStencil.stencilCompareFunction    = MTLCompareFunctionEqual;
    depthStateDesc.backFaceStencil.stencilFailureOperation   = MTLStencilOperationKeep;
    depthStateDesc.backFaceStencil.depthStencilPassOperation = op2ml[op];
    
    
    [ml_RenderState.renderCommandEncoder setStencilReferenceValue:screen->stencilValue + offs ];
    needCreateDepthState = true;
    
    //MLRenderer->loadDepthStencil = true;
    //glStencilFunc(GL_EQUAL, screen->stencilValue + offs, ~0);        // draw sky into stencil
    //glStencilOp(GL_KEEP, GL_KEEP, op2gl[op]);        // this stage doesn't modify the stencil

    //if (flags != -1)
    //{
    //    bool cmon = !(flags & SF_ColorMaskOff);
    //    glColorMask(cmon, cmon, cmon, cmon);                        // don't write to the graphics buffer
    //    glDepthMask(!(flags & SF_DepthMaskOff));
    //}
}

void MlRenderState::ToggleState(int state, bool on)
{
    if (on)
    {
    //    glEnable(state);
    }
    //else
    //{
    //    glDisable(state);
    //}
}

void MlRenderState::SetCulling(int mode)
{
    //if (mode != Cull_None)
    //{
    //    glEnable(GL_CULL_FACE);
    //    glFrontFace(mode == Cull_CCW ? GL_CCW : GL_CW);
    //}
    //else
    //{
    //    glDisable(GL_CULL_FACE);
    //}
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
    if (targets)
    {
        
    }
    //{
    //    gltarget |= GL_DEPTH_BUFFER_BIT;
    //    glClearDepth(1);
    //}
    //if (targets & CT_Stencil)
    //{
    //    gltarget |= GL_STENCIL_BUFFER_BIT;
    //    glClearStencil(0);
    //}
    //if (targets & CT_Color)
    //{
    //    gltarget |= GL_COLOR_BUFFER_BIT;
    //    glClearColor(screen->mSceneClearColor[0], screen->mSceneClearColor[1], screen->mSceneClearColor[2], screen->mSceneClearColor[3]);
    //}
    //glClear(gltarget);
}

void MlRenderState::EnableStencil(bool on)
{
    if (!on)
        depthStateDesc.frontFaceStencil.stencilCompareFunction = MTLCompareFunctionNever;
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
    m_Viewport.znear = 0.0f;
    m_Viewport.zfar = 1.0f;
    
    [ml_RenderState.renderCommandEncoder setViewport:m_Viewport];
}

void MlRenderState::EnableDepthTest(bool on)
{
    depthStateDesc.depthWriteEnabled  = on;
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
    //if (!on) glDisable(GL_DEPTH_CLAMP);
    //else glEnable(GL_DEPTH_CLAMP);
    mLastDepthClamp = on;
    return res;
}

}
