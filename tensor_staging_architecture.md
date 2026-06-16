# High-Performance AI Pipeline: Dynamic Tensor Staging Architecture

This document defines the implementation for the pre-allocated, fixed-size staging buffers using a "lazy dimension binding" pattern. This allows the Flutter layer to dynamically define model input shape and normalization vectors at runtime without requiring modification or recompilation of the native C++ engine.

---

## 1. Core Lifecycle Workflow


[Flutter UI] Initialise Model Engine ➔ Maps Target Dims & Normalization arrays

[C++ Engine] Allocates single, contiguous Float32 block once on Native Heap (TensorStage)

[User Interaction] Triggers AI Task (e.g., Remove Background)

[OpenCV Core] Reads Master NativeImg Handle ➔ Downsamples + Normalizes directly into TensorStage

[ONNX Mobile] Executes processing inference directly from the static TensorStage memory pointer

[GPU Shader] Pulls low-res mask ➔ Upscales via hardware interpolation ➔ Blends back onto Master Canvas

[TensorStage Memory] Wiped clean via memset (0) ➔ Stays warm and allocated for next execution iteration


---

## 2. C++ Architecture Interface (`tensor_staging.h`)

```cpp
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
    bool isPlanarCHW; // true for CHW (planar), false for HWC (interleaved)
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
    // Allocates or updates a fixed memory slot for a specific model ID
    bool configureStagingSlot(int32_t slotId, int width, int height, int channels, 
                              float meanR, float meanG, float meanB, 
                              float stdR, float stdG, float stdB, bool isPlanarCHW);
    
    // Grabs the master cv::Mat from your image handle, processes it into the staging slot
    bool prepareStageInput(int64_t imageHandle, int32_t slotId);
    
    // Returns the raw 64-bit memory pointer of the staging buffer to pass directly to ONNX
    void* getStagePointer(int32_t slotId);
    
    // Frees the allocated memory block when a feature or screen is closed
    void freeStagingSlot(int32_t slotId);
}

#endif // TENSOR_STAGING_H



C++ Processing Pipeline (tensor_staging.cpp)
C++
#include "tensor_staging.h"
#include "native_image.h" // Hooks into your existing handle registry mapping int64_t to cv::Mat
#include <opencv2/imgproc.hpp>
#include <map>
#include <mutex>

static std::map<int32_t, TensorStage> g_stagingRegistry;
static std::mutex g_stagingMutex;

bool configureStagingSlot(int32_t slotId, int width, int height, int channels, 
                          float meanR, float meanG, float meanB, 
                          float stdR, float stdG, float stdB, bool isPlanarCHW) {
    std::lock_guard<std::mutex> lock(g_stagingMutex);
    
    TensorStage& stage = g_stagingRegistry[slotId];
    size_t requiredBytes = width * height * channels * sizeof(float);
    
    // If already allocated with the exact same size, zero memory and reuse to prevent fragmentation
    if (stage.isAllocated && stage.bufferSizeInBytes == requiredBytes) {
        memset(stage.dataBuffer, 0, requiredBytes);
    } else {
        // Free old buffer allocation if dimensions or allocations changed
        if (stage.dataBuffer) free(stage.dataBuffer);
        
        // Allocate a predictable, continuous chunk of native heap memory
        stage.dataBuffer = malloc(requiredBytes);
        if (!stage.dataBuffer) return false;
        stage.bufferSizeInBytes = requiredBytes;
        stage.isAllocated = true;
    }
    
    // Hydrate configurations
    stage.config = { width, height, channels, {meanR, meanG, meanB}, {stdR, stdG, stdB}, isPlanarCHW };
    return true;
}

bool prepareStageInput(int64_t imageHandle, int32_t slotId) {
    std::lock_guard<std::mutex> lock(g_stagingMutex);
    
    // 1. Resolve master high-res image matrix from handle registry
    cv::Mat* masterMat = getMatFromHandle(imageHandle); 
    if (!masterMat || masterMat->empty()) return false;
    
    // 2. Resolve target staging slot parameters
    auto it = g_stagingRegistry.find(slotId);
    if (it == g_stagingRegistry.end() || !it->second.isAllocated) return false;
    TensorStage& stage = it->second;
    
    // 3. Fast hardware-accelerated geometric downsample via OpenCV imgproc
    cv::Mat resizedMat;
    cv::resize(*masterMat, resizedMat, cv::Size(stage.config.targetWidth, stage.config.targetHeight), 0, 0, cv::INTER_LINEAR);
    
    // Standardise internal working colorspaces to 3-channel RGB matrix format
    if (resizedMat.channels() == 4) {
        cv::cvtColor(resizedMat, resizedMat, cv::COLOR_RGBA2RGB);
    } else if (resizedMat.channels() == 1) {
        cv::cvtColor(resizedMat, resizedMat, cv::COLOR_GRAY2RGB);
    }
    
    float* floatBuffer = static_cast<float*>(stage.dataBuffer);
    int w = stage.config.targetWidth;
    int h = stage.config.targetHeight;
    
    // 4. Transform data structure layout directly into the pre-allocated float buffer
    if (stage.config.isPlanarCHW) {
        // Planar Format (CHW): Separate Contiguous Channel Arrays [RRR...GG x...BBB...]
        int planeSize = w * h;
        for (int y = 0; y < h; ++y) {
            for (int x = 0; x < w; ++x) {
                cv::Vec3b pixel = resizedMat.at<cv::Vec3b>(y, x);
                int pixelIdx = y * w + x;
                
                // Read OpenCV standard BGR ➔ Cast to Float ➔ Normalise ➔ Partition to Planar Planes
                floatBuffer[pixelIdx]                 = ((pixel[2] / 255.0f) - stage.config.mean[0]) / stage.config.stdDev[0]; // R
                floatBuffer[planeSize + pixelIdx]      = ((pixel[1] / 255.0f) - stage.config.mean[1]) / stage.config.stdDev[1]; // G
                floatBuffer[(planeSize * 2) + pixelIdx] = ((pixel[0] / 255.0f) - stage.config.mean[2]) / stage.config.stdDev[2]; // B
            }
        }
    } else {
        // Interleaved Format (HWC): Contiguous RGB RGB RGB structures
        for (int y = 0; y < h; ++y) {
            for (int x = 0; x < w; ++x) {
                cv::Vec3b pixel = resizedMat.at<cv::Vec3b>(y, x);
                int bufferIdx = (y * w + x) * 3;
                
                floatBuffer[bufferIdx]     = ((pixel[2] / 255.0f) - stage.config.mean[0]) / stage.config.stdDev[0]; // R
                floatBuffer[bufferIdx + 1] = ((pixel[1] / 255.0f) - stage.config.mean[1]) / stage.config.stdDev[1]; // G
                floatBuffer[bufferIdx + 2] = ((pixel[0] / 255.0f) - stage.config.mean[2]) / stage.config.stdDev[2]; // B
            }
        }
    }
    
    return true;
}

void* getStagePointer(int32_t slotId) {
    std::lock_guard<std::mutex> lock(g_stagingMutex);
    auto it = g_stagingRegistry.find(slotId);
    if (it != g_stagingRegistry.end() && it->second.isAllocated) {
        return it->second.dataBuffer;
    }
    return nullptr;
}

void freeStagingSlot(int32_t slotId) {
    std::lock_guard<std::mutex> lock(g_stagingMutex);
    auto it = g_stagingRegistry.find(slotId);
    if (it != g_stagingRegistry.end()) {
        if (it->second.dataBuffer) free(it->second.dataBuffer);
        g_stagingRegistry.erase(it);
    }
}



4. Flutter Dart FFI Interface Binding (ai_staging_bridge.dart)
Dart
import 'dart:ffi';
import 'package:ffi/ffi.dart';

// Native function low-level C FFI signatures
typedef NativeConfigureSlot = Bool Function(Int32 slotId, Int32 width, Int32 height, Int32 channels, Float meanR, Float meanG, Float meanB, Float stdR, Float stdG, Float stdB, Bool isPlanar);
typedef DartConfigureSlot = bool Function(int slotId, int width, int height, int channels, double meanR, double meanG, double meanB, double stdR, double stdG, double stdB, bool isPlanar);

typedef NativePrepareInput = Bool Function(Int64 imageHandle, Int32 slotId);
typedef DartPrepareInput = bool Function(int imageHandle, int slotId);

typedef NativeGetPointer = Pointer<Void> Function(Int32 slotId);
typedef DartGetPointer = Pointer<Void> Function(int slotId);

typedef NativeFreeSlot = Void Function(Int32 slotId);
typedef DartFreeSlot = void Function(int slotId);

class AIStagingManager {
  late DynamicLibrary _nativeLib;
  late DartConfigureSlot _configureSlot;
  late DartPrepareInput _prepareInput;
  late DartGetPointer _getPointer;
  late DartFreeSlot _freeSlot;

  AIStagingManager() {
    // Interacts with your compiled shared library binary compilation target
    _nativeLib = DynamicLibrary.open('libvulkan_compute_engine.so');
    
    _configureSlot = _nativeLib.lookupFunction<NativeConfigureSlot, DartConfigureSlot>('configureStagingSlot');
    _prepareInput = _nativeLib.lookupFunction<NativePrepareInput, DartPrepareInput>('prepareStageInput');
    _getPointer = _nativeLib.lookupFunction<NativeGetPointer, DartGetPointer>('getStagePointer');
    _freeSlot = _nativeLib.lookupFunction<NativeFreeSlot, DartFreeSlot>('freeStagingSlot');
  }

  /// Allocates a predictable fixed memory slot for any future model configuration dimensions.
  bool initModelSlot({
    required int slotId,
    required int width,
    required int height,
    required int channels,
    required List<double> mean,
    required List<double> stdDev,
    required bool isPlanarCHW,
  }) {
    return _configureSlot(slotId, width, height, channels, mean[0], mean[1], mean[2], stdDev[0], stdDev[1], stdDev[2], isPlanarCHW);
  }

  /// Drops the current edited frame state down to the preallocated staging target address.
  bool populateSlotInput(int nativeImageHandle, int slotId) {
    return _prepareInput(nativeImageHandle, slotId);
  }

  /// Fetches the direct memory address pointer to feed your model interpreter engine (ONNX Runtime Mobile).
  Pointer<Void> getInputPointer(int slotId) {
    return _getPointer(slotId);
  }

  /// Explicitly releases the memory blocks allocation when exiting editing contexts.
  void releaseSlot(int slotId) {
    _freeSlot(slotId);
  }
}

***

Add `tensor_staging.cpp` to your `CMakeLists.txt` source array compilation list, hook up your custom `getMatFromHandle` hook to lookup your native matrices, and you are ready to configure any model size on the fly from Dart!