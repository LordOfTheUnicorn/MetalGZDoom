#include "v_video.h"
#include "ml_buffer.h"
#include "ml_framebuffer.h"
#include "metal/renderer/ml_renderstate.h"
#include "metal/renderer/ml_renderer.h"


namespace MetalRenderer
{

static inline void InvalidateBufferState()
{
    ml_RenderState.ResetVertexBuffer();    // force rebinding of buffers on next Apply call.
}

MlBuffer::MlBuffer()
{
}

MlBuffer::~MlBuffer()
{
    free(mBuffer);
}

void MlBuffer::Reset()
{
    mBuffer = nullptr;
}

void MlBuffer::SetData(size_t size, const void *data, bool staticdata)
{
    if (data != nullptr)
    {
        mBuffer = malloc(size);
        memcpy(mBuffer, data, size);
    }
    else
    {
        mPersistent = screen->BuffersArePersistent() && !staticdata;
        if (mPersistent)
        {
            map = mBuffer = malloc(size);
        }
        else
        {
            map = mBuffer = malloc(size);
        }
    }
    buffersize = size;
    InvalidateBufferState();
}


void MlBuffer::SetSubData(size_t offset, size_t size, const void *data)
{
    void * buff = mBuffer;
    if (buff != nullptr)
    {
        memcpy((&buff + offset), data, size);
        buffersize = size;
    }
}

void MlBuffer::Resize(size_t newsize)
{
    buffersize = newsize;
}

void MlBuffer::Map()
{
    if (!mPersistent)
    {
            map = mBuffer;
        InvalidateBufferState();
    }
}

void MlBuffer::Unmap()
{
    if (!mPersistent)
    {
        InvalidateBufferState();
        map = nullptr;
    }
}

void* MlBuffer::GetData()
{
    return mBuffer;
}

void *MlBuffer::Lock(unsigned int size)
{
    return mBuffer;
}

void MlBuffer::Unlock()
{
    InvalidateBufferState();
}

/////////////////////////////////////////////////////////////////////////////


void MlVertexBuffer::SetFormat(int numBindingPoints, int numAttributes, size_t stride, const FVertexBufferAttribute *attrs)
{
    static int VFmtToGLFmt[] = { MTLVertexFormatFloat, MTLVertexFormatFloat, MTLVertexFormatFloat, MTLVertexFormatFloat, MTLVertexFormatUInt, MTLVertexFormatUInt1010102Normalized };
    static uint8_t VFmtToSize[] = {4, 3, 2, 1, 4, 4};
    
    mStride = stride;
    mNumBindingPoints = numBindingPoints;
    
    for(int i = 0; i < numAttributes; i++)
    {
        if (attrs[i].location >= 0 && attrs[i].location < VATTR_MAX)
        {
            auto & attrinf = mAttributeInfo[attrs[i].location];
            attrinf.format = VFmtToGLFmt[attrs[i].format];
            attrinf.size = VFmtToSize[attrs[i].format];
            attrinf.offset = attrs[i].offset;
            attrinf.bindingpoint = attrs[i].binding;
        }
    }
}

MlVertexBuffer::MlVertexBuffer()
{
    option = MTLResourceStorageModeShared;
}

void MlVertexBuffer::Bind(int *offsets, id<MTLRenderCommandEncoder> renderCommandEncoder)
{
    int i = 0;
    for(auto &attrinf : mAttributeInfo)
    {
        if (attrinf.size != 0)
        {
            if (i == 3)
            {
                [renderCommandEncoder setVertexBytes:mBuffer length:attrinf.size * 4 atIndex:i];
            }
        }
        i++;
    }
}


/////////////////////////////////////////////////////////////////////////////


void MlDataBuffer::BindRange(FRenderState* state, size_t start, size_t length)
{
    HWViewpointUniforms *uniforms = (HWViewpointUniforms*)mBuffer;
    
    mtlHWViewpointUniforms *hwUniforms = MLRenderer->mHWViewpointUniforms;
    
    hwUniforms->mProjectionMatrix = *((matrix_float4x4*)uniforms->mProjectionMatrix.Get());
    //hwUniforms->mProjectionMatrix = simd_transpose(hwUniforms->mProjectionMatrix);
    hwUniforms->mViewMatrix = *((matrix_float4x4*)uniforms->mViewMatrix.Get());
    //hwUniforms->mViewMatrix = (simd_transpose(hwUniforms->mViewMatrix));
    
    //hwUniforms->mClipLine  = vector_float4{uniforms->mClipLine.X,uniforms->mClipLine.Y,uniforms->mClipLine.Z,uniforms->mClipLine.W};
    //hwUniforms->mCameraPos = vector_float4{uniforms->mCameraPos.X,uniforms->mCameraPos.Y,uniforms->mCameraPos.Z,uniforms->mCameraPos.W};
    //hwUniforms->mGlobVis = uniforms->mGlobVis;
    //hwUniforms->mPalLightLevels = uniforms->mPalLightLevels;
    hwUniforms->mViewHeight = uniforms->mViewHeight;
    hwUniforms->mClipHeight = uniforms->mClipHeight;
    hwUniforms->mClipHeightDirection = uniforms->mClipHeightDirection;
    hwUniforms->mShadowmapFilter = uniforms->mShadowmapFilter;

    //id<MTLBuffer> buff = [device newBufferWithBytes:hwUniforms length:sizeof(hwUniforms) options:MTLResourceStorageModeShared];
    //ml_RenderState.setVertexBuffer(buff, 4);
}

}
