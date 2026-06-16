#ifndef TENSOR_STAGING_H
#define TENSOR_STAGING_H

#include <opencv2/core.hpp>
#include <vector>
#include <stdint.h>

// Defines the data shape and normalization rules for a future AI model
struct TensorConfig {
    int targetWidth;
    int targetHeight;
    int channels;
    float mean[3];
    float stdDev[3];
    bool isPlanarCHW;
};

// Holds the actual pre-allocated block of physical hardware memory
struct TensorStage {
    TensorConfig config;
    void* dataBuffer = nullptr;
    size_t bufferSizeInBytes = 0;
    bool isAllocated = false;
};

// Global Staging Manager Interface exposed via C linkage for Dart FFI
extern "C" {

    bool configureStagingSlot(int32_t slotId, int width, int height, int channels,
                              float meanR, float meanG, float meanB,
                              float stdR, float stdG, float stdB, bool isPlanarCHW);

    bool prepareStageInput(int64_t imageHandle, int32_t slotId);

    void* getStagePointer(int32_t slotId);

    void freeStagingSlot(int32_t slotId);
}

#endif // TENSOR_STAGING_H
