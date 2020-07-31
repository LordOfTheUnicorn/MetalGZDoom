//
//---------------------------------------------------------------------------
//
// Copyright(C) 2005-2016 Christoph Oelckers
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
** gl1_renderer.cpp
** Renderer interface
**
*/

//#include "gl_load/gl_system.h"
#include "files.h"
#include "v_video.h"
#include "m_png.h"
#include "w_wad.h"
#include "doomstat.h"
#include "i_time.h"
#include "p_effect.h"
#include "d_player.h"
#include "a_dynlight.h"
#include "cmdlib.h"
#include "g_game.h"
#include "swrenderer/r_swscene.h"
#include "hwrenderer/utility/hw_clock.h"

//#include "gl_load/gl_interface.h"
#include "metal/system/ml_framebuffer.h"
#include "hwrenderer/utility/hw_cvars.h"
//#include "gl/system/gl_debug.h"
#include "metal/renderer/ml_renderer.h"
#include "metal/renderer/ml_RenderState.h"
#include "metal/renderer/ml_renderbuffers.h"
#include "metal/shaders/ml_shader.h"
#include "metal/textures/ml_hwtexture.h"
#include "hwrenderer/utility/hw_vrmodes.h"
#include "hwrenderer/data/flatvertices.h"
#include "hwrenderer/scene/hw_skydome.h"
#include "hwrenderer/scene/hw_fakeflat.h"
#include "metal/textures/ml_samplers.h"
#include "hwrenderer/dynlights/hw_lightbuffer.h"
#include "hwrenderer/data/hw_viewpointbuffer.h"
#include "hwrenderer/postprocessing/hw_postprocess.h"
#include "hwrenderer/postprocessing/hw_postprocess_cvars.h"
#include "r_videoscale.h"
#include "r_data/models/models.h"
//#include "gl/renderer/gl_postprocessstate.h"
#include "metal/system/ml_buffer.h"
#include "metal/system/ml_framebuffer.h"

#import "Metal/Metal.h"

EXTERN_CVAR(Int, screenblocks)
EXTERN_CVAR(Bool, cl_capfps)
CVAR(Int, ml_dither_bpc, 0, CVAR_ARCHIVE | CVAR_GLOBALCONFIG | CVAR_NOINITCALL)

extern bool NoInterpolateView;
extern bool vid_hdr_active;

void DoWriteSavePic(FileWriter *file, ESSType ssformat, uint8_t *scr, int width, int height, sector_t *viewsector, bool upsidedown);

namespace MetalRenderer
{

 MlRenderer *MLRenderer;

//===========================================================================
//
// Renderer interface
//
//===========================================================================

//-----------------------------------------------------------------------------
//
// Initialize
//
//-----------------------------------------------------------------------------

MlRenderer::MlRenderer(MetalFrameBuffer *fb)
{
    framebuffer = fb;
    ml_RenderState = new MlRenderState();
    if (ml_RenderState)
        ml_RenderState->InitialaziState();
    mHWViewpointUniforms = new mtlHWViewpointUniforms();
    loadDepthStencil = false;
    semaphore = dispatch_semaphore_create(3);
}

void MlRenderer::Initialize(int width, int height, id<MTLDevice> device)
{
    mScreenBuffers = new MlRenderBuffers();
    mSaveBuffers = new MlRenderBuffers();
    mBuffers = mScreenBuffers;
    mPresentShader = new PresentUniforms();
    mPresent3dCheckerShader = new MlShaderProgram();
    mPresent3dColumnShader = new MlShaderProgram();
    mPresent3dRowShader = new MlShaderProgram();
    //mShadowMapShader = new FShadowMapShader();

    // needed for the core profile, because someone decided it was a good idea to remove the default VAO.
    //glGenQueries(1, &PortalQueryObject);

    //glGenVertexArrays(1, &mVAOID);
    //glBindVertexArray(mVAOID);
    //FGLDebug::LabelObject(GL_VERTEX_ARRAY, mVAOID, "FGLRenderer.mVAOID");

    mFBID = 0;
    mOldFBID = 0;

    mShaderManager = new MlShaderManager();
    mSamplerManager = new MlSamplerManager(device);
}

MlRenderer::~MlRenderer()
{
    FlushModels();
    TexMan.FlushAll();
    if (mShaderManager != nullptr)
        delete mShaderManager;
    
    if (mSamplerManager != nullptr)
        delete mSamplerManager;
    
    if (swdrawer)
        delete swdrawer;
    
    if (mBuffers)
        delete mBuffers;
    
    if (mSaveBuffers)
        delete mSaveBuffers;
    
    if (mPresentShader)
        delete mPresentShader;
    
    if (mPresent3dCheckerShader)
        delete mPresent3dCheckerShader;
    
    if (mPresent3dColumnShader)
        delete mPresent3dColumnShader;
    
    if (mPresent3dRowShader)
        delete mPresent3dRowShader;
    
    //if (mShadowMapShader)
    //    delete mShadowMapShader;
    
    if (ml_RenderState)
        delete ml_RenderState;
}

//===========================================================================
//
//
//
//===========================================================================

void MlRenderer::ResetSWScene()
{
    // force recreation of the SW scene drawer to ensure it gets a new set of resources.
    if (swdrawer != nullptr)
        delete swdrawer;
    
    swdrawer = nullptr;
}

//===========================================================================
//
//
//
//===========================================================================

bool MlRenderer::StartOffscreen()
{
    //bool firstBind = (mFBID == 0);
    //if (mFBID == 0)
    //    glGenFramebuffers(1, &mFBID);
    //glGetIntegerv(GL_FRAMEBUFFER_BINDING, &mOldFBID);
    //glBindFramebuffer(GL_FRAMEBUFFER, mFBID);
    //if (firstBind)
    //    FGLDebug::LabelObject(GL_FRAMEBUFFER, mFBID, "OffscreenFB");
    //return true;
}

//===========================================================================
//
//
//
//===========================================================================

void MlRenderer::EndOffscreen()
{
    //glBindFramebuffer(GL_FRAMEBUFFER, mOldFBID);
}

//===========================================================================
//
//
//
//===========================================================================

void MlRenderer::UpdateShadowMap()
{
    //if (screen->mShadowMap.PerformUpdate())
    //{
    //    FGLDebug::PushGroup("ShadowMap");

    //    FGLPostProcessState savedState;

    //    static_cast<GLDataBuffer*>(screen->mShadowMap.mLightList)->BindBase();
    //    static_cast<GLDataBuffer*>(screen->mShadowMap.mNodesBuffer)->BindBase();
    //    static_cast<GLDataBuffer*>(screen->mShadowMap.mLinesBuffer)->BindBase();

    //    mBuffers->BindShadowMapFB();

    //    mShadowMapShader->Bind();
    //    mShadowMapShader->Uniforms->ShadowmapQuality = gl_shadowmap_quality;
    //    mShadowMapShader->Uniforms->NodesCount = screen->mShadowMap.NodesCount();
    //    mShadowMapShader->Uniforms.SetData();
    //    static_cast<GLDataBuffer*>(mShadowMapShader->Uniforms.GetBuffer())->BindBase();

    //    glViewport(0, 0, gl_shadowmap_quality, 1024);
    //    RenderScreenQuad();

    //    const auto &viewport = screen->mScreenViewport;
    //    glViewport(viewport.left, viewport.top, viewport.width, viewport.height);

    //    mBuffers->BindShadowMapTexture(16);
    //    FGLDebug::PopGroup();
    //    screen->mShadowMap.FinishUpdate();
    //}
}

//-----------------------------------------------------------------------------
//
// renders the view
//
//-----------------------------------------------------------------------------

sector_t *MlRenderer::RenderView(player_t* player)
{
    ml_RenderState->SetVertexBuffer(screen->mVertexData);
    screen->mVertexData->Reset();
    sector_t *retsec;

    if (!V_IsHardwareRenderer())
    {
        if (swdrawer == nullptr)
            swdrawer = new SWSceneDrawer;
        
        retsec = swdrawer->RenderView(player);
    }
    else
    {
        hw_ClearFakeFlat();

        iter_dlightf = iter_dlight = draw_dlight = draw_dlightf = 0;

        checkBenchActive();

        // reset statistics counters
        ResetProfilingData();

        // Get this before everything else
        if (cl_capfps || r_NoInterpolate) r_viewpoint.TicFrac = 1.;
        else r_viewpoint.TicFrac = I_GetTimeFrac();

        screen->mLights->Clear();
        screen->mViewpoints->Clear();

        // NoInterpolateView should have no bearing on camera textures, but needs to be preserved for the main view below.
        bool saved_niv = NoInterpolateView;
        NoInterpolateView = false;

        // Shader start time does not need to be handled per level. Just use the one from the camera to render from.
        ml_RenderState->CheckTimer(player->camera->Level->ShaderStartTime);
        // prepare all camera textures that have been used in the last frame.
        // This must be done for all levels, not just the primary one!
        for (auto Level : AllLevels())
        {
            Level->canvasTextureInfo.UpdateAll([&](AActor *camera, FCanvasTexture *camtex, double fov)
            {
                RenderTextureView(camtex, camera, fov);
            });
        }
        NoInterpolateView = saved_niv;


        // now render the main view
        float fovratio;
        float ratio = r_viewwindow.WidescreenRatio;
        if (r_viewwindow.WidescreenRatio >= 1.3f)
        {
            fovratio = 1.333333f;
        }
        else
        {
            fovratio = ratio;
        }

        retsec = RenderViewpoint(r_viewpoint, player->camera, NULL, r_viewpoint.FieldOfView.Degrees, ratio, fovratio, true, true);
    }
    All.Unclock();
    return retsec;
}

//===========================================================================
//
//
//
//===========================================================================

void MlRenderer::BindToFrameBuffer(FMaterial *mat)
{
    auto BaseLayer = static_cast<IHardwareTexture*>(mat->GetLayer(0, 0));

    //if (BaseLayer == nullptr)
    //{
    //    // must create the hardware texture first
    //    BaseLayer->BindOrCreate(mat->sourcetex, 0, 0, 0, 0);
    //    FHardwareTexture::Unbind(0);
    //  //  gl_RenderState.ClearLastMaterial();
    //}
    //BaseLayer->BindToFrameBuffer(mat->GetWidth(), mat->GetHeight());
}

//===========================================================================
//
// Camera texture rendering
//
//===========================================================================

void MlRenderer::RenderTextureView(FCanvasTexture *tex, AActor *Viewpoint, double FOV)
{
    // This doesn't need to clear the fake flat cache. It can be shared between camera textures and the main view of a scene.
    FMaterial * mltex = FMaterial::ValidateTexture(tex, false);

    int width = mltex->TextureWidth();
    int height = mltex->TextureHeight();

    StartOffscreen();
    BindToFrameBuffer(mltex);

    IntRect bounds;
    bounds.left = bounds.top = 0;
    
    
    
    bounds.width  = 1440;//mltex->GetWidth();
    bounds.height = 900;//mltex->GetHeight();

    FRenderViewpoint texvp;
    RenderViewpoint(texvp, Viewpoint, &bounds, FOV, (float)width / height, (float)width / height, false, false);

    EndOffscreen();

    tex->SetUpdated(true);
    static_cast<MetalFrameBuffer*>(screen)->camtexcount++;
}

//===========================================================================
//
// Render the view to a savegame picture
//
//===========================================================================
void MlRenderer::CopyToBackbuffer(const IntRect *bounds, bool applyGamma)
{
    screen->Draw2D();    // draw all pending 2D stuff before copying the buffer
    screen->Clear2D();

    MlRenderState renderstate(mBuffers);
    //hw_postprocess.customShaders.Run(&renderstate, "screen");

    //FGLPostProcessState savedState;
    //savedState.SaveTextureBindings(2);

    IntRect box;
    if (bounds)
    {
        box = *bounds;
    }
    else
    {
        //ClearBorders();
        box = screen->mOutputLetterbox;
    }
    
    //mBuffers->BindCurrentTexture(0);
    DrawPresentTexture(box, applyGamma);
}

void MlRenderer::Flush()
{
    //auto vrmode = VRMode::GetVRMode(true);
    //if (vrmode->mEyeCount == 1)
    //{
        CopyToBackbuffer(nullptr, true);
    //}
    //else
    //{
        // Render 2D to eye textures
        //int eyeCount = vrmode->mEyeCount;
        //for (int eye_ix = 0; eye_ix < eyeCount; ++eye_ix)
        //{
        //    screen->Draw2D();
        //    if (eyeCount - eye_ix > 1)
        //        mBuffers->NextEye(eyeCount);
        //}
        //screen->Clear2D();

        //FGLPostProcessState savedState;
        //FGLDebug::PushGroup("PresentEyes");
        // Note: This here is the ONLY place in the entire engine where the OpenGL dependent parts of the Stereo3D code need to be dealt with.
        // There's absolutely no need to create a overly complex class hierarchy for just this.
        //PresentStereo();
        //FGLDebug::PopGroup();
    //}
}

void MlRenderer::RenderScreenQuad()
{
    //auto buffer = static_cast<MlVertexBuffer *>(screen->mVertexData->GetBufferObjects().first);
    //buffer->Bind(nullptr);
    //glDrawArrays(GL_TRIANGLE_STRIP, FFlatVertexBuffer::PRESENT_INDEX, 4);
}

void MlRenderer::DrawPresentTexture(const IntRect &box, bool applyGamma)
{
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
    RenderScreenQuad();
}


void MetalFrameBuffer::CleanForRestart()
{
    if (MLRenderer)
        MLRenderer->ResetSWScene();
}

void MlRenderer::WriteSavePic(player_t *player, FileWriter *file, int width, int height)
{
    IntRect bounds;
    bounds.left = 0;
    bounds.top = 0;
    bounds.width = width;
    bounds.height = height;
    
    // we must be sure the GPU finished reading from the buffer before we fill it with new data.
    //glFinish();
    
    // Switch to render buffers dimensioned for the savepic
    mBuffers = mSaveBuffers;
    
    hw_ClearFakeFlat();
    ml_RenderState->SetVertexBuffer(screen->mVertexData);
    screen->mVertexData->Reset();
    screen->mLights->Clear();
    screen->mViewpoints->Clear();

    // This shouldn't overwrite the global viewpoint even for a short time.
    FRenderViewpoint savevp;
    sector_t *viewsector = RenderViewpoint(savevp, players[consoleplayer].camera, &bounds, r_viewpoint.FieldOfView.Degrees, 1.6f, 1.6f, true, false);
    //glDisable(GL_STENCIL_TEST);
    ml_RenderState->SetNoSoftLightLevel();
    CopyToBackbuffer(&bounds, false);
    
    // strictly speaking not needed as the glReadPixels should block until the scene is rendered, but this is to safeguard against shitty drivers
    //glFinish();
    
    int numpixels = width * height;
    uint8_t * scr = (uint8_t *)M_Malloc(numpixels * 3);
    //glReadPixels(0,0,width, height,GL_RGB,GL_UNSIGNED_BYTE,scr);

    DoWriteSavePic(file, SS_RGB, scr, width, height, viewsector, true);
    M_Free(scr);
    
    // Switch back the screen render buffers
    screen->SetViewportRects(nullptr);
    mBuffers = mScreenBuffers;
}

//===========================================================================
//
//
//
//===========================================================================

void MlRenderer::BeginFrame()
{
    mScreenBuffers->Setup(screen->mScreenViewport.width, screen->mScreenViewport.height, screen->mSceneViewport.width, screen->mSceneViewport.height);
    mSaveBuffers->Setup(SAVEPICWIDTH, SAVEPICHEIGHT, SAVEPICWIDTH, SAVEPICHEIGHT);
}

}

