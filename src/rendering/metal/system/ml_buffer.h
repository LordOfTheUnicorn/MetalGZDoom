#pragma once

#import <Metal/Metal.h>
#import "simd/simd.h"
#include "utility/tarray.h"
#include "hwrenderer/data/buffers.h"

#ifdef _MSC_VER
// silence bogus warning C4250: 'VKVertexBuffer': inherits 'VKBuffer::VKBuffer::SetData' via dominance
// According to internet infos, the warning is erroneously emitted in this case.
#pragma warning(disable:4250)
#endif

namespace MetalRenderer
{
class MlBuffer : virtual public IBuffer
{
public:
    MlBuffer();
    ~MlBuffer();

    //static void ResetAll();
    void Reset();

    void SetData(size_t size, const void *data, bool staticdata) override;
    void SetSubData(size_t offset, size_t size, const void *data) override;
    void Resize(size_t newsize) override;

    void Map() override;
    void Unmap() override;
    
    void* GetData();

    void *Lock(unsigned int size) override;
    void Unlock() override;
    
    MTLResourceOptions option;

    //VkBufferUsageFlags mBufferType = 0;
    //std::unique_ptr<VulkanBuffer> mBuffer;
    //std::unique_ptr<VulkanBuffer> mStaging;
    bool mPersistent = false;
    //bool map = false;
    //TArray<uint8_t> mStaticUpload;
    void*                 mBuffer;
private:
    //void*                 mBuffer;
    //uint                m_IndicesCount;
    //uint                indexSize;
};

class MlVertexBuffer : public IVertexBuffer, public MlBuffer
{
    struct MLVertexBufferAttribute
    {
        int bindingpoint;
        int format;
        int size;
        int offset;
    };
    
    int mNumBindingPoints;
    MLVertexBufferAttribute mAttributeInfo[VATTR_MAX] = {};
    size_t mStride = 0;
public:

    //int i;
    vector_float4 aPosition[6];
    vector_float2 aTexCoord[6];
    vector_float4 aColor[6];
    
    MlVertexBuffer();
    
    
    
    void SetFormat(int numBindingPoints, int numAttributes, size_t stride, const FVertexBufferAttribute *attrs) override;
    void Bind(int *offsets, id<MTLRenderCommandEncoder> renderCommandEncoder);

    int VertexFormat = -1;
};

class MlIndexBuffer : public IIndexBuffer, public MlBuffer
{
public:
    MlIndexBuffer() {option = MTLResourceStorageModeShared;}

    int bindingpoint;
};

class MlDataBuffer : public IDataBuffer, public MlBuffer
{
public:
    MlDataBuffer(){};

    void BindRange(FRenderState *state, size_t start, size_t length) override;

    int bindingpoint;
    matrix_float4x4 mat;
    float ASS = true;
};
}
