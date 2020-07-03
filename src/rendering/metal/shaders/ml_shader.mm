#pragma once

#include <memory>
#import <Metal/Metal.h>

#include "metal/shaders/ml_shader.h"
#include "metal/shaders/ml_shader.h"
#include "utility/vectors.h"
#include "matrix.h"
#include "name.h"
#include "hwrenderer/scene/hw_renderstate.h"
#include <simd/simd.h>
#include "metal/system/ml_framebuffer.h"
#include "metal/system/ml_framebuffer.h"


namespace MetalRenderer
{

bool MlShader::Load(const MLVertexBufferAttribute *attr, size_t stride)
{
    NSError* error = nil;
    id <MTLLibrary> defaultLibrary = [device newLibraryWithFile: @"/Users/unicorn1343/metalShaders/doomMetallib.metallib" error:&error];
    id <MTLFunction> VShader = [defaultLibrary newFunctionWithName:@"VertexMainSimple"];
    id <MTLFunction> FShader = [defaultLibrary newFunctionWithName:@"FragmentMainSimple"];
    
    MTLVertexDescriptor *vertexDesc = [[MTLVertexDescriptor alloc] init];
    
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
//##############################################################
    
    MTLRenderPipelineDescriptor * figurePD = [[MTLRenderPipelineDescriptor alloc] init];
    figurePD.label = @"VertexMain";
    figurePD.vertexFunction = VShader;
    figurePD.fragmentFunction = FShader;
    figurePD.vertexDescriptor = vertexDesc;
    figurePD.sampleCount = 1;
    
    MTLDepthStencilDescriptor *depthStateDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthStateDesc.depthCompareFunction = MTLCompareFunctionAlways;
    depthStateDesc.depthWriteEnabled = YES;
    depthStateDesc.frontFaceStencil.stencilCompareFunction = MTLCompareFunctionAlways;
    depthStateDesc.backFaceStencil.stencilCompareFunction = MTLCompareFunctionAlways;
    depthState = [device newDepthStencilStateWithDescriptor:depthStateDesc];
       
    figurePD.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    figurePD.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    figurePD.stencilAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;

    figurePD.colorAttachments[0].rgbBlendOperation           = MTLBlendOperationAdd;
    figurePD.colorAttachments[0].alphaBlendOperation         = MTLBlendOperationAdd;
    figurePD.colorAttachments[0].sourceRGBBlendFactor        = MTLBlendFactorOne;
    figurePD.colorAttachments[0].sourceAlphaBlendFactor      = MTLBlendFactorOne;
    figurePD.colorAttachments[0].destinationRGBBlendFactor   = MTLBlendFactorOneMinusSourceAlpha;
    figurePD.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    figurePD.colorAttachments[0].blendingEnabled = YES;
    
    pipelineState = [device newRenderPipelineStateWithDescriptor:figurePD  error:&error];
       
    if(!pipelineState || error)
    {
        NSLog(@"Failed to created pipeline state, error %@", error);
        assert(pipelineState);
        return false;
    }
    
    
    
    return true;
}

}
