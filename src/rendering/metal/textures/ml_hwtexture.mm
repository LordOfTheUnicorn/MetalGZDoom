//
//---------------------------------------------------------------------------
//
// Copyright(C) 2004-2016 Christoph Oelckers
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
/*
** gltexture.cpp
** Low level OpenGL texture handling. These classes are also
** containers for the various translations a texture can have.
**
*/

#include "templates.h"
#include "c_cvars.h"
#include "doomtype.h"
#include "r_data/colormaps.h"
#include "hwrenderer/textures/hw_material.h"

#include "hwrenderer/utility/hw_cvars.h"
#include "metal/textures/ml_samplers.h"
#include "metal/textures/ml_hwtexture.h"
#include "metal/system/ml_buffer.h"
#include "metal/system/ml_framebuffer.h"
#include "metal/renderer/ml_renderstate.h"


namespace MetalRenderer
{
TexFilter texFilter[]={
    {MTLSamplerMinMagFilterNearest, MTLSamplerMinMagFilterNearest, false},
    {MTLSamplerMipFilterNearest, MTLSamplerMinMagFilterNearest,    true},
    {MTLSamplerMinMagFilterLinear,  MTLSamplerMinMagFilterLinear,  false},
    {MTLSamplerMipFilterLinear,  MTLSamplerMinMagFilterLinear,  true},
    {MTLSamplerMipFilterLinear,  MTLSamplerMinMagFilterLinear,  true},
    {MTLSamplerMipFilterNearest, MTLSamplerMinMagFilterNearest, true},
    {MTLSamplerMipFilterLinear,  MTLSamplerMinMagFilterNearest, true},
};

int TexFormat[]={
    MTLPixelFormatRGBA8Unorm,
    MTLPixelFormatRGBA8Unorm,
    MTLPixelFormatRGBA8Unorm,
    MTLPixelFormatRGBA8Unorm,
    // [BB] Added compressed texture formats.
    MTLPixelFormatBC1_RGBA,
    MTLPixelFormatBC1_RGBA,
    MTLPixelFormatBC2_RGBA,
    MTLPixelFormatBC3_RGBA,
};

MlHardwareTexture::MlHardwareTexture()
{
    mBuffer = new MlBuffer();
};

MlHardwareTexture::~MlHardwareTexture()
{
    [mTex release];
    delete mBuffer;
};


//===========================================================================
//
//
//
//===========================================================================
void MlHardwareTexture::AllocateBuffer(int w, int h, int texelsize)
{
    mlTextureBytes = texelsize;
    bufferpitch = w;
}


uint8_t* MlHardwareTexture::MapBuffer()
{
    return (uint8_t*)mBuffer->GetData();
}

void MlHardwareTexture::ResetAll()
{
    [mTex release];
}

void MlHardwareTexture::Reset(size_t id)
{
    [mTex release];
}

unsigned int MlHardwareTexture::Bind(int texunit, bool needmipmap)
{
    //if (mlTexID != 0)
    //{
    //    if (lastbound[texunit] == mlTexID)
    //        return mlTexID;
    //
    //    lastbound[texunit] = glTexID;
    //    if (texunit != 0) glActiveTexture(GL_TEXTURE0 + texunit);
    //    glBindTexture(GL_TEXTURE_2D, glTexID);
    //    // Check if we need mipmaps on a texture that was creted without them.
    //    if (needmipmap && !mipmapped && TexFilter[gl_texture_filter].mipmapping)
    //    {
    //        glGenerateMipmap(GL_TEXTURE_2D);
    //        mipmapped = true;
    //    }
    //    if (texunit != 0) glActiveTexture(GL_TEXTURE0);
    //    return glTexID;
    //}
    return 0;
}

unsigned int MlHardwareTexture::CreateTexture(unsigned char * buffer, int w, int h, int texunit, bool mipmap, int translation, const char *name)
{
    CreateTexture(buffer,w,h,texunit,mipmap,name);
    return 1;
}

id<MTLTexture> MlHardwareTexture::CreateTexture(unsigned char * buffer, int w, int h, int texunit, bool mipmap, const char *name)
{
    //nameTex(name);
    int rh,rw;
    //int texformat = MTLPixelFormatBGRA8Unorm;//GL_RGBA8;// TexFormat[gl_texture_format];
    bool deletebuffer=false;

    rw = w;//GetTexDimension(w);
    rh = h;//GetTexDimension(h);

    if (!buffer)
    {
        // The texture must at least be initialized if no data is present.
        mipmapped = false;
        buffer=(unsigned char *)calloc(4,rw * (rh+1));
        deletebuffer=true;
        //texheight = -h;
    }
    else
    {
        if (rw < w || rh < h)
        {
            // The texture is larger than what the hardware can handle so scale it down.
            unsigned char * scaledbuffer=(unsigned char *)calloc(4,rw * (rh+1));
            if (scaledbuffer)
            {
                Resize(w, h, rw, rh, buffer, scaledbuffer);
                deletebuffer=true;
                buffer=scaledbuffer;
            }
        }
    }
    
    

    MTLTextureDescriptor *desc = [MTLTextureDescriptor new];
    desc.width = rw;
    desc.height = rh;
    desc.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    desc.storageMode = MTLStorageModeManaged;
    desc.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
    desc.textureType = MTLTextureType2D;
    desc.sampleCount = 1;
    
    mTex = [device newTextureWithDescriptor:desc];
    
    if(buffer)
    {
        MTLRegion region = MTLRegionMake2D(0, 0, rw, rh);
        [mTex replaceRegion:region mipmapLevel:0 withBytes:buffer bytesPerRow:(4*rw)];
    }


    if (deletebuffer && buffer)
        free(buffer);
    
    if (0)//mipmap)
    {
        mipmapped = true;
    }
    
    return mTex;
}

bool MlHardwareTexture::BindOrCreate(FTexture *tex, int texunit, int clampmode, int translation, int flags, id <MTLRenderCommandEncoder> encoder)
{
    int usebright = false;

    if (translation <= 0)
    {
        translation = -translation;
    }
    else
    {
        auto remap = TranslationToTable(translation);
        translation = remap == nullptr ? 0 : remap->GetUniqueIndex();
    }

    bool needmipmap = (clampmode <= CLAMP_XY);

    // Bind it to the system.
    if (!Bind(texunit, needmipmap))
    {

        int w = 0, h = 0;

        // Create this texture
        
        FTextureBuffer texbuffer;

        if (!tex->isHardwareCanvas())
        {
            texbuffer = tex->CreateTexBuffer(translation, flags | CTF_ProcessData);
            w = texbuffer.mWidth;
            h = texbuffer.mHeight;
        }
        else
        {
            w = tex->GetWidth();
            h = tex->GetHeight();
        }
        if (!CreateTexture(texbuffer.mBuffer, w, h, texunit, needmipmap, /*translation,*/ "FHardwareTexture.BindOrCreate"))
        {
            // could not create texture
            return false;
        }
    }
    if (tex->isHardwareCanvas())
        static_cast<FCanvasTexture*>(tex)->NeedUpdate();
    
    FImageSource * t = tex->GetImage();
    
    
    //MLRenderer->mSamplerManager->Bind(texunit, clampmode, 255);
    if (encoder)
    {
        //[encoder setFragmentSamplerState:MLRenderer->mSamplerManager->mSamplers[clampmode] atIndex:9];
        [encoder setFragmentTexture:mTex atIndex:1];
    }
    return true;
}

}
