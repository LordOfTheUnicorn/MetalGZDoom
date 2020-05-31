// 
//---------------------------------------------------------------------------
//
// Copyright(C) 2018 Christoph Oelckers
// All rights reserved.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with this program.  If not, see http://www.gnu.org/licenses/
//
//--------------------------------------------------------------------------
//

#include "ml_samplers.h"
#include "metal/renderer/ml_renderstate.h"

namespace MetalRenderer
{

MlSamplerManager::MlSamplerManager(id <MTLDevice> device)
{
    mDevice = device;
    Create();
}

void MlSamplerManager::Create()
{
    MTLSamplerDescriptor* desc[7];
        
        for (int i = 0; i < 7; i++)
        {
            desc[i] = [MTLSamplerDescriptor new];
        }
        
        desc[5].minFilter = MTLSamplerMinMagFilterNearest;
        desc[5].magFilter = MTLSamplerMinMagFilterNearest;
        desc[5].maxAnisotropy = 1.f;
        desc[4].maxAnisotropy = 1.f;
        desc[6].maxAnisotropy = 1.f;
        
        desc[1].sAddressMode = MTLSamplerAddressModeClampToEdge;
        desc[2].tAddressMode = MTLSamplerAddressModeClampToEdge;
        desc[3].sAddressMode = MTLSamplerAddressModeClampToEdge;
        desc[3].tAddressMode = MTLSamplerAddressModeClampToEdge;
        desc[4].sAddressMode = MTLSamplerAddressModeClampToEdge;
        desc[4].tAddressMode = MTLSamplerAddressModeClampToEdge;
        
        for (int i = 0; i < 7; i++)
        {
            mSamplers[i] = [mDevice newSamplerStateWithDescriptor:desc[i]];
        }
        
        for (int i = 0; i < 7; i++)
        {
            [desc[i] release];
        }

    //    for (int i = 0; i < 7; i++)
    //    {
    //        FString name;
    //        name.Format("mSamplers[%d]", i);
    //        FGLDebug::LabelObject(GL_SAMPLER, mSamplers[i], name.GetChars());
    //    }
}

void MlSamplerManager::Destroy()
{
    for (int i = 0; i < 7; i++)
    {
        [mSamplers[i] release];
    }
}

void MlSamplerManager::SetTextureFilterMode()
{
    Destroy();
    Create();
}


uint8_t MlSamplerManager::Bind(int texunit, int num, int lastval)
{
    //renderCommandEncoder
}

}
