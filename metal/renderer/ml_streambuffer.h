#pragma once

#include "metal/system/ml_buffer.h"
#include "metal/shaders/ml_shader.h"

namespace MetalRenderer
{
class MlStreamBuffer
{
public:
    MlStreamBuffer(size_t structSize, size_t count);
    ~MlStreamBuffer();

    uint32_t NextStreamDataBlock();
    void Reset() { mStreamDataOffset = 0; }

    MlDataBuffer* UniformBuffer = nullptr;

private:
    uint32_t mBlockSize = 0;
    uint32_t mStreamDataOffset = 0;
};

class MlStreamBufferWriter
{
public:
	MlStreamBufferWriter();

	bool Write(const StreamData& data);
	void Reset();

	uint32_t DataIndex() const { return mDataIndex; }
	uint32_t StreamDataOffset() const { return mStreamDataOffset; }

private:
	MlStreamBuffer* mBuffer;
	uint32_t mDataIndex = 255;
	uint32_t mStreamDataOffset = 0;
};

class MlMatrixBufferWriter
{
public:
	MlMatrixBufferWriter();

	bool Write(const VSMatrix& modelMatrix, bool modelMatrixEnabled, const VSMatrix& textureMatrix, bool textureMatrixEnabled);
	void Reset();

	uint32_t Offset() const { return mOffset; }

private:
	MlStreamBuffer* mBuffer;
	MatricesUBO mMatrices = {};
	VSMatrix mIdentityMatrix;
	uint32_t mOffset = 0;
};

}
