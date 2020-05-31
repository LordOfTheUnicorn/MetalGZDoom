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


struct Material
{
    float4 Base;
    float4 Bright;
    float3 Normal;
    float3 Specular;
    float Glossiness;
    float SpecularLevel;
    float Metallic;
    float Roughness;
    float AO;
};

typedef struct
{
    float uDesaturationFactor;
    float4 uCameraPos;
    float uGlobVis;
    int uPalLightLevels;
    int uFogEnabled;
    float4 uGlowTopColor;
    float4 uGlowBottomColor;
    int uTextureMode;
    float4 uFogColor;
    float4 uObjectColor;
    float4 uObjectColor2;
    float4 uAddColor;
    float4 uDynLightColor;
    float timer;
    //texture2d<float> tex;
    
    //#define uLightLevel uLightAttr.a
    //#define uFogDensity uLightAttr.b
    //#define uLightFactor uLightAttr.g
    //#define uLightDist uLightAttr.r
    float4 uLightAttr;
} Uniforms;

//float4 Process(float4 color);
//float4 ProcessTexel();
//Material ProcessMaterial();
//float4 ProcessLight(Material mat, float4 color);
//float3 ProcessMaterialLight(Material material, float3 color);

//===========================================================================
//
// Color to grayscale
//
//===========================================================================

float grayscale(float4 color)
{
    return dot(color.rgb, float3(0.3, 0.56, 0.14));
}

//===========================================================================
//
// Desaturate a color
//
//===========================================================================

float4 desaturate(float4 texel, float uDesaturationFactor)
{
    if (uDesaturationFactor > 0.0)
    {
        float gray = grayscale(texel);
        return mix (texel, float4(gray,gray,gray,texel.a), uDesaturationFactor);
    }
    else
    {
        return texel;
    }
}

//===========================================================================
//
// Texel
//
//===========================================================================

float4 getTexel(float2 st, float4 uObjectColor, float4 uObjectColor2, int uTextureMode, float3 gradientdist, float4 uAddColor, float uDesaturationFactor, texture2d<float> tex)
{
    constexpr sampler colorSampler(mip_filter::linear, mag_filter::linear, min_filter::linear);

    float4 texel = tex.sample(colorSampler, st);
    
    
    //Apply texture modes
    
    switch (uTextureMode)
    {
        case 1:    // TM_STENCIL
            texel.rgb = float3(1.0,1.0,1.0);
            break;
    
        case 2:    // TM_OPAQUE
            texel.a = 1.0;
            break;
    
        case 3:    // TM_INVERSE
            texel = float4(1.0-texel.r, 1.0-texel.b, 1.0-texel.g, texel.a);
            break;
    
        case 4:    // TM_ALPHATEXTURE
        {
            float gray = grayscale(texel);
            texel = float4(1.0, 1.0, 1.0, gray*texel.a);
            break;
        }
    
        case 5:    // TM_CLAMPY
            //stpq
            if (st.y < 0.0 || st.y > 1.0)
            {
                texel.a = 0.0;
            }
            break;
    
        case 6: // TM_OPAQUEINVERSE
            texel = float4(1.0-texel.x, 1.0-texel.z, 1.0-texel.y, 1.0);
            break;
    
        case 7: //TM_FOGLAYER
            return texel;
    }
    
    texel.rgb += uAddColor.rgb;

    if (uObjectColor2.a == 0.0) texel *= uObjectColor;
    else texel *= mix(uObjectColor, uObjectColor2, gradientdist.z);

    return desaturate(texel, uDesaturationFactor);
}

float4 ProcessTexel(float4 vTexCoord, float4 uObjectColor, float4 uObjectColor2, int uTextureMode, float3 gradientdist, float4 uAddColor, float uDesaturationFactor, texture2d<float> tex, float timer)
{
    float2 texCoord = vTexCoord.xy;
    //float4            getTexel(float2 st, float4 uObjectColor, float4 uObjectColor2, float3 gradientdist, float4 uAddColor, float uDesaturationFactor)
    float4 basicColor = getTexel(texCoord, uObjectColor, uObjectColor2, uTextureMode, gradientdist, uAddColor, uDesaturationFactor, tex);
    float2 texSize = float2(tex.get_width(), tex.get_height());

    texCoord.x = float( int(texCoord.x * texSize.x) ) / texSize.x;
    texCoord.y = float( int(texCoord.y * texSize.y) ) / texSize.y;

    float texX = texCoord.x / 3.0 + 0.66;
    float texY = 0.34 - texCoord.y / 3.0;
    float vX = (texX/texY)*21.0;
    float vY = (texY/texX)*13.0;
    float test = fmod(timer*2.0+(vX + vY), 0.5);

    basicColor.a = basicColor.a * test;
    basicColor.r = basicColor.g = basicColor.b = 0.0;
    
    return basicColor;
}

//===========================================================================
//
// Materials
//
//===========================================================================

Material ProcessMaterial(float4 vTexCoord, float4 uObjectColor, float4 uObjectColor2, int uTextureMode, float3 gradientdist, float4 uAddColor, float uDesaturationFactor, texture2d<float> tex, float timer,
                         float4 vWorldNormal)
{
    Material material;
    material.Base = ProcessTexel(vTexCoord, uObjectColor, uObjectColor2, uTextureMode, gradientdist, uAddColor, uDesaturationFactor, tex, timer);
    material.Normal = normalize(vWorldNormal.xyz);//ApplyNormalMap(vTexCoord.xy);
    return material;
}

//===========================================================================
//
// Lights
//
//===========================================================================

float3 ProcessMaterialLight(Material material, float3 color, float4 uDynLightColor, float uDesaturationFactor)
{
    return material.Base.rgb * clamp(color + desaturate(uDynLightColor,uDesaturationFactor).rgb, 0.0, 1.4);
}

float4 ProcessLight(Material material, float4 color)
{
    return color;
}

//===========================================================================
//
// Vanilla Doom wall colormap equation
//
//===========================================================================
float R_WallColormap(float lightnum, float z, float3 normal, float4 pixelpos, float4 uCameraPos)
{
    // R_ScaleFromGlobalAngle calculation
    float projection = 160.0; // projection depends on SCREENBLOCKS!! 160 is the fullscreen value
    float2 line_v1 = pixelpos.xz; // in vanilla this is the first curline vertex
    float2 line_normal = normal.xz;
    float texscale = projection * clamp(dot(normalize(uCameraPos.xz - line_v1), line_normal), 0.0, 1.0) / z;

    float lightz = clamp(16.0 * texscale, 0.0, 47.0);

    // scalelight[lightnum][lightz] lookup
    float startmap = (15.0 - lightnum) * 4.0;
    return startmap - lightz * 0.5;
}

//===========================================================================
//
// Vanilla Doom plane colormap equation
//
//===========================================================================
float R_PlaneColormap(float lightnum, float z)
{
    float lightz = clamp(z / 16.0f, 0.0, 127.0);

    // zlight[lightnum][lightz] lookup
    float startmap = (15.0 - lightnum) * 4.0;
    float scale = 160.0 / (lightz + 1.0);
    return startmap - scale * 0.5;
}

//===========================================================================
//
// zdoom colormap equation
//
//===========================================================================
float R_ZDoomColormap(float light, float z, float uGlobVis)
{
    float L = light * 255.0;
    float vis = min(uGlobVis / z, 24.0 / 32.0);
    float shade = 2.0 - (L + 12.0) / 128.0;
    float lightscale = shade - vis;
    return lightscale * 31.0;
}

float R_DoomColormap(float light, float z, float4 pixelpos, float4 vWorldNormal, float4 uCameraPos, float uGlobVis, int uPalLightLevels)
{
    if ((uPalLightLevels >> 16) == 16) // gl_lightmode 16
    {
        float lightnum = clamp(light * 15.0, 0.0, 15.0);

        if (dot(vWorldNormal.xyz, vWorldNormal.xyz) > 0.5)
        {
            float3 normal = normalize(vWorldNormal.xyz);
            return mix(R_WallColormap(lightnum, z, normal, pixelpos, uCameraPos), R_PlaneColormap(lightnum, z), abs(normal.y));
        }
        else // vWorldNormal is not set on sprites
        {
            return R_PlaneColormap(lightnum, z);
        }
    }
    else
    {
        return R_ZDoomColormap(light, z, uGlobVis);
    }
}

//===========================================================================
//
// Doom software lighting equation
//
//===========================================================================
float R_DoomLightingEquation(float light, float4 pixelpos, float4 vWorldNormal, float4 uCameraPos, int uPalLightLevels, float uGlobVis)
{
    // z is the depth in view space, positive going into the screen
    float z;
    if (((uPalLightLevels >> 8)  & 0xff) == 2)
    {
        z = distance(pixelpos.xyz, uCameraPos.xyz);
    }
    else
    {
        z = pixelpos.w;
    }

    float colormap = R_DoomColormap(light, z, pixelpos, vWorldNormal, uCameraPos, uGlobVis, uPalLightLevels);

    if ((uPalLightLevels & 0xff) != 0)
        colormap = floor(colormap) + 0.5;

    // Result is the normalized colormap index (0 bright .. 1 dark)
    return clamp(colormap, 0.0, 31.0) / 32.0;
}

//===========================================================================
//
// Calculate light
//
// It is important to note that the light color is not desaturated
// due to ZDoom's implementation weirdness. Everything that's added
// on top of it, e.g. dynamic lights and glows are, though, because
// the objects emitting these lights are also.
//
// This is making this a bit more complicated than it needs to
// because we can't just desaturate the final fragment color.
//
//===========================================================================

float4 getLightColor(Material material, float fogdist, float fogfactor, float4 pixelpos, float4 vWorldNormal, float4 vColor, Uniforms uniforms, float3 glowdist)
{
    //typedef struct
    //{
    //    float uDesaturationFactor;
    //    float4 uCameraPos;
    //    float uGlobVis;
    //    int uPalLightLevels;
    //
    //    //#define uLightLevel uLightAttr.a
    //    //#define uFogDensity uLightAttr.b
    //    //#define uLightFactor uLightAttr.g
    //    //#define uLightDist uLightAttr.r
    //    float4 uLightAttr;
    //
    //    int uFogEnabled;
    //    float4 uGlowTopColor;
    //} Uniforms;
    
    float4 color = vColor;
    
    if (uniforms.uLightAttr.w >= 0.0)
    {
        float newlightlevel = 1.0 - R_DoomLightingEquation(uniforms.uLightAttr.w, pixelpos, vWorldNormal, uniforms.uCameraPos, uniforms.uPalLightLevels, uniforms.uGlobVis);
        color.rgb *= newlightlevel;
    }
    else if (uniforms.uFogEnabled > 0)
    {
        // brightening around the player for light mode 2
        if (fogdist < uniforms.uLightAttr.x)
        {
            color.rgb *= uniforms.uLightAttr.y - (fogdist / uniforms.uLightAttr.x) * (uniforms.uLightAttr.y - 1.0);
        }
        
        //
        // apply light diminishing through fog equation
        //
        color.rgb = mix(float3(0.0, 0.0, 0.0), color.rgb, fogfactor);
    }
    
    //
    // handle glowing walls
    //
    if (uniforms.uGlowTopColor.a > 0.0 && glowdist.x < uniforms.uGlowTopColor.a)
    {
        color.rgb += desaturate(uniforms.uGlowTopColor * (1.0 - glowdist.x / uniforms.uGlowTopColor.a), uniforms.uDesaturationFactor).rgb;
    }
    if (uniforms.uGlowBottomColor.a > 0.0 && glowdist.y < uniforms.uGlowBottomColor.a)
    {
        color.rgb += desaturate(uniforms.uGlowBottomColor * (1.0 - glowdist.y / uniforms.uGlowBottomColor.a), uniforms.uDesaturationFactor).rgb;
    }
    color = min(color, 1.0);

    //
    // apply brightmaps (or other light manipulation by custom shaders.
    //
    color = ProcessLight(material, color);

    //
    // apply dynamic lights
    //
    return float4(ProcessMaterialLight(material, color.rgb, uniforms.uDynLightColor, uniforms.uDesaturationFactor), material.Base.a * vColor.a);
}

//===========================================================================
//
// Applies colored fog
//
//===========================================================================

float4 applyFog(float4 frag, float fogfactor, float4 uFogColor)
{
    return float4(mix(uFogColor.rgb, frag.rgb, fogfactor), frag.a);
}

//===========================================================================
//
// Main shader routine
//
//===========================================================================

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

       return float4(colorSample);
    
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

