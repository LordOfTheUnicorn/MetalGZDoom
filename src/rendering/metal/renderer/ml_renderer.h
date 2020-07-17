
#ifndef __GL_RENDERER_H
#define __GL_RENDERER_H

#include "r_defs.h"
#include "v_video.h"
#include "vectors.h"
#include "swrenderer/r_renderer.h"
#include "matrix.h"
#include "metal/renderer/ml_renderbuffers.h"
#include "metal/system/ml_framebuffer.h"
#include "hwrenderer/scene/hw_portal.h"
#include "hwrenderer/dynlights/hw_shadowmap.h"
#include "hwrenderer/postprocessing/hw_postprocess.h"
#include <functional>

#import "Metal/Metal.h"

#ifdef _MSC_VER
#pragma warning(disable:4244)
#endif

struct particle_t;
class FCanvasTexture;
class FFlatVertexBuffer;
class FSkyVertexBuffer;
class FShaderManager;
class HWPortal;
class FLightBuffer;
class DPSprite;
class FGLRenderBuffers;
class FGL2DDrawer;
class FHardwareTexture;
class SWSceneDrawer;
class HWViewpointBuffer;
struct FRenderViewpoint;

namespace MetalRenderer
{
class MetalFrameBuffer;

struct mtlHWViewpointUniforms
{
    mtlHWViewpointUniforms()
    {
        mProjectionMatrix = matrix_float4x4{0};
        mViewMatrix = matrix_float4x4{0};
        mNormalViewMatrix = matrix_float4x4{0};
        mCameraPos = vector_float4{0.f,0.f,0.f,0.f};
        mClipLine  = vector_float4{0.f,0.f,0.f,0.f};
        
        mGlobVis = 1.f;
        mPalLightLevels = 0;
        mViewHeight = 0;
        mClipHeight = 0.f;
        mClipHeightDirection = 0.f;
        mShadowmapFilter = 1;
    }
    ~mtlHWViewpointUniforms() = default;
    
    matrix_float4x4 mProjectionMatrix;
    matrix_float4x4 mViewMatrix;
    matrix_float4x4 mNormalViewMatrix;
    vector_float4   mCameraPos;
    vector_float4   mClipLine;

    float   mGlobVis;
    int     mPalLightLevels;
    int     mViewHeight;
    float   mClipHeight;
    float   mClipHeightDirection;
    int     mShadowmapFilter;
};

class MlRenderer
{
public:

    MetalFrameBuffer *framebuffer;
    int mMirrorCount = 0;
    int mPlaneMirrorCount = 0;
    MlShaderManager *mShaderManager = nullptr;
    MlSamplerManager *mSamplerManager = nullptr;
    unsigned int mFBID;
    unsigned int mVAOID;
    unsigned int PortalQueryObject;
    unsigned int mStencilValue = 0;
    
    mtlHWViewpointUniforms *mHWViewpointUniforms;

    int mOldFBID;

    MlRenderBuffers *mBuffers = nullptr;
    MlRenderBuffers *mScreenBuffers = nullptr;
    MlRenderBuffers *mSaveBuffers = nullptr;
    PresentUniforms *mPresentShader = nullptr;;
    MlShaderProgram *mPresent3dCheckerShader = nullptr;
    MlShaderProgram *mPresent3dColumnShader = nullptr;
    MlShaderProgram *mPresent3dRowShader = nullptr;
    //FShadowMapShader *mShadowMapShader = nullptr;
    bool loadDepthStencil : 1;

    //FRotator mAngles;

    SWSceneDrawer *swdrawer = nullptr;

    MlRenderer(MetalFrameBuffer *fb);
    ~MlRenderer();

    void Initialize(int width, int height, id<MTLDevice> device);

    void ClearBorders();

    void ResetSWScene();

    void PresentStereo();
    void RenderScreenQuad();
    void PostProcessScene(int fixedcm, const std::function<void()> &afterBloomDrawEndScene2D){};
    void AmbientOccludeScene(float m5){};
    void ClearTonemapPalette();
    void BlurScene(float gameinfobluramount);
    void CopyToBackbuffer(const IntRect *bounds, bool applyGamma);
    void DrawPresentTexture(const IntRect &box, bool applyGamma);
    void Flush();
    void Draw2D(F2DDrawer *data);
    void RenderTextureView(FCanvasTexture *tex, AActor *Viewpoint, double FOV);
    void WriteSavePic(player_t *player, FileWriter *file, int width, int height);
    sector_t *RenderView(player_t *player);
    void BeginFrame();
    
    sector_t *RenderViewpoint (FRenderViewpoint &mainvp, AActor * camera, IntRect * bounds, float fov, float ratio, float fovratio, bool mainview, bool toscreen);


    bool StartOffscreen();
    void EndOffscreen();
    void UpdateShadowMap();

    void BindToFrameBuffer(FMaterial *mat);

private:

    void DrawScene(HWDrawInfo *di, int drawmode);
    bool QuadStereoCheckInitialRenderContextState();
    void PresentAnaglyph(bool r, bool g, bool b);
    void PresentSideBySide();
    void PresentTopBottom();
   // void prepareInterleavedPresent(FPresentShaderBase& shader);
    void PresentColumnInterleaved();
    void PresentRowInterleaved();
    void PresentCheckerInterleaved();
    void PresentQuadStereo();

};

struct TexFilter_s
{
    int minfilter;
    int magfilter;
    bool mipmapping;
} ;

extern MlRenderer *MLRenderer;
}
#endif
