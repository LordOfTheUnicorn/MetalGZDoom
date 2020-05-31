#pragma once
#import <Metal/Metal.h>

namespace MetalRenderer
{
    class MlSamplerManager
    {
        id <MTLDevice> mDevice;
        
        // We need 6 different samplers: 4 for the different clamping modes,
        // one for 2D-textures and one for voxel textures
        id<MTLSamplerState> mSamplers[7];
        
        //void UnbindAll();
        
        void Create();
        void Destroy();
        
    public:
        
        MlSamplerManager(id <MTLDevice> device);
        ~MlSamplerManager(){Destroy();};
        
        uint8_t Bind(int texunit, int num, int lastval);
        void SetTextureFilterMode();
        
        id<MTLSamplerState> Get(int no) const { return mSamplers[no]; }
        
    };

}
