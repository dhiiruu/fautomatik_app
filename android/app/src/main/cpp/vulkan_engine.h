#ifndef VULKAN_COMPUTE_ENGINE_H
#define VULKAN_COMPUTE_ENGINE_H

#include <vulkan/vulkan.h>
#include <vector>
#include <memory>
#include <string>
#include <unordered_map>
#include <functional>

// Maximum supported image dimensions
constexpr uint32_t kMaxImageWidth = 8192;
constexpr uint32_t kMaxImageHeight = 8192;

// Error codes returned by the engine
enum class VkEngineResult : int32_t {
  Success = 0,
  ErrorVulkanNotAvailable = -1,
  ErrorNoPhysicalDevice = -2,
  ErrorDeviceCreation = -3,
  ErrorMemoryAllocation = -4,
  ErrorBufferCreation = -5,
  ErrorShaderCompilation = -6,
  ErrorPipelineCreation = -7,
  ErrorInvalidParam = -8,
  ErrorImageTooLarge = -9,
  ErrorNotInitialized = -10,
};

// Image format
enum class ImageFormat : int32_t {
  RGBA8 = 0,
  GRAY8 = 1,
};

// Shader source type
enum class ShaderSourceType : int32_t {
  SPIRV = 0,     // Pre-compiled SPIR-V binary
  GLSL = 1,      // GLSL source (requires shaderc at runtime)
};

// Shader parameter types
enum class ParamType : int32_t {
  Float = 0,
  Int = 1,
  Float2 = 2,
  Float4 = 3,
};

// Uniform parameter block (max 64 bytes for push constants or uniform buffer)
struct alignas(16) ShaderParams {
  float values[16]; // 64 bytes
};

// C-compatible handle for FFI
struct VkEngineContext;
struct VkShaderHandle;
struct VkBufferHandle;
struct VkPipelineHandle;

// ────────────────────────────────────────────────────────────────────────────
// C API — exported for Dart FFI
// ────────────────────────────────────────────────────────────────────────────
extern "C" {

// Engine lifecycle
VkEngineContext* vkEngine_create();
void vkEngine_destroy(VkEngineContext* ctx);
int32_t vkEngine_init(VkEngineContext* ctx);
int32_t vkEngine_getDeviceInfo(VkEngineContext* ctx, char* outBuf, int32_t bufSize);

// Buffer management
VkBufferHandle* vkEngine_createBuffer(VkEngineContext* ctx, int32_t width, int32_t height, int32_t format);
void vkEngine_destroyBuffer(VkEngineContext* ctx, VkBufferHandle* buf);
int32_t vkEngine_uploadToBuffer(VkEngineContext* ctx, VkBufferHandle* buf, const uint8_t* data, int32_t size);
int32_t vkEngine_downloadFromBuffer(VkEngineContext* ctx, VkBufferHandle* buf, uint8_t* outData, int32_t size);

// Shader management
VkShaderHandle* vkEngine_createShaderFromSpirv(
    VkEngineContext* ctx, const uint8_t* spirvData, int32_t spirvSize, const char* entryPoint);
VkShaderHandle* vkEngine_createShaderFromGLSL(
    VkEngineContext* ctx, const char* source, const char* entryPoint);
void vkEngine_destroyShader(VkEngineContext* ctx, VkShaderHandle* shader);

// Pipeline management
VkPipelineHandle* vkEngine_createPipeline(
    VkEngineContext* ctx, VkShaderHandle* shader,
    int32_t localSizeX, int32_t localSizeY, int32_t localSizeZ);
void vkEngine_destroyPipeline(VkEngineContext* ctx, VkPipelineHandle* pipeline);

// Dispatch
int32_t vkEngine_dispatch(
    VkEngineContext* ctx, VkPipelineHandle* pipeline,
    VkBufferHandle* input, VkBufferHandle* output,
    const float* params, int32_t paramCount,
    int32_t width, int32_t height);

// Convenience — single-call processing
int32_t vkEngine_processGrayscale(
    VkEngineContext* ctx, const uint8_t* input, uint8_t* output,
    int32_t width, int32_t height);
int32_t vkEngine_processBrightnessContrast(
    VkEngineContext* ctx, const uint8_t* input, uint8_t* output,
    int32_t width, int32_t height, float brightness, float contrast);
int32_t vkEngine_processComposite(
    VkEngineContext* ctx, const uint8_t* src, const uint8_t* mask,
    uint8_t* output, int32_t width, int32_t height,
    uint32_t bgColor, float maskThreshold, float featherRadius);

} // extern "C"

#endif // VULKAN_COMPUTE_ENGINE_H
