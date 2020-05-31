#pragma once

#include <memory>
#import <Metal/Metal.h>

#include "utility/vectors.h"
#include "matrix.h"
#include "name.h"
#include "hwrenderer/scene/hw_renderstate.h"
#import <simd/simd.h>
#include "hwrenderer/data/flatvertices.h"

//class VulkanDevice;
//class VulkanShader;

namespace MetalRenderer
{

class FUniform1i
{
public:
    int val;
    void Set(int v)
    {val = v;}
};

class FBufferedUniform1i
{
public:
    int val;
    void Set(int v)
    {val = v;}
};

class FBufferedUniform4i
{
public:
    vector_int4 val;
    void Set(vector_int4 v)
    {val = v;}
};

class FBufferedUniform1f
{
public:
    float val;
    void Set(float v)
    {val = v;}
};

class FBufferedUniform2f
{
public:
    vector_float2 val;
    void Set(vector_float2 v)
    {val = v;}
};

class FBufferedUniform4f
{
public:
    vector_float4 val;
    void Set(vector_float4 v)
    {val = v;}
};

class FUniform4f
{
public:
    vector_float4 val;
    void Set(vector_float4 v)
    {val = v;}
};

class FBufferedUniformPE
{
public:
    FVector4PalEntry mBuffer;
    void Set(FVector4PalEntry v)
    {mBuffer = v;}
};

class MetalMatrixFloat4x4
{
public:
    matrix_float4x4 mat;
    void matrixToMetal (VSMatrix vs)
    {
        mat = matrix_float4x4{simd_float4{vs.mMatrix[0],vs.mMatrix[1],vs.mMatrix[2],vs.mMatrix[3]},
            simd_float4{vs.mMatrix[4],vs.mMatrix[5],vs.mMatrix[6],vs.mMatrix[7]},
            simd_float4{vs.mMatrix[8],vs.mMatrix[9],vs.mMatrix[10],vs.mMatrix[11]},
            simd_float4{vs.mMatrix[12],vs.mMatrix[13],vs.mMatrix[14],vs.mMatrix[15]}};
    }
};

class MlShader
{
    friend class MlShaderCollection;
    friend class MlRenderState;

    unsigned int hShader;
    unsigned int hVertProg;
    unsigned int hFragProg;
    FName mName;

    FBufferedUniform1f muDesaturation;
    FBufferedUniform1i muFogEnabled;
    FBufferedUniform1i muTextureMode;
    FBufferedUniform4f muLightParms;
    FBufferedUniform2f muClipSplit;
    FBufferedUniform1i muLightIndex;
    FBufferedUniformPE muFogColor;
    FBufferedUniform4f muDynLightColor;
    FBufferedUniformPE muObjectColor;
    FBufferedUniformPE muObjectColor2;
    FBufferedUniformPE muAddColor;
    FUniform4f muGlowBottomColor;
    FUniform4f muGlowTopColor;
    FUniform4f muGlowBottomPlane;
    FUniform4f muGlowTopPlane;
    FUniform4f muGradientBottomPlane;
    FUniform4f muGradientTopPlane;
    FUniform4f muSplitBottomPlane;
    FUniform4f muSplitTopPlane;
    FBufferedUniform1f muInterpolationFactor;
    FBufferedUniform1f muAlphaThreshold;
    FBufferedUniform2f muSpecularMaterial;
    FBufferedUniform1f muTimer;
    
    int lights_index;
    MetalMatrixFloat4x4 modelmatrix;
    MetalMatrixFloat4x4 normalmodelmatrix;
    MetalMatrixFloat4x4 texturematrix;

    int currentglowstate = 0;
    int currentgradientstate = 0;
    int currentsplitstate = 0;
    int currentcliplinestate = 0;
    int currentfixedcolormap = 0;
    bool currentTextureMatrixState = true;// by setting the matrix state to 'true' it is guaranteed to be set the first time the render state gets applied.
    bool currentModelMatrixState = true;

public:
    id<MTLRenderPipelineState> pipelineState;
    id<MTLDepthStencilState> depthState;
    
    MlShader(const char *name)
        : mName(name)
    {
        hShader = hVertProg = hFragProg = 0;
    }
    
    MlShader() = default;


    virtual ~MlShader(){};

    bool Load(const char * name, const char * vert_prog_lump, const char * fragprog, const char * fragprog2, const char * light_fragprog, const char *defines);
    bool Load();

    bool Bind();
    unsigned int GetHandle() const { return hShader; }
};


struct MatricesUBO
{
	VSMatrix ModelMatrix;
	VSMatrix NormalModelMatrix;
	VSMatrix TextureMatrix;
};

class ShaderFunctions
{
public:
    ShaderFunctions() = default;
    ShaderFunctions(id<MTLFunction> frag, id<MTLFunction> vert)
    {
        vertFunc = vert;
        fragFunc = frag;
    };

    void setVertexFunction(NSString* name)
    {
        vertFunc = [lib newFunctionWithName:name];
    };
    
    void setFragmentFunction(NSString* name)
    {
        fragFunc = [lib newFunctionWithName:name];
    };
    
private:
    id<MTLFunction> vertFunc;
    id<MTLFunction> fragFunc;
    id<MTLLibrary>  lib;
};

class MlShaderProgram
{
public:
    ShaderFunctions *funcs;
    id<MTLBuffer> uniforms;
    
    
    MlShaderProgram()
    {
        funcs = new ShaderFunctions();
    };
    
    ~MlShaderProgram()
    {
        delete funcs;
    };
    
    void SetShaderFunctions(NSString* vert, NSString* frag)
    {
        funcs->setVertexFunction(vert);
        funcs->setFragmentFunction(frag);
    };
    
    void SetVertexFunctions(NSString* vert)
    {
        funcs->setVertexFunction(vert);
    };
    
    void SetFragmentFunctions(NSString* frag)
    {
        funcs->setFragmentFunction(frag);
    };
    
};

class MlShaderCollection
{
    TArray<MlShader*> mMaterialShaders;
    TArray<MlShader*> mMaterialShadersNAT;
    MlShader *mEffectShaders[MAX_EFFECTS];

    void Clean();
    void CompileShaders(EPassType passType);
    
public:
    MlShaderCollection(EPassType passType);
    ~MlShaderCollection();
    MlShader *Compile(const char *ShaderName, const char *ShaderPath, const char *LightModePath, const char *shaderdefines, bool usediscard, EPassType passType);
    int Find(const char *mame);
    MlShader *BindEffect(int effect);

    MlShader *Get(unsigned int eff, bool alphateston)
    {
        // indices 0-2 match the warping modes, 3 is brightmap, 4 no texture, the following are custom
        if (!alphateston && eff <= 3)
        {
            return mMaterialShadersNAT[eff];    // Non-alphatest shaders are only created for default, warp1+2 and brightmap. The rest won't get used anyway
        }
        if (eff < mMaterialShaders.Size())
        {
            return mMaterialShaders[eff];
        }
        return nullptr;
    }
};

class MlShaderManager
{
public:
	MlShaderManager() = default;
	~MlShaderManager() = default;

    MlShader *BindEffect(int effect, EPassType passType);
    MlShader *Get(unsigned int eff, bool alphateston, EPassType passType);

private:
    
    void SetActiveShader(MlShader *sh);
    MlShader *mActiveShader = nullptr;
    TArray<MlShaderCollection*> mPassShaders;

    friend class MlShader;

};

}
