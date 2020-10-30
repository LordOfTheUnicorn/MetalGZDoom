#pragma once
#import <Metal/Metal.h>

namespace MetalRenderer
{
    class MlSamplerManager
    {
        id <MTLDevice>        mDevice;
        MTLSamplerDescriptor* mDesc[7];
        bool mRepeatMode : 1;
        // We need 6 different samplers: 4 for the different clamping modes,
        // one for 2D-textures and one for voxel textures
        
        //void UnbindAll();
        
        void CreateDesc();
        void CreateSamplers();
        void DestroySamplers();
        void DestroyDesc();
        void Destroy();
        
    public:
        id<MTLSamplerState> mSamplers[7];
        id<MTLSamplerState> currentSampler;
        MlSamplerManager(id <MTLDevice> device);
        ~MlSamplerManager(){Destroy();};
        
        uint8_t Bind(int texunit, int num, int lastval);
        void BindToShader(id<MTLRenderCommandEncoder> encoder);
        void SetTextureFilterMode();
        void SetRepeatAddressMode(bool val);
        
        id<MTLSamplerState> Get(int no) const { return mSamplers[no]; }
        
    };

}
