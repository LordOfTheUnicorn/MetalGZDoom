#pragma once

#include "tarray.h"
#include "hwrenderer/textures/hw_ihwtexture.h"
#include "metal/system/ml_buffer.h"
#import <Metal/Metal.h>



namespace MetalRenderer
{
static const uint8_t STATE_TEXTURES_COUNT     = 16;
static const uint8_t STATE_SAMPLERS_COUNT     = 16;

struct TexFilter
{
    int minfilter;
    int magfilter;
    bool mipmapping;
} ;

struct MetalState
{
    id<MTLTexture>               mTextures;
    int                                 Id;
    //id<MTLSamplerState>          mSamplers;
    //int8_t                       mLastVSTex;
    //int8_t                       mLastPSTex;
    //int8_t                       mLastVSSampler;
    //int8_t                       mLastPSSampler;
    //int                          mFormat;
    //int                          mSize;
    //int8_t                       mUsageFlags;
    //size_t                       mOffset;
    //int                          mWidth;
    //int                          mHeight;
};

struct offsetSize
{
    int offset;
    int size;
};

class MlHardwareTexture : public IHardwareTexture
{
private:
    
    int mlTexID;
    int mlTextureBytes = 4;
    bool mipmapped = false;
    MlBuffer *mBuffer;
    MetalState metalState[STATE_TEXTURES_COUNT];
    id<MTLTexture>               mTextures;
    //int currentTexId;
    int mBufferSize = 0;
    //id<MTLTexture> mTex;
    NSString *nameTex;
    //std::vector<offsetSize> mOffsetSize;
    

    int GetDepthBuffer(int w, int h);

public:
    MlHardwareTexture();
    ~MlHardwareTexture();

    static void Unbind(int texunit);
    static void UnbindAll();

    void BindToFrameBuffer(int w, int h);
    int FindFreeTexIndex()
    {
        for (int i = 0; i < STATE_TEXTURES_COUNT; i++)
        {
            if (metalState[i].Id == -1)
                return i;
        }
        return -1;
    }

  //  unsigned int Bind(int texunit, bool needmipmap);
  //  bool BindOrCreate(FTexture *tex, int texunit, int clampmode, int translation, int flags);

    void AllocateBuffer(int w, int h, int texelsize);
    uint8_t* MapBuffer();

    //bool CreateTexture(uint8_t texID, int w, int h, int pixelsize, int format, const void *pixels, id<MTLDevice> device);
    unsigned int CreateTexture(unsigned char * buffer, int w, int h, int texunit, bool mipmap, int translation, const char *name) override;
    unsigned int CreateWipeScreen(unsigned char * buffer, int w, int h, int texunit, bool mipmap, int translation, const char *name);
    bool CreateTexture(unsigned char * buffer, int w, int h, int texunit, bool mipmap, const char *name);
    void ResetAll();
    void Reset(size_t id);
    bool BindOrCreate(FTexture *tex, int texunit, int clampmode, int translation, int flags, id <MTLRenderCommandEncoder> encoder);
    int Bind(int texunit, bool needmipmap);
 //   unsigned int GetTextureHandle(int translation);
};
}
