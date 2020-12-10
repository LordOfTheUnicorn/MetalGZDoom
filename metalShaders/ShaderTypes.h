//#ifndef ShaderTypes_h
//#define ShaderTypes_h

#include <simd/simd.h>

typedef struct
{
    matrix_float4x4 ModelMatrix;
    matrix_float4x4 ViewMatrix;
    matrix_float4x4 TextureMatrix;
    matrix_float4x4 ProjectionMatrix;
} PerView;
