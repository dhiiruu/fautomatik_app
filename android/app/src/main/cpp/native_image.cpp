#include "native_image.h"
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/imgcodecs.hpp>
#include <vector>
#include <mutex>
#include <unordered_map>

// ── Internal reference-counted image store ──────────────────────────

struct NativeImage {
  cv::Mat mat;
  int refCount = 1;
};

static std::unordered_map<int64_t, NativeImage*> s_images;
static std::mutex s_mutex;
static int64_t s_nextHandle = 1;

static int64_t _store(NativeImage* img) {
  std::lock_guard<std::mutex> lock(s_mutex);
  int64_t h = s_nextHandle++;
  s_images[h] = img;
  return h;
}

static NativeImage* _get(int64_t handle) {
  std::lock_guard<std::mutex> lock(s_mutex);
  auto it = s_images.find(handle);
  return (it != s_images.end()) ? it->second : nullptr;
}

static void _remove(int64_t handle) {
  std::lock_guard<std::mutex> lock(s_mutex);
  s_images.erase(handle);
}

// ── Lifecycle ───────────────────────────────────────────────────────

int64_t nativeImage_createFromFile(const char* path) {
  if (!path) return 0;
  cv::Mat mat = cv::imread(path, cv::IMREAD_UNCHANGED);
  if (mat.empty()) return 0;
  auto* img = new NativeImage();
  img->mat = mat;
  return _store(img);
}

int64_t nativeImage_createFromBytes(const uint8_t* data, int32_t size) {
  if (!data || size <= 0) return 0;
  std::vector<uint8_t> buf(data, data + size);
  cv::Mat mat = cv::imdecode(buf, cv::IMREAD_UNCHANGED);
  if (mat.empty()) return 0;
  auto* img = new NativeImage();
  img->mat = mat;
  return _store(img);
}

int64_t nativeImage_createEmpty(int32_t width, int32_t height) {
  if (width <= 0 || height <= 0) return 0;
  auto* img = new NativeImage();
  img->mat = cv::Mat(height, width, CV_8UC4, cv::Scalar(0, 0, 0, 255));
  return _store(img);
}

int64_t nativeImage_fromRgba(const uint8_t* pixels, int32_t w, int32_t h) {
  if (!pixels || w <= 0 || h <= 0) return 0;
  auto* img = new NativeImage();
  img->mat = cv::Mat(h, w, CV_8UC4);
  std::memcpy(img->mat.data, pixels, w * h * 4);
  return _store(img);
}

int64_t nativeImage_clone(int64_t handle) {
  auto* img = _get(handle);
  if (!img) return 0;
  img->refCount++;
  return handle; // Same handle, ref incremented
}

void nativeImage_release(int64_t handle) {
  auto* img = _get(handle);
  if (!img) return;
  img->refCount--;
  if (img->refCount <= 0) {
    _remove(handle);
    delete img;
  }
}

// ── Accessors ───────────────────────────────────────────────────────

int32_t nativeImage_width(int64_t handle) {
  auto* img = _get(handle);
  return img ? img->mat.cols : 0;
}

int32_t nativeImage_height(int64_t handle) {
  auto* img = _get(handle);
  return img ? img->mat.rows : 0;
}

int32_t nativeImage_channels(int64_t handle) {
  auto* img = _get(handle);
  return img ? img->mat.channels() : 0;
}

int32_t nativeImage_totalBytes(int64_t handle) {
  auto* img = _get(handle);
  return img ? img->mat.total() * img->mat.elemSize() : 0;
}

uint8_t* nativeImage_data(int64_t handle) {
  auto* img = _get(handle);
  return img ? img->mat.data : nullptr;
}

// ── Mat accessor ────────────────────────────────────────────────────

void* nativeImage_getMat(int64_t handle) {
  auto* img = _get(handle);
  return img ? &img->mat : nullptr;
}

// ── Operations (in-place) ───────────────────────────────────────────

int32_t nativeImage_cvtColor(int64_t handle, int32_t code) {
  auto* img = _get(handle);
  if (!img) return -1;
  cv::Mat out;
  cv::cvtColor(img->mat, out, code);
  img->mat = out;
  return 0;
}

int32_t nativeImage_resize(int64_t handle, int32_t w, int32_t h, int32_t interpolation) {
  auto* img = _get(handle);
  if (!img || w <= 0 || h <= 0) return -1;
  static const int interpMap[] = {
    cv::INTER_NEAREST, cv::INTER_LINEAR, cv::INTER_CUBIC, cv::INTER_AREA
  };
  int interp = (interpolation >= 0 && interpolation < 4) ? interpMap[interpolation] : cv::INTER_LINEAR;
  cv::Mat out;
  cv::resize(img->mat, out, cv::Size(w, h), 0, 0, interp);
  img->mat = out;
  return 0;
}

int32_t nativeImage_gaussianBlur(int64_t handle, int32_t kx, int32_t ky,
                                  double sigmaX, double sigmaY) {
  auto* img = _get(handle);
  if (!img) return -1;
  kx = (kx % 2 == 0) ? kx + 1 : kx; // ensure odd
  ky = (ky % 2 == 0) ? ky + 1 : ky;
  cv::Mat out;
  cv::GaussianBlur(img->mat, out, cv::Size(kx, ky), sigmaX, sigmaY);
  img->mat = out;
  return 0;
}

int32_t nativeImage_sobel(int64_t handle, int32_t ddepth, int32_t dx, int32_t dy, int32_t ksize) {
  auto* img = _get(handle);
  if (!img) return -1;
  ksize = (ksize % 2 == 0) ? ksize + 1 : ksize;
  cv::Mat out;
  cv::Sobel(img->mat, out, ddepth, dx, dy, ksize);
  img->mat = out;
  return 0;
}

// ── Raw pixel I/O ───────────────────────────────────────────────────

int32_t nativeImage_readPixels(int64_t handle, int32_t x, int32_t y,
                                int32_t w, int32_t h, uint8_t* buffer) {
  auto* img = _get(handle);
  if (!img || !buffer) return -1;
  cv::Rect roi(x, y, w, h);
  if (roi.x < 0 || roi.y < 0 ||
      roi.x + roi.w > img->mat.cols ||
      roi.y + roi.h > img->mat.rows) return -1;
  cv::Mat crop(img->mat, roi);
  std::memcpy(buffer, crop.data, w * h * crop.elemSize());
  return w * h * crop.elemSize();
}

// ── Vulkan bridge helpers ───────────────────────────────────────────

int32_t nativeImage_copyToRgba(int64_t handle, uint8_t* outBuffer) {
  auto* img = _get(handle);
  if (!img || !outBuffer) return -1;

  cv::Mat rgbaMat;
  if (img->mat.channels() == 4) {
    // Already RGBA? OpenCV uses BGRA — swap R↔B.
    cv::cvtColor(img->mat, rgbaMat, cv::COLOR_BGRA2RGBA);
  } else if (img->mat.channels() == 3) {
    // BGR → RGBA
    cv::cvtColor(img->mat, rgbaMat, cv::COLOR_BGR2RGBA);
  } else if (img->mat.channels() == 1) {
    // Gray → RGBA
    cv::cvtColor(img->mat, rgbaMat, cv::COLOR_GRAY2RGBA);
  } else {
    return -1;
  }

  int32_t bytes = rgbaMat.total() * rgbaMat.elemSize();
  std::memcpy(outBuffer, rgbaMat.data, bytes);
  return bytes;
}

// ── Texture display ─────────────────────────────────────────────────

int32_t nativeImage_copyToWindowBuffer(int64_t handle, ANativeWindow_Buffer* buffer) {
  auto* img = _get(handle);
  if (!img || !buffer || !buffer->bits) return -1;

  cv::Mat rgba;
  const int c = img->mat.channels();
  if (c == 4) {
    cv::cvtColor(img->mat, rgba, cv::COLOR_BGRA2RGBA);
  } else if (c == 3) {
    cv::cvtColor(img->mat, rgba, cv::COLOR_BGR2RGBA);
  } else if (c == 1) {
    cv::cvtColor(img->mat, rgba, cv::COLOR_GRAY2RGBA);
  } else {
    return -1;
  }

  const int srcW = rgba.cols;
  const int srcH = rgba.rows;
  const int srcStride = srcW * 4;            // bytes per source row
  const int dstStride = buffer->stride * 4;  // bytes per dest row
  const int copyBytes = (srcStride < dstStride) ? srcStride : dstStride;
  const int copyRows = (srcH < buffer->height) ? srcH : buffer->height;

  uint8_t* dst = static_cast<uint8_t*>(buffer->bits);
  const uint8_t* src = rgba.data;

  for (int y = 0; y < copyRows; y++) {
    std::memcpy(dst + y * dstStride, src + y * srcStride, copyBytes);
  }
  return 0;
}
