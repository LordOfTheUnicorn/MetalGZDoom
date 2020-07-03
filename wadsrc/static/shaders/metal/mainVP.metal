//layout(location = 0) in float4 aPosition;
//layout(location = 1) in float2 aTexCoord;
//layout(location = 2) in float4 aColor;
//
//layout(location = 0) out float4 vTexCoord;
//layout(location = 1) out float4 vColor;

#include <metal_stdlib>
#include <simd/simd.h>
//#include "ShaderTypes.h"

using namespace metal;

typedef struct
{
    float4 aPosition [[attribute(0)]];
    float2 aTexCoord [[attribute(1)]];
    float4 aColor    [[attribute(2)]];
//#ifndef SIMPLE    // we do not need these for simple shaders
    //float4 aVertex2  [[attribute(3)]];
    //float4 aNormal   [[attribute(4)]];
    //float4 aNormal2  [[attribute(5)]];
//#endif
} inVertex;

typedef struct
{
    float4 aVertex2;
    float4 aNormal;
    float4 aNormal2;
} inVertexData;

typedef struct
{
    float4 aPosition [[position]];
    float4 vTexCoord;
    float4 vColor;
#ifndef SIMPLE
    float4 pixelpos;
    float3 glowdist;
    float3 gradientdist;
    float4 vWorldNormal;
    float4 vEyeNormal;
#endif
//#ifdef NO_CLIPDISTANCE_SUPPORT
    float4 ClipDistanceA [[user(clip_A)]];
    float4 ClipDistanceB [[user(clip_B)]];
//#endif
} outVertex;

typedef struct
{
    float4x4 ModelMatrix;
    float4x4 TextureMatrix;
    float4x4 NormalModelMatrix;
} PerView;

typedef struct
{
    float4   uClipLine;
    float    uClipHeight;
    float    uClipHeightDirection;
    float4x4 ProjectionMatrix;
    float4x4 ViewMatrix;
    float4x4 NormalViewMatrix;
} ViewpointUBO;

typedef struct
{
    float2 uClipSplit;
    float4 uSplitTopPlane;
    float  uInterpolationFactor;
    float4 uGlowTopColor;
    float4 uGlowTopPlane;
    float4 uGlowBottomPlane;
    float4 uObjectColor2;
    float4 uSplitBottomPlane;
    float4 uGradientBottomPlane;
    float4 uGlowBottomColor;
    float4 uGradientTopPlane;
} UniformsVS;

vertex outVertex VertexMainSimple(inVertex in [[stage_in]], constant PerView& perView [[buffer(3)]], constant ViewpointUBO& UBO [[buffer(4)]], constant UniformsVS& uniforms [[buffer(5)]], constant inVertexData& vertexData [[buffer(6)]])
{
    outVertex out;
    
    float ClipDistance0, ClipDistance1, ClipDistance2, ClipDistance3, ClipDistance4;
    float2 parmTexCoord;
    float4 parmPosition;
    
    parmTexCoord = in.aTexCoord;
    parmPosition = in.aPosition;
    #ifndef SIMPLE
        float4 worldcoord = perView.ModelMatrix * mix(parmPosition, vertexData.aVertex2, uniforms.uInterpolationFactor);
    #else
        float4 worldcoord = perView.ModelMatrix * parmPosition;
    #endif

    float4 eyeCoordPos = UBO.ViewMatrix * worldcoord;

    #ifdef HAS_UNIFORM_VERTEX_DATA
        if ((useVertexData & 1) == 0)
            out.vColor = uVertexColor;
        else
            out.vColor = in.aColor;
    #else
        out.vColor = in.aColor;
    #endif
    
    #ifndef SIMPLE
        out.pixelpos.xyz = worldcoord.xyz;
        out.pixelpos.w = -eyeCoordPos.z/eyeCoordPos.w;

        if (uniforms.uGlowTopColor.a > 0 || uniforms.uGlowBottomColor.a > 0)
        {
            float topatpoint = (uniforms.uGlowTopPlane.w + uniforms.uGlowTopPlane.x * worldcoord.x + uniforms.uGlowTopPlane.y * worldcoord.z) * uniforms.uGlowTopPlane.z;
            float bottomatpoint = (uniforms.uGlowBottomPlane.w + uniforms.uGlowBottomPlane.x * worldcoord.x + uniforms.uGlowBottomPlane.y * worldcoord.z) * uniforms.uGlowBottomPlane.z;
            out.glowdist.x = topatpoint - worldcoord.y;
            out.glowdist.y = worldcoord.y - bottomatpoint;
            out.glowdist.z = clamp(out.glowdist.x / (topatpoint - bottomatpoint), 0.0, 1.0);
        }
        
        if (uniforms.uObjectColor2.a != 0)
        {
            float topatpoint = (uniforms.uGradientTopPlane.w + uniforms.uGradientTopPlane.x * worldcoord.x + uniforms.uGradientTopPlane.y * worldcoord.z) * uniforms.uGradientTopPlane.z;
            float bottomatpoint = (uniforms.uGradientBottomPlane.w + uniforms.uGradientBottomPlane.x * worldcoord.x + uniforms.uGradientBottomPlane.y * worldcoord.z) * uniforms.uGradientBottomPlane.z;
            out.gradientdist.x = topatpoint - worldcoord.y;
            out.gradientdist.y = worldcoord.y - bottomatpoint;
            out.gradientdist.z = clamp(out.gradientdist.x / (topatpoint - bottomatpoint), 0.0, 1.0);
        }
        
        if (uniforms.uSplitBottomPlane.z != 0.0)
        {
            ClipDistance3 = ((uniforms.uSplitTopPlane.w + uniforms.uSplitTopPlane.x * worldcoord.x + uniforms.uSplitTopPlane.y * worldcoord.z) * uniforms.uSplitTopPlane.z) - worldcoord.y;
            ClipDistance4 = worldcoord.y - ((uniforms.uSplitBottomPlane.w + uniforms.uSplitBottomPlane.x * worldcoord.x + uniforms.uSplitBottomPlane.y * worldcoord.z) * uniforms.uSplitBottomPlane.z);
        }

        #ifdef HAS_UNIFORM_VERTEX_DATA
            if ((useVertexData & 2) == 0)
                out.vWorldNormal = perView.NormalModelMatrix * float4(uVertexNormal.xyz, 1.0);
            else
                out.vWorldNormal = perView.NormalModelMatrix * float4(normalize(mix(vertexData.aNormal.xyz, vertexData.aNormal2.xyz, uniforms.uInterpolationFactor)), 1.0);
        #else
            out.vWorldNormal = perView.NormalModelMatrix * float4(normalize(mix(vertexData.aNormal.xyz, vertexData.aNormal2.xyz, uniforms.uInterpolationFactor)), 1.0);
        #endif
        out.vEyeNormal = UBO.NormalViewMatrix * out.vWorldNormal;
    #endif
    
    #ifdef SPHEREMAP
        float3 u = normalize(eyeCoordPos.xyz);
        float4 n = normalize(UBO.NormalViewMatrix * float4(parmTexCoord.x, 0.0, parmTexCoord.y, 0.0));
        float3 r = reflect(u, n.xyz);
        float m = 2.0 * sqrt( r.x*r.x + r.y*r.y + (r.z+1.0)*(r.z+1.0) );
        float2 sst = float2(r.x/m + 0.5,  r.y/m + 0.5);
        out.vTexCoord.xy = sst;
    #else
        out.vTexCoord = perView.TextureMatrix * float4(parmTexCoord, 0.0, 1.0);
    #endif
    
    out.vTexCoord = perView.TextureMatrix * float4(parmTexCoord, 0.0, 1.0);
    out.vColor = in.aColor;
    
    out.aPosition = UBO.ProjectionMatrix * eyeCoordPos;
    out.aPosition.w = 1.f;
    out.aPosition.z = 1.f;

    if (UBO.uClipHeightDirection != 0.0) // clip planes used for reflective flats
    {
        ClipDistance0 = (worldcoord.y - UBO.uClipHeight) * UBO.uClipHeightDirection;
    }
    else if (UBO.uClipLine.x > -1000000.0) // and for line portals - this will never be active at the same time as the reflective planes clipping so it can use the same hardware clip plane.
    {
        ClipDistance0 = -( (worldcoord.z - UBO.uClipLine.y) * UBO.uClipLine.z + (UBO.uClipLine.x - worldcoord.x) * UBO.uClipLine.w ) + 1.0/32768.0;    // allow a tiny bit of imprecisions for colinear linedefs.
    }
    else
    {
        ClipDistance0 = 1;
    }

    //// clip planes used for translucency splitting
    ClipDistance1 = worldcoord.y - uniforms.uClipSplit.x;
    ClipDistance2 = uniforms.uClipSplit.y - worldcoord.y;

    if (length(uniforms.uSplitTopPlane) == 0)
    {
        ClipDistance3 = 1.0;
        ClipDistance4 = 1.0;
    }

//#ifdef NO_CLIPDISTANCE_SUPPORT
    out.ClipDistanceA = float4(ClipDistance0, ClipDistance1, ClipDistance2, ClipDistance3);
    out.ClipDistanceB = float4(ClipDistance4, 0.0, 0.0, 0.0);
//#else
//    out.ClipDistance[0] = ClipDistance0;
//    out.ClipDistance[1] = ClipDistance1;
//    out.ClipDistance[2] = ClipDistance2;
//    out.ClipDistance[3] = ClipDistance3;
//    out.ClipDistance[4] = ClipDistance4;
//#endif

    return out;
}


//layout(location = 0) in float4 vTexCoord;
//layout(location = 1) in float4 vColor;
//layout(location = 2) in float4 pixelpos;
//layout(location = 3) in float3 glowdist;
//layout(location = 4) in float3 gradientdist;
//layout(location = 5) in float4 vWorldNormal;
//layout(location = 6) in float4 vEyeNormal;
//
//
//layout(location=0) out float4 FragColor;




fragment float4 FragmentMainSimple(outVertex in [[stage_in]]/*, constant float4& pixelpos [[buffer(2)]], constant float3& glowdist[[buffer(3)]],
                                   constant float3& gradientdist[[buffer(4)]], constant float4& vWorldNormal [[buffer(5)]], constant float4& vEyeNormal [[buffer(6)]], constant Uniforms& uniforms [[buffer(7)]]*/, texture2d<float> tex [[texture(8)]])
{
    //layout(location = 0) in float4 vTexCoord;
    //layout(location = 1) in float4 vColor;
    //layout(location = 2) in float4 pixelpos;
    //layout(location = 3) in float3 glowdist;
    //layout(location = 4) in float3 gradientdist;
    //layout(location = 5) in float4 vWorldNormal;
    //layout(location = 6) in float4 vEyeNormal;
    
    
    //layout(location=0) out float4 FragColor;
    
    constexpr sampler colorSampler(mip_filter::linear,
                                      mag_filter::linear,
                                      min_filter::linear);

       float4 colorSample = tex.sample(colorSampler, in.vTexCoord.xy);

        return float4(255.f,0.f,0.f,1.f);
    
    //Material material = ProcessMaterial(in.vTexCoord, uniforms.uObjectColor, uniforms.uObjectColor2, uniforms.uTextureMode, 1, uniforms.uAddColor, uniforms.uDesaturationFactor, tex,
      //                                  uniforms.timer, 1);
    //float4 frag = material.Base;
   
    //frag = frag * in.vColor;//ProcessLight(material, in.vColor);
    //frag.rgb = frag.rgb + uniforms.uFogColor.rgb;
   
    //return frag;

    //if (uniforms.uFogEnabled != -3)    // check for special 2D 'fog' mode.
    //{
    //    float fogdist = 0.0;
    //    float fogfactor = 0.0;
    //
    //    //
    //    // calculate fog factor
    //    //
    //    if (uniforms.uFogEnabled != 0)
    //    {
    //        if (uniforms.uFogEnabled == 1 || uniforms.uFogEnabled == -1)
    //        {
    //            fogdist = max(16.0, pixelpos.w);
    //        }
    //        else
    //        {
    //            fogdist = max(16.0, distance(pixelpos.xyz, uniforms.uCameraPos.xyz));
    //        }
    //        fogfactor = exp2 (uniforms.uLightAttr.z * fogdist);
    //    }
    //
    //    if (uniforms.uTextureMode != 7)
    //    {
    //        frag = getLightColor(material, fogdist, fogfactor, pixelpos, vWorldNormal, in.vColor, uniforms, glowdist);
    //        //
    //        // colored fog
    //        //
    //        if (uniforms.uFogEnabled < 0)
    //        {
    //            frag = applyFog(frag, fogfactor, uniforms.uFogColor);
    //        }
    //    }
    //    else
    //    {
    //        frag = float4(uniforms.uFogColor.rgb, (1.0 - fogfactor) * frag.a * 0.75 * in.vColor.a);
    //    }
    //}
    //else // simple 2D (uses the fog color to add a color overlay)
    //{
    //    if (uniforms.uTextureMode == 7)
    //    {
    //        float gray = grayscale(frag);
    //        float4 cm = (uniforms.uObjectColor + gray * (uniforms.uAddColor - uniforms.uObjectColor)) * 2;
    //        frag = float4(clamp(cm.rgb, 0.0, 1.0), frag.a);
    //    }
    //        frag = frag * in.vColor;//ProcessLight(material, in.vColor);
    //    frag.rgb = frag.rgb + uniforms.uFogColor.rgb;
    //}
    //
    //return frag;
}

