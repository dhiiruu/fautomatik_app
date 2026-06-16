#include "tensor_staging.h"
#include "native_image.h"
#include <opencv2/imgproc.hpp>
#include <map>
#include <mutex>
#include <cstring>

static std::map<int32_t, TensorStage> g_stagingRegistry;
static std::mutex g_stagingMutex;

bool configureStagingSlot(int32_t slotId, int width, int height, int channels,
                          float meanR, float meanG, float meanB,
                          float stdR, float stdG, float stdB, bool isPlanarCHW) {
    std::lock_guard<std::mutex> lock(g_stagingMutex);

    TensorStage& stage = g_stagingRegistry[slotId];
    size_t requiredBytes = static_cast<size_t>(width) * height * channels * sizeof(float);

    if (stage.isAllocated && stage.bufferSizeInBytes == requiredBytes) {
        std::memset(stage.dataBuffer, 0, requiredBytes);
    } else {
        if (stage.dataBuffer) std::free(stage.dataBuffer);
        stage.dataBuffer = std::malloc(requiredBytes);
        if (!stage.dataBuffer) return false;
        stage.bufferSizeInBytes = requiredBytes;
        stage.isAllocated = true;
    }

    stage.config = {
        width, height, channels,
        {meanR, meanG, meanB},
        {stdR, stdG, stdB},
        isPlanarCHW
    };
    return true;
}

bool prepareStageInput(int64_t imageHandle, int32_t slotId) {
    std::lock_guard<std::mutex> lock(g_stagingMutex);

    auto* masterMat = static_cast<cv::Mat*>(nativeImage_getMat(imageHandle));
    if (!masterMat || masterMat->empty()) return false;

    auto it = g_stagingRegistry.find(slotId);
    if (it == g_stagingRegistry.end() || !it->second.isAllocated) return false;
    TensorStage& stage = it->second;

    cv::Mat resizedMat;
    cv::resize(*masterMat, resizedMat,
               cv::Size(stage.config.targetWidth, stage.config.targetHeight),
               0, 0, cv::INTER_LINEAR);

    // OpenCV stores BGR/BGRA natively. The normalization loop below
    // reads pixel[2]→R, pixel[1]→G, pixel[0]→B which assumes BGR order.
    if (resizedMat.channels() == 4) {
        cv::cvtColor(resizedMat, resizedMat, cv::COLOR_BGRA2BGR);
    } else if (resizedMat.channels() == 1) {
        cv::cvtColor(resizedMat, resizedMat, cv::COLOR_GRAY2BGR);
    }

    float* floatBuffer = static_cast<float*>(stage.dataBuffer);
    int w = stage.config.targetWidth;
    int h = stage.config.targetHeight;

    if (stage.config.isPlanarCHW) {
        int planeSize = w * h;
        for (int y = 0; y < h; ++y) {
            for (int x = 0; x < w; ++x) {
                cv::Vec3b pixel = resizedMat.at<cv::Vec3b>(y, x);
                int pixelIdx = y * w + x;

                floatBuffer[pixelIdx]                  = ((pixel[2] / 255.0f) - stage.config.mean[0]) / stage.config.stdDev[0];
                floatBuffer[planeSize + pixelIdx]       = ((pixel[1] / 255.0f) - stage.config.mean[1]) / stage.config.stdDev[1];
                floatBuffer[(planeSize * 2) + pixelIdx] = ((pixel[0] / 255.0f) - stage.config.mean[2]) / stage.config.stdDev[2];
            }
        }
    } else {
        for (int y = 0; y < h; ++y) {
            for (int x = 0; x < w; ++x) {
                cv::Vec3b pixel = resizedMat.at<cv::Vec3b>(y, x);
                int bufferIdx = (y * w + x) * 3;

                floatBuffer[bufferIdx]     = ((pixel[2] / 255.0f) - stage.config.mean[0]) / stage.config.stdDev[0];
                floatBuffer[bufferIdx + 1] = ((pixel[1] / 255.0f) - stage.config.mean[1]) / stage.config.stdDev[1];
                floatBuffer[bufferIdx + 2] = ((pixel[0] / 255.0f) - stage.config.mean[2]) / stage.config.stdDev[2];
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
        if (it->second.dataBuffer) std::free(it->second.dataBuffer);
        g_stagingRegistry.erase(it);
    }
}
