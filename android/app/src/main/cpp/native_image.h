#ifndef NATIVE_IMAGE_H
#define NATIVE_IMAGE_H

#include <cstdint>
#include <android/native_window.h>

extern "C" {

// ── Lifecycle ───────────────────────────────────────────────────────

int64_t nativeImage_createFromFile(const char* path);
int64_t nativeImage_createFromBytes(const uint8_t* data, int32_t size);
int64_t nativeImage_createEmpty(int32_t width, int32_t height);
int64_t nativeImage_fromRgba(const uint8_t* pixels, int32_t w, int32_t h);
int64_t nativeImage_clone(int64_t handle);
void nativeImage_release(int64_t handle);

// ── Accessors ───────────────────────────────────────────────────────

int32_t nativeImage_width(int64_t handle);
int32_t nativeImage_height(int64_t handle);
int32_t nativeImage_channels(int64_t handle);
int32_t nativeImage_totalBytes(int64_t handle);
uint8_t* nativeImage_data(int64_t handle);

// Get the raw cv::Mat pointer for direct OpenCV access.
// The returned pointer is valid until nativeImage_release is called.
void* nativeImage_getMat(int64_t handle);

// ── Operations (in-place) ───────────────────────────────────────────

int32_t nativeImage_cvtColor(int64_t handle, int32_t code);
int32_t nativeImage_resize(int64_t handle, int32_t w, int32_t h, int32_t interpolation);
int32_t nativeImage_gaussianBlur(int64_t handle, int32_t kx, int32_t ky, double sigmaX, double sigmaY);
int32_t nativeImage_sobel(int64_t handle, int32_t ddepth, int32_t dx, int32_t dy, int32_t ksize);

// ── Raw pixel I/O ───────────────────────────────────────────────────

int32_t nativeImage_readPixels(int64_t handle, int32_t x, int32_t y,
                                int32_t w, int32_t h, uint8_t* buffer);
int32_t nativeImage_copyToRgba(int64_t handle, uint8_t* outBuffer);

// ── Texture display (zero-copy to ANativeWindow) ────────────────────

// Copy the native image into an ANativeWindow_Buffer for direct display.
// The buffer must already be locked via ANativeWindow_lock.
// Handles stride alignment and BGR→RGBA conversion internally.
// Returns 0 on success, -1 on error.
int32_t nativeImage_copyToWindowBuffer(int64_t handle, ANativeWindow_Buffer* buffer);

} // extern "C"

#endif // NATIVE_IMAGE_H
