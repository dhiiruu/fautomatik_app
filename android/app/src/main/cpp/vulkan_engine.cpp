#include "vulkan_engine.h"
#include "vulkan_loader.h"
#include <cstring>
#include <cstdio>
#include <algorithm>
#include <vector>

// ────────────────────────────────────────────────────────────────────────────
// Global Vulkan loader (resolved at runtime on Android via dlopen)
// ────────────────────────────────────────────────────────────────────────────
static VkLib g_vk;
#define VK g_vk

// Convenience: wrap loader function calls so the rest of the code reads naturally.
// The loader resolves the same-named function pointers so we can call them directly.
// (The VK macro is just for clarity — the pointers ARE the function names.)
#define vkCreateInstance                   VK.vkCreateInstance
#define vkDestroyInstance                  VK.vkDestroyInstance
#define vkEnumeratePhysicalDevices         VK.vkEnumeratePhysicalDevices
#define vkGetPhysicalDeviceProperties      VK.vkGetPhysicalDeviceProperties
#define vkGetPhysicalDeviceMemoryProperties VK.vkGetPhysicalDeviceMemoryProperties
#define vkGetPhysicalDeviceQueueFamilyProperties VK.vkGetPhysicalDeviceQueueFamilyProperties
#define vkCreateDevice                     VK.vkCreateDevice
#define vkDestroyDevice                    VK.vkDestroyDevice
#define vkGetDeviceQueue                   VK.vkGetDeviceQueue
#define vkDeviceWaitIdle                   VK.vkDeviceWaitIdle
#define vkCreateCommandPool                VK.vkCreateCommandPool
#define vkDestroyCommandPool               VK.vkDestroyCommandPool
#define vkAllocateCommandBuffers           VK.vkAllocateCommandBuffers
#define vkFreeCommandBuffers               VK.vkFreeCommandBuffers
#define vkBeginCommandBuffer               VK.vkBeginCommandBuffer
#define vkEndCommandBuffer                 VK.vkEndCommandBuffer
#define vkQueueSubmit                      VK.vkQueueSubmit
#define vkQueueWaitIdle                    VK.vkQueueWaitIdle
#define vkCreateBuffer                     VK.vkCreateBuffer
#define vkDestroyBuffer                    VK.vkDestroyBuffer
#define vkGetBufferMemoryRequirements      VK.vkGetBufferMemoryRequirements
#define vkAllocateMemory                   VK.vkAllocateMemory
#define vkFreeMemory                       VK.vkFreeMemory
#define vkBindBufferMemory                 VK.vkBindBufferMemory
#define vkMapMemory                        VK.vkMapMemory
#define vkUnmapMemory                      VK.vkUnmapMemory
#define vkCmdCopyBuffer                    VK.vkCmdCopyBuffer
#define vkCreateShaderModule               VK.vkCreateShaderModule
#define vkDestroyShaderModule              VK.vkDestroyShaderModule
#define vkCreateDescriptorSetLayout        VK.vkCreateDescriptorSetLayout
#define vkDestroyDescriptorSetLayout       VK.vkDestroyDescriptorSetLayout
#define vkCreatePipelineLayout             VK.vkCreatePipelineLayout
#define vkDestroyPipelineLayout            VK.vkDestroyPipelineLayout
#define vkCreateComputePipelines           VK.vkCreateComputePipelines
#define vkDestroyPipeline                  VK.vkDestroyPipeline
#define vkCreateDescriptorPool             VK.vkCreateDescriptorPool
#define vkDestroyDescriptorPool            VK.vkDestroyDescriptorPool
#define vkAllocateDescriptorSets           VK.vkAllocateDescriptorSets
#define vkFreeDescriptorSets               VK.vkFreeDescriptorSets
#define vkUpdateDescriptorSets             VK.vkUpdateDescriptorSets
#define vkCmdBindPipeline                  VK.vkCmdBindPipeline
#define vkCmdBindDescriptorSets            VK.vkCmdBindDescriptorSets
#define vkCmdDispatch                      VK.vkCmdDispatch

// ────────────────────────────────────────────────────────────────────────────
// Internal structures
// ────────────────────────────────────────────────────────────────────────────

struct VkBufferHandle {
  VkBuffer buffer = VK_NULL_HANDLE;
  VkDeviceMemory memory = VK_NULL_HANDLE;
  VkDeviceSize size = 0;
  int32_t width = 0;
  int32_t height = 0;
  ImageFormat format = ImageFormat::RGBA8;
};

struct VkShaderHandle {
  VkShaderModule module = VK_NULL_HANDLE;
  std::string entryPoint = "main";
};

struct VkPipelineHandle {
  VkDescriptorSetLayout descLayout = VK_NULL_HANDLE;
  VkPipelineLayout pipelineLayout = VK_NULL_HANDLE;
  VkPipeline pipeline = VK_NULL_HANDLE;
  VkDescriptorPool descPool = VK_NULL_HANDLE;
  VkDescriptorSet descSet = VK_NULL_HANDLE;
  int32_t localSizeX = 16;
  int32_t localSizeY = 16;
  int32_t localSizeZ = 1;
};

struct VkEngineContext {
  bool initialized = false;
  VkInstance instance = VK_NULL_HANDLE;
  VkPhysicalDevice physDevice = VK_NULL_HANDLE;
  VkDevice device = VK_NULL_HANDLE;
  VkQueue computeQueue = VK_NULL_HANDLE;
  VkCommandPool cmdPool = VK_NULL_HANDLE;
  uint32_t computeQueueFamily = UINT32_MAX;
  VkPhysicalDeviceProperties deviceProps{};
  VkPhysicalDeviceMemoryProperties memProps{};
  VkBuffer stagingBuffer = VK_NULL_HANDLE;
  VkDeviceMemory stagingMemory = VK_NULL_HANDLE;
  VkDeviceSize stagingSize = 0;
  void* stagingMapped = nullptr;
};

// ────────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────────

static bool _findComputeQueueFamily(VkPhysicalDevice pd, uint32_t* out) {
  uint32_t n = 0;
  vkGetPhysicalDeviceQueueFamilyProperties(pd, &n, nullptr);
  std::vector<VkQueueFamilyProperties> props(n);
  vkGetPhysicalDeviceQueueFamilyProperties(pd, &n, props.data());
  for (uint32_t i = 0; i < n; i++)
    if (props[i].queueFlags & VK_QUEUE_COMPUTE_BIT) { *out = i; return true; }
  return false;
}

static uint32_t _findMemType(VkEngineContext* ctx, uint32_t bits, VkMemoryPropertyFlags flags) {
  for (uint32_t i = 0; i < ctx->memProps.memoryTypeCount; i++)
    if ((bits & (1 << i)) && (ctx->memProps.memoryTypes[i].propertyFlags & flags) == flags)
      return i;
  return UINT32_MAX;
}

static bool _ensureStaging(VkEngineContext* ctx, VkDeviceSize size) {
  if (ctx->stagingSize >= size) return true;
  if (ctx->stagingBuffer) {
    vkUnmapMemory(ctx->device, ctx->stagingMemory);
    vkDestroyBuffer(ctx->device, ctx->stagingBuffer, nullptr);
    vkFreeMemory(ctx->device, ctx->stagingMemory, nullptr);
  }
  VkBufferCreateInfo bi{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
  bi.size = size;
  bi.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT;
  bi.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
  if (vkCreateBuffer(ctx->device, &bi, nullptr, &ctx->stagingBuffer) != VK_SUCCESS) return false;
  VkMemoryRequirements mr; vkGetBufferMemoryRequirements(ctx->device, ctx->stagingBuffer, &mr);
  VkMemoryAllocateInfo ai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
  ai.allocationSize = mr.size;
  ai.memoryTypeIndex = _findMemType(ctx, mr.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT);
  if (ai.memoryTypeIndex == UINT32_MAX) return false;
  if (vkAllocateMemory(ctx->device, &ai, nullptr, &ctx->stagingMemory) != VK_SUCCESS) return false;
  vkBindBufferMemory(ctx->device, ctx->stagingBuffer, ctx->stagingMemory, 0);
  vkMapMemory(ctx->device, ctx->stagingMemory, 0, size, 0, &ctx->stagingMapped);
  ctx->stagingSize = size;
  return true;
}

static int32_t _copyViaStaging(VkEngineContext* ctx, VkBuffer src, VkBuffer dst,
                                VkDeviceSize size, bool toDevice) {
  if (!_ensureStaging(ctx, size))
    return static_cast<int32_t>(VkEngineResult::ErrorMemoryAllocation);

  VkCommandBufferAllocateInfo ca{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
  ca.commandPool = ctx->cmdPool; ca.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY; ca.commandBufferCount = 1;
  VkCommandBuffer cb;
  vkAllocateCommandBuffers(ctx->device, &ca, &cb);
  VkCommandBufferBeginInfo bi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
  bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
  vkBeginCommandBuffer(cb, &bi);
  VkBufferCopy cp{}; cp.size = size;
  if (toDevice)
    vkCmdCopyBuffer(cb, src, dst, 1, &cp);
  else
    vkCmdCopyBuffer(cb, src, dst, 1, &cp);
  vkEndCommandBuffer(cb);
  VkSubmitInfo si{VK_STRUCTURE_TYPE_SUBMIT_INFO}; si.commandBufferCount = 1; si.pCommandBuffers = &cb;
  vkQueueSubmit(ctx->computeQueue, 1, &si, VK_NULL_HANDLE);
  vkQueueWaitIdle(ctx->computeQueue);
  vkFreeCommandBuffers(ctx->device, ctx->cmdPool, 1, &cb);
  return static_cast<int32_t>(VkEngineResult::Success);
}

// ────────────────────────────────────────────────────────────────────────────
// C API implementation
// ────────────────────────────────────────────────────────────────────────────

VkEngineContext* vkEngine_create() { return new VkEngineContext(); }

void vkEngine_destroy(VkEngineContext* ctx) {
  if (!ctx) return;
  if (ctx->device) {
    vkDeviceWaitIdle(ctx->device);
    if (ctx->stagingBuffer) {
      vkUnmapMemory(ctx->device, ctx->stagingMemory);
      vkDestroyBuffer(ctx->device, ctx->stagingBuffer, nullptr);
      vkFreeMemory(ctx->device, ctx->stagingMemory, nullptr);
    }
    if (ctx->cmdPool) vkDestroyCommandPool(ctx->device, ctx->cmdPool, nullptr);
    vkDestroyDevice(ctx->device, nullptr);
  }
  if (ctx->instance) vkDestroyInstance(ctx->instance, nullptr);
  delete ctx;
}

int32_t vkEngine_init(VkEngineContext* ctx) {
  if (!ctx) return static_cast<int32_t>(VkEngineResult::ErrorInvalidParam);
  if (!g_vk.load()) return static_cast<int32_t>(VkEngineResult::ErrorVulkanNotAvailable);

  VkApplicationInfo ai{VK_STRUCTURE_TYPE_APPLICATION_INFO};
  ai.pApplicationName = "VulkanCompute"; ai.apiVersion = VK_API_VERSION_1_2;
  VkInstanceCreateInfo ii{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO}; ii.pApplicationInfo = &ai;
  if (vkCreateInstance(&ii, nullptr, &ctx->instance) != VK_SUCCESS)
    return static_cast<int32_t>(VkEngineResult::ErrorVulkanNotAvailable);

  uint32_t dc = 0;
  vkEnumeratePhysicalDevices(ctx->instance, &dc, nullptr);
  if (!dc) return static_cast<int32_t>(VkEngineResult::ErrorNoPhysicalDevice);
  std::vector<VkPhysicalDevice> devices(dc);
  vkEnumeratePhysicalDevices(ctx->instance, &dc, devices.data());
  for (auto& d : devices) {
    vkGetPhysicalDeviceProperties(d, &ctx->deviceProps);
    if (ctx->deviceProps.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
      ctx->physDevice = d; break;
    }
  }
  if (!ctx->physDevice) { ctx->physDevice = devices[0]; vkGetPhysicalDeviceProperties(ctx->physDevice, &ctx->deviceProps); }
  vkGetPhysicalDeviceMemoryProperties(ctx->physDevice, &ctx->memProps);
  if (!_findComputeQueueFamily(ctx->physDevice, &ctx->computeQueueFamily))
    return static_cast<int32_t>(VkEngineResult::ErrorNoPhysicalDevice);

  const float pq = 1.0f;
  VkDeviceQueueCreateInfo qi{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
  qi.queueFamilyIndex = ctx->computeQueueFamily; qi.queueCount = 1; qi.pQueuePriorities = &pq;
  VkDeviceCreateInfo di{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
  di.queueCreateInfoCount = 1; di.pQueueCreateInfos = &qi;
  if (vkCreateDevice(ctx->physDevice, &di, nullptr, &ctx->device) != VK_SUCCESS)
    return static_cast<int32_t>(VkEngineResult::ErrorDeviceCreation);
  vkGetDeviceQueue(ctx->device, ctx->computeQueueFamily, 0, &ctx->computeQueue);

  VkCommandPoolCreateInfo pi{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
  pi.queueFamilyIndex = ctx->computeQueueFamily;
  pi.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
  if (vkCreateCommandPool(ctx->device, &pi, nullptr, &ctx->cmdPool) != VK_SUCCESS)
    return static_cast<int32_t>(VkEngineResult::ErrorDeviceCreation);

  ctx->initialized = true;
  return static_cast<int32_t>(VkEngineResult::Success);
}

int32_t vkEngine_getDeviceInfo(VkEngineContext* ctx, char* buf, int32_t n) {
  if (!ctx || !buf || n <= 0) return static_cast<int32_t>(VkEngineResult::ErrorInvalidParam);
  std::snprintf(buf, n, "%s | Vulkan %d.%d.%d",
           ctx->deviceProps.deviceName,
           VK_VERSION_MAJOR(ctx->deviceProps.apiVersion),
           VK_VERSION_MINOR(ctx->deviceProps.apiVersion),
           VK_VERSION_PATCH(ctx->deviceProps.apiVersion));
  return static_cast<int32_t>(VkEngineResult::Success);
}

// ── Buffers ─────────────────────────────────────────────────────────────

VkBufferHandle* vkEngine_createBuffer(VkEngineContext* ctx, int32_t w, int32_t h, int32_t fmt) {
  if (!ctx || w <= 0 || h <= 0 || w > kMaxImageWidth || h > kMaxImageHeight) return nullptr;
  auto* b = new VkBufferHandle();
  b->width = w; b->height = h; b->format = static_cast<ImageFormat>(fmt);
  uint32_t bpp = (fmt == static_cast<int32_t>(ImageFormat::GRAY8)) ? 1 : 4;
  b->size = static_cast<VkDeviceSize>(w) * h * bpp;

  VkBufferCreateInfo bi{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
  bi.size = b->size;
  bi.usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT;
  if (vkCreateBuffer(ctx->device, &bi, nullptr, &b->buffer) != VK_SUCCESS) { delete b; return nullptr; }
  VkMemoryRequirements mr; vkGetBufferMemoryRequirements(ctx->device, b->buffer, &mr);
  VkMemoryAllocateInfo ai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO}; ai.allocationSize = mr.size;
  ai.memoryTypeIndex = _findMemType(ctx, mr.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
  if (ai.memoryTypeIndex == UINT32_MAX) { vkDestroyBuffer(ctx->device, b->buffer, nullptr); delete b; return nullptr; }
  if (vkAllocateMemory(ctx->device, &ai, nullptr, &b->memory) != VK_SUCCESS) { vkDestroyBuffer(ctx->device, b->buffer, nullptr); delete b; return nullptr; }
  vkBindBufferMemory(ctx->device, b->buffer, b->memory, 0);
  return b;
}

void vkEngine_destroyBuffer(VkEngineContext* ctx, VkBufferHandle* b) {
  if (!ctx || !b) return;
  if (b->buffer) vkDestroyBuffer(ctx->device, b->buffer, nullptr);
  if (b->memory) vkFreeMemory(ctx->device, b->memory, nullptr);
  delete b;
}

int32_t vkEngine_uploadToBuffer(VkEngineContext* ctx, VkBufferHandle* buf, const uint8_t* data, int32_t size) {
  if (!ctx || !buf || !data || size > static_cast<int32_t>(buf->size))
    return static_cast<int32_t>(VkEngineResult::ErrorInvalidParam);
  std::memcpy(ctx->stagingMapped, data, size);
  return _copyViaStaging(ctx, ctx->stagingBuffer, buf->buffer, size, true);
}

int32_t vkEngine_downloadFromBuffer(VkEngineContext* ctx, VkBufferHandle* buf, uint8_t* outData, int32_t size) {
  if (!ctx || !buf || !outData || size > static_cast<int32_t>(buf->size))
    return static_cast<int32_t>(VkEngineResult::ErrorInvalidParam);
  int32_t r = _copyViaStaging(ctx, buf->buffer, ctx->stagingBuffer, size, false);
  if (r == 0) std::memcpy(outData, ctx->stagingMapped, size);
  return r;
}

// ── Shaders ────────────────────────────────────────────────────────────

VkShaderHandle* vkEngine_createShaderFromSpirv(VkEngineContext* ctx, const uint8_t* data, int32_t size, const char* ep) {
  if (!ctx || !data || size <= 0) return nullptr;
  auto* s = new VkShaderHandle();
  if (ep) s->entryPoint = ep;
  VkShaderModuleCreateInfo mi{VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
  mi.codeSize = size; mi.pCode = reinterpret_cast<const uint32_t*>(data);
  if (vkCreateShaderModule(ctx->device, &mi, nullptr, &s->module) != VK_SUCCESS) { delete s; return nullptr; }
  return s;
}

VkShaderHandle* vkEngine_createShaderFromGLSL(VkEngineContext*, const char*, const char*) { return nullptr; }

void vkEngine_destroyShader(VkEngineContext* ctx, VkShaderHandle* s) {
  if (!ctx || !s) return;
  if (s->module) vkDestroyShaderModule(ctx->device, s->module, nullptr);
  delete s;
}

// ── Pipeline ──────────────────────────────────────────────────────────

VkPipelineHandle* vkEngine_createPipeline(VkEngineContext* ctx, VkShaderHandle* shader,
                                            int32_t lsx, int32_t lsy, int32_t lsz) {
  if (!ctx || !shader) return nullptr;
  auto* p = new VkPipelineHandle();
  p->localSizeX = lsx; p->localSizeY = lsy; p->localSizeZ = lsz;

  std::vector<VkDescriptorSetLayoutBinding> bindings(3);
  for (int i = 0; i < 3; i++) {
    bindings[i].binding = i; bindings[i].descriptorCount = 1; bindings[i].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
  }
  bindings[0].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
  bindings[1].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
  bindings[2].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;

  VkDescriptorSetLayoutCreateInfo li{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
  li.bindingCount = 3; li.pBindings = bindings.data();
  if (vkCreateDescriptorSetLayout(ctx->device, &li, nullptr, &p->descLayout) != VK_SUCCESS) { delete p; return nullptr; }

  VkPipelineLayoutCreateInfo pli{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
  pli.setLayoutCount = 1; pli.pSetLayouts = &p->descLayout;
  if (vkCreatePipelineLayout(ctx->device, &pli, nullptr, &p->pipelineLayout) != VK_SUCCESS) { vkDestroyDescriptorSetLayout(ctx->device, p->descLayout, nullptr); delete p; return nullptr; }

  VkPipelineShaderStageCreateInfo si{VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO};
  si.stage = VK_SHADER_STAGE_COMPUTE_BIT; si.module = shader->module; si.pName = shader->entryPoint.c_str();
  VkComputePipelineCreateInfo ci{VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO};
  ci.stage = si; ci.layout = p->pipelineLayout;
  if (vkCreateComputePipelines(ctx->device, VK_NULL_HANDLE, 1, &ci, nullptr, &p->pipeline) != VK_SUCCESS) {
    vkDestroyPipelineLayout(ctx->device, p->pipelineLayout, nullptr);
    vkDestroyDescriptorSetLayout(ctx->device, p->descLayout, nullptr); delete p; return nullptr;
  }

  std::vector<VkDescriptorPoolSize> ps(2);
  ps[0].type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER; ps[0].descriptorCount = 2;
  ps[1].type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER; ps[1].descriptorCount = 1;
  VkDescriptorPoolCreateInfo dpci{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
  dpci.poolSizeCount = 2; dpci.pPoolSizes = ps.data(); dpci.maxSets = 1;
  if (vkCreateDescriptorPool(ctx->device, &dpci, nullptr, &p->descPool) != VK_SUCCESS) {
    vkDestroyPipeline(ctx->device, p->pipeline, nullptr);
    vkDestroyPipelineLayout(ctx->device, p->pipelineLayout, nullptr);
    vkDestroyDescriptorSetLayout(ctx->device, p->descLayout, nullptr); delete p; return nullptr;
  }

  VkDescriptorSetAllocateInfo dai{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
  dai.descriptorPool = p->descPool; dai.descriptorSetCount = 1; dai.pSetLayouts = &p->descLayout;
  if (vkAllocateDescriptorSets(ctx->device, &dai, &p->descSet) != VK_SUCCESS) {
    vkDestroyDescriptorPool(ctx->device, p->descPool, nullptr);
    vkDestroyPipeline(ctx->device, p->pipeline, nullptr);
    vkDestroyPipelineLayout(ctx->device, p->pipelineLayout, nullptr);
    vkDestroyDescriptorSetLayout(ctx->device, p->descLayout, nullptr); delete p; return nullptr;
  }
  return p;
}

void vkEngine_destroyPipeline(VkEngineContext* ctx, VkPipelineHandle* p) {
  if (!ctx || !p) return;
  if (p->descSet) vkFreeDescriptorSets(ctx->device, p->descPool, 1, &p->descSet);
  if (p->descPool) vkDestroyDescriptorPool(ctx->device, p->descPool, nullptr);
  if (p->pipeline) vkDestroyPipeline(ctx->device, p->pipeline, nullptr);
  if (p->pipelineLayout) vkDestroyPipelineLayout(ctx->device, p->pipelineLayout, nullptr);
  if (p->descLayout) vkDestroyDescriptorSetLayout(ctx->device, p->descLayout, nullptr);
  delete p;
}

// ── Dispatch ──────────────────────────────────────────────────────────

int32_t vkEngine_dispatch(VkEngineContext* ctx, VkPipelineHandle* pipeline,
                          VkBufferHandle* input, VkBufferHandle* output,
                          const float* params, int32_t paramCount,
                          int32_t width, int32_t height) {
  if (!ctx || !pipeline || !input || !output)
    return static_cast<int32_t>(VkEngineResult::ErrorInvalidParam);

  VkDeviceSize psize = std::max(static_cast<VkDeviceSize>(paramCount) * sizeof(float), static_cast<VkDeviceSize>(64));
  VkBuffer pb; VkDeviceMemory pm; void* pmap;
  VkBufferCreateInfo bi{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO}; bi.size = psize;
  bi.usage = VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
  if (vkCreateBuffer(ctx->device, &bi, nullptr, &pb) != VK_SUCCESS)
    return static_cast<int32_t>(VkEngineResult::ErrorBufferCreation);
  VkMemoryRequirements mr; vkGetBufferMemoryRequirements(ctx->device, pb, &mr);
  VkMemoryAllocateInfo ai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO}; ai.allocationSize = mr.size;
  ai.memoryTypeIndex = _findMemType(ctx, mr.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
  if (ai.memoryTypeIndex == UINT32_MAX) { vkDestroyBuffer(ctx->device, pb, nullptr); return static_cast<int32_t>(VkEngineResult::ErrorMemoryAllocation); }
  vkAllocateMemory(ctx->device, &ai, nullptr, &pm); vkBindBufferMemory(ctx->device, pb, pm, 0);
  vkMapMemory(ctx->device, pm, 0, psize, 0, &pmap);
  std::memcpy(pmap, params, paramCount * sizeof(float));
  if (psize > paramCount * sizeof(float))
    std::memset(static_cast<uint8_t*>(pmap) + paramCount * sizeof(float), 0, psize - paramCount * sizeof(float));
  vkUnmapMemory(ctx->device, pm);

  VkDescriptorBufferInfo ibi{input->buffer, 0, input->size};
  VkDescriptorBufferInfo obi{output->buffer, 0, output->size};
  VkDescriptorBufferInfo pbi{pb, 0, psize};

  VkWriteDescriptorSet w0{VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET}; w0.dstSet = pipeline->descSet; w0.dstBinding = 0; w0.descriptorCount = 1; w0.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER; w0.pBufferInfo = &ibi;
  VkWriteDescriptorSet w1{VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET}; w1.dstSet = pipeline->descSet; w1.dstBinding = 1; w1.descriptorCount = 1; w1.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER; w1.pBufferInfo = &obi;
  VkWriteDescriptorSet w2{VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET}; w2.dstSet = pipeline->descSet; w2.dstBinding = 2; w2.descriptorCount = 1; w2.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER; w2.pBufferInfo = &pbi;
  VkWriteDescriptorSet ws[] = {w0, w1, w2};
  vkUpdateDescriptorSets(ctx->device, 3, ws, 0, nullptr);

  VkCommandBufferAllocateInfo ca{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
  ca.commandPool = ctx->cmdPool; ca.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY; ca.commandBufferCount = 1;
  VkCommandBuffer cb; vkAllocateCommandBuffers(ctx->device, &ca, &cb);
  VkCommandBufferBeginInfo cbi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
  cbi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
  vkBeginCommandBuffer(cb, &cbi);
  vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline->pipeline);
  vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline->pipelineLayout, 0, 1, &pipeline->descSet, 0, nullptr);
  uint32_t gx = (width + pipeline->localSizeX - 1) / pipeline->localSizeX;
  uint32_t gy = (height + pipeline->localSizeY - 1) / pipeline->localSizeY;
  vkCmdDispatch(cb, gx, gy, 1);
  vkEndCommandBuffer(cb);
  VkSubmitInfo si{VK_STRUCTURE_TYPE_SUBMIT_INFO}; si.commandBufferCount = 1; si.pCommandBuffers = &cb;
  vkQueueSubmit(ctx->computeQueue, 1, &si, VK_NULL_HANDLE);
  vkQueueWaitIdle(ctx->computeQueue);
  vkFreeCommandBuffers(ctx->device, ctx->cmdPool, 1, &cb);
  vkDestroyBuffer(ctx->device, pb, nullptr); vkFreeMemory(ctx->device, pm, nullptr);
  return static_cast<int32_t>(VkEngineResult::Success);
}

// ── Convenience — include embedded shaders ────────────────────────────

#include "shaders/spv/grayscale.h"
#include "shaders/spv/brightness_contrast.h"
#include "shaders/spv/composite.h"
#include "shaders/spv/gaussian_blur.h"

static int32_t _runShader(VkEngineContext* ctx, const uint8_t* spv, int spvSize,
                           const uint8_t* input, uint8_t* output,
                           int w, int h, const float* params, int pc) {
  auto* s = vkEngine_createShaderFromSpirv(ctx, spv, spvSize, "main");
  if (!s) return static_cast<int32_t>(VkEngineResult::ErrorShaderCompilation);
  auto* p = vkEngine_createPipeline(ctx, s, 16, 16, 1);
  if (!p) { vkEngine_destroyShader(ctx, s); return static_cast<int32_t>(VkEngineResult::ErrorPipelineCreation); }
  auto* ib = vkEngine_createBuffer(ctx, w, h, 0);
  auto* ob = vkEngine_createBuffer(ctx, w, h, 0);
  if (!ib || !ob) { vkEngine_destroyPipeline(ctx, p); vkEngine_destroyShader(ctx, s); vkEngine_destroyBuffer(ctx, ib); vkEngine_destroyBuffer(ctx, ob); return static_cast<int32_t>(VkEngineResult::ErrorMemoryAllocation); }

  int32_t r = vkEngine_uploadToBuffer(ctx, ib, input, w * h * 4);
  if (r == 0) r = vkEngine_dispatch(ctx, p, ib, ob, params, pc, w, h);
  if (r == 0) r = vkEngine_downloadFromBuffer(ctx, ob, output, w * h * 4);

  vkEngine_destroyBuffer(ctx, ob); vkEngine_destroyBuffer(ctx, ib);
  vkEngine_destroyPipeline(ctx, p); vkEngine_destroyShader(ctx, s);
  return r;
}

int32_t vkEngine_processGrayscale(VkEngineContext* ctx, const uint8_t* input, uint8_t* output,
                                   int32_t w, int32_t h) {
  float params[4] = {0}; return _runShader(ctx, kGrayscaleSpv, kGrayscaleSpvSize, input, output, w, h, params, 0);
}

int32_t vkEngine_processBrightnessContrast(VkEngineContext* ctx, const uint8_t* input, uint8_t* output,
                                            int32_t w, int32_t h, float brightness, float contrast) {
  float params[4] = {brightness, contrast}; return _runShader(ctx, kBrightnessContrastSpv, kBrightnessContrastSpvSize, input, output, w, h, params, 2);
}

int32_t vkEngine_processComposite(VkEngineContext* ctx, const uint8_t* src, const uint8_t* mask,
                                   uint8_t* output, int32_t w, int32_t h,
                                   uint32_t bgColor, float maskThreshold, float featherRadius) {
  // Pack src + mask into one buffer: w*h RGBA pixels, then w*h mask bytes
  int32_t pixelCount = w * h;
  int32_t srcSize = pixelCount * 4;
  int32_t combinedSize = srcSize + pixelCount;

  auto* ib = vkEngine_createBuffer(ctx, w, h + 1, 0); // extra row for mask
  if (!ib) return static_cast<int32_t>(VkEngineResult::ErrorMemoryAllocation);

  int32_t r = vkEngine_uploadToBuffer(ctx, ib, src, srcSize);
  if (r != 0) { vkEngine_destroyBuffer(ctx, ib); return r; }

  auto* ob = vkEngine_createBuffer(ctx, w, h, 0);
  if (!ob) { vkEngine_destroyBuffer(ctx, ib); return static_cast<int32_t>(VkEngineResult::ErrorMemoryAllocation); }

  auto* s = vkEngine_createShaderFromSpirv(ctx, kCompositeSpv, kCompositeSpvSize, "main");
  if (!s) { vkEngine_destroyBuffer(ctx, ib); vkEngine_destroyBuffer(ctx, ob); return static_cast<int32_t>(VkEngineResult::ErrorShaderCompilation); }
  auto* p = vkEngine_createPipeline(ctx, s, 16, 16, 1);
  if (!p) { vkEngine_destroyShader(ctx, s); vkEngine_destroyBuffer(ctx, ib); vkEngine_destroyBuffer(ctx, ob); return static_cast<int32_t>(VkEngineResult::ErrorPipelineCreation); }

  // Write mask into the input buffer manually via staging
  vkEngine_downloadFromBuffer(ctx, ib, const_cast<uint8_t*>(src), srcSize); // download to temp
  // Actually we need to upload source first, then mask. Let's do it properly:
  // Re-upload with mask appended. We'll use a temp buffer.
  std::vector<uint8_t> combined(combinedSize);
  std::memcpy(combined.data(), src, srcSize);
  std::memcpy(combined.data() + srcSize, mask, pixelCount);

  // Re-create input buffer with combined data
  vkEngine_destroyBuffer(ctx, ib);
  ib = vkEngine_createBuffer(ctx, w, h + 1, 0);
  r = vkEngine_uploadToBuffer(ctx, ib, combined.data(), combinedSize);
  if (r != 0) { vkEngine_destroyBuffer(ctx, ib); vkEngine_destroyBuffer(ctx, ob); vkEngine_destroyPipeline(ctx, p); vkEngine_destroyShader(ctx, s); return r; }

  float bgf;
  std::memcpy(&bgf, &bgColor, sizeof(float));
  float params[4] = {bgf, maskThreshold, featherRadius, 0};
  r = vkEngine_dispatch(ctx, p, ib, ob, params, 4, w, h);
  if (r == 0) r = vkEngine_downloadFromBuffer(ctx, ob, output, srcSize);

  vkEngine_destroyBuffer(ctx, ob); vkEngine_destroyBuffer(ctx, ib);
  vkEngine_destroyPipeline(ctx, p); vkEngine_destroyShader(ctx, s);
  return r;
}
