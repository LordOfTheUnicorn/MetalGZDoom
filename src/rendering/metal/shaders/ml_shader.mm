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

bool MlShader::Load()
{
    NSError* error = nil;
    
    id <MTLLibrary> defaultLibrary = [device newLibraryWithFile: @"/Users/unicorn1343/metalShaders/doomMetallib.metallib" error:&error];
    //id <MTLLibrary> defaultLibrary = [device newDefaultLibrary];
    id <MTLFunction> VShader = [defaultLibrary newFunctionWithName:@"VertexMainSimple"];
    id <MTLFunction> FShader = [defaultLibrary newFunctionWithName:@"FragmentMainSimple"];
    //autoreleaepool
    MTLVertexDescriptor *vertexDesc = [[MTLVertexDescriptor alloc] init];
    
    // Set param for shader
    
    vertexDesc.attributes[0].format = MTLVertexFormatFloat4;
    vertexDesc.attributes[0].offset = 0;
    vertexDesc.attributes[0].bufferIndex = 0;
    vertexDesc.layouts[0].stride = 16; // float4 = float(4) * 4
    vertexDesc.layouts[0].stepRate = 1;
    vertexDesc.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    vertexDesc.attributes[1].format = MTLVertexFormatFloat2;
    vertexDesc.attributes[1].offset = 0;
    vertexDesc.attributes[1].bufferIndex = 1;
    vertexDesc.layouts[1].stride = 8; //float2 = float(4) * 2
    vertexDesc.layouts[1].stepRate = 1;
    vertexDesc.layouts[1].stepFunction = MTLVertexStepFunctionPerVertex;
    
    vertexDesc.attributes[2].format = MTLVertexFormatFloat4;
    vertexDesc.attributes[2].offset = 0;
    vertexDesc.attributes[2].bufferIndex = 2;
    vertexDesc.layouts[2].stride = 16; // float4 = float(4) * 4
    vertexDesc.layouts[2].stepRate = 1;
    vertexDesc.layouts[2].stepFunction = MTLVertexStepFunctionPerVertex;
    
    MTLRenderPipelineDescriptor * figurePD = [[MTLRenderPipelineDescriptor alloc] init];
    figurePD.label = @"VertexMain";
    figurePD.vertexFunction = VShader;
    figurePD.fragmentFunction = FShader;
    figurePD.vertexDescriptor = vertexDesc;
    figurePD.sampleCount = 1;
    
    MTLDepthStencilDescriptor *depthStateDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthStateDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthStateDesc.depthWriteEnabled = YES;
    depthStateDesc.frontFaceStencil.stencilCompareFunction = MTLCompareFunctionAlways;
    depthStateDesc.backFaceStencil.stencilCompareFunction = MTLCompareFunctionAlways;
    depthState = [device newDepthStencilStateWithDescriptor:depthStateDesc];
    
    //[pipelineState:figurePD
    //         label:@"figurePipelineDescriptor"
    //   sampleCount:1
    //    vertexFunction:VShader
    //fragmentFunction:FShader
    //vertexDescriptor:vertexDesc];
       
    figurePD.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    figurePD.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    figurePD.stencilAttachmentPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    
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
