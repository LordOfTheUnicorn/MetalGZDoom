//
//---------------------------------------------------------------------------
//
// Copyright(C) 2016 Magnus Norddahl
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
** gl_postprocess.cpp
** Post processing effects in the render pipeline
**
*/

#include "gl_load/gl_system.h"
#include "gi.h"
#include "m_png.h"
#include "r_utility.h"
#include "d_player.h"
#include "metal/system/ml_buffer.h"
#include "metal/system/ml_framebuffer.h"
#include "hwrenderer/utility/hw_cvars.h"
#include "metal/renderer/ml_renderstate.h"
#include "metal/renderer/ml_renderbuffers.h"
#include "metal/renderer/ml_renderer.h"
#include "metal/renderer/ml_postprocessstate.h"
//#include "ml/shaders/gl_shaderprogram.h"
#include "hwrenderer/postprocessing/hw_postprocess.h"
#include "hwrenderer/postprocessing/hw_postprocess_cvars.h"
#include "hwrenderer/utility/hw_vrmodes.h"
#include "hwrenderer/data/flatvertices.h"
//#include "gl/textures/gl_hwtexture.h"
#include "r_videoscale.h"

extern bool vid_hdr_active;

CVAR(Int, ml_dither_bpc, 0, CVAR_ARCHIVE | CVAR_GLOBALCONFIG | CVAR_NOINITCALL)

namespace MetalRenderer
{

//void MlRenderer::RenderScreenQuad()
//{
//    auto buffer = static_cast<GLVertexBuffer *>(screen->mVertexData->GetBufferObjects().first);
//    buffer->Bind(nullptr);
//    glDrawArrays(GL_TRIANGLE_STRIP, FFlatVertexBuffer::PRESENT_INDEX, 4);
//}

//-----------------------------------------------------------------------------
//
// Adds ambient occlusion to the scene
//
//-----------------------------------------------------------------------------

void MlRenderer::AmbientOccludeScene(float m5)
{
    int sceneWidth = mBuffers->GetSceneWidth();
    int sceneHeight = mBuffers->GetSceneHeight();

    MLPPRenderState renderstate(mBuffers);
    hw_postprocess.ssao.Render(&renderstate, m5, sceneWidth, sceneHeight);
}

void MlRenderer::BlurScene(float gameinfobluramount)
{
    int sceneWidth = mBuffers->GetSceneWidth();
    int sceneHeight = mBuffers->GetSceneHeight();

    MLPPRenderState renderstate(mBuffers);

    auto vrmode = VRMode::GetVRMode(true);
    int eyeCount = vrmode->mEyeCount;
    for (int i = 0; i < eyeCount; ++i)
    {
        hw_postprocess.bloom.RenderBlur(&renderstate, sceneWidth, sceneHeight, gameinfobluramount);
        if (eyeCount - i > 1) mBuffers->NextEye(eyeCount);
    }
}

void MlRenderer::ClearTonemapPalette()
{
    hw_postprocess.tonemap.ClearTonemapPalette();
}

//-----------------------------------------------------------------------------
//
// Copies the rendered screen to its final destination
//
//-----------------------------------------------------------------------------

void MlRenderer::Flush()
{
    auto vrmode = VRMode::GetVRMode(true);
    if (vrmode->mEyeCount == 1)
    {
        CopyToBackbuffer(nullptr, true);
    }
    else
    {
        // Render 2D to eye textures
        int eyeCount = vrmode->mEyeCount;
        for (int eye_ix = 0; eye_ix < eyeCount; ++eye_ix)
        {
            screen->Draw2D();
            if (eyeCount - eye_ix > 1)
                mBuffers->NextEye(eyeCount);
        }
        screen->Clear2D();

        //FGLPostProcessState savedState;
        //FGLDebug::PushGroup("PresentEyes");
        // Note: This here is the ONLY place in the entire engine where the OpenGL dependent parts of the Stereo3D code need to be dealt with.
        // There's absolutely no need to create a overly complex class hierarchy for just this.
        PresentStereo();
        //FGLDebug::PopGroup();
    }
}

//-----------------------------------------------------------------------------
//
// Gamma correct while copying to frame buffer
//
//-----------------------------------------------------------------------------

void MlRenderer::CopyToBackbuffer(const IntRect *bounds, bool applyGamma)
{
    screen->Draw2D();    // draw all pending 2D stuff before copying the buffer
    screen->Clear2D();

    MLPPRenderState renderstate(mBuffers);
    hw_postprocess.customShaders.Run(&renderstate, "screen");

    //FGLDebug::PushGroup("CopyToBackbuffer");
    //FGLPostProcessState savedState;
    //savedState.SaveTextureBindings(2);
    //mBuffers->BindOutputFB();

    IntRect box;
    if (bounds)
    {
        box = *bounds;
    }
    else
    {
        ClearBorders();
        box = screen->mOutputLetterbox;
    }

    //mBuffers->BindC urrentTexture(0);
    DrawPresentTexture(box, applyGamma);
    //FGLDebug::PopGroup();
}

void MlRenderer::DrawPresentTexture(const IntRect &box, bool applyGamma)
{
    //glViewport(box.left, box.top, box.width, box.height);

    //mBuffers->BindDitherTexture(1);

    //glActiveTexture(GL_TEXTURE0);
    //if (ViewportLinearScale())
    //{
    //    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    //    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    //}
    //else
    //{
    //    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    //    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    //}

    //mPresentShader->Bind();
    if (!applyGamma || framebuffer->IsHWGammaActive())
    {
        mPresentShader->InvGamma = 1.0f;
        mPresentShader->Contrast = 1.0f;
        mPresentShader->Brightness = 0.0f;
        mPresentShader->Saturation = 1.0f;
    }
    else
    {
        mPresentShader->InvGamma = 1.0f / clamp<float>(Gamma, 0.1f, 4.f);
        mPresentShader->Contrast = clamp<float>(vid_contrast, 0.1f, 3.f);
        mPresentShader->Brightness = clamp<float>(vid_brightness, -0.8f, 0.8f);
        mPresentShader->Saturation = clamp<float>(vid_saturation, -15.0f, 15.f);
        mPresentShader->GrayFormula = static_cast<int>(gl_satformula);
    }
    if (vid_hdr_active && framebuffer->IsFullscreen())
    {
        // Full screen exclusive mode treats a rgba16f frame buffer as linear.
        // It probably will eventually in desktop mode too, but the DWM doesn't seem to support that.
        mPresentShader->HdrMode = 1;
        mPresentShader->ColorScale = (ml_dither_bpc == -1) ? 1023.0f : (float)((1 << ml_dither_bpc) - 1);
    }
    else
    {
        mPresentShader->HdrMode = 0;
        mPresentShader->ColorScale = (ml_dither_bpc == -1) ? 255.0f : (float)((1 << ml_dither_bpc) - 1);
    }
    mPresentShader->Scale = { screen->mScreenViewport.width / (float)mBuffers->GetWidth(), screen->mScreenViewport.height / (float)mBuffers->GetHeight() };
    mPresentShader->Offset = { 0.0f, 0.0f };
    //mPresentShader->SetData();
    //static_cast<MlBuffer*>(mPresentShader)->BindBase();
    RenderScreenQuad();
}

//-----------------------------------------------------------------------------
//
// Fills the black bars around the screen letterbox
//
//-----------------------------------------------------------------------------

void MlRenderer::ClearBorders()
{
    const auto &box = screen->mOutputLetterbox;

    int clientWidth = framebuffer->GetClientWidth();
    int clientHeight = framebuffer->GetClientHeight();
    if (clientWidth == 0 || clientHeight == 0)
        return;

    //glViewport(0, 0, clientWidth, clientHeight);
    //glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    //glEnable(GL_SCISSOR_TEST);
    //if (box.top > 0)
    //{
    //    glScissor(0, 0, clientWidth, box.top);
    //    glClear(GL_COLOR_BUFFER_BIT);
    //}
    //if (clientHeight - box.top - box.height > 0)
    //{
    //    glScissor(0, box.top + box.height, clientWidth, clientHeight - box.top - box.height);
    //    glClear(GL_COLOR_BUFFER_BIT);
    //}
    //if (box.left > 0)
    //{
    //    glScissor(0, box.top, box.left, box.height);
    //    glClear(GL_COLOR_BUFFER_BIT);
    //}
    //if (clientWidth - box.left - box.width > 0)
    //{
    //    glScissor(box.left + box.width, box.top, clientWidth - box.left - box.width, box.height);
    //    glClear(GL_COLOR_BUFFER_BIT);
    //}
    //glDisable(GL_SCISSOR_TEST);
}

}

