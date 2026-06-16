#include <jni.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include "native_image.h"

// HAL_PIXEL_FORMAT_RGBA_8888 = 1 (same as AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM)
// Defined here for API < 26 compatibility.
#ifndef AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM
#define AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM 1
#endif

extern "C" {

// ── JNI: copy native image into the SurfaceTexture-backed buffer ────

JNIEXPORT jint JNICALL
Java_com_example_fautomatik_app_TextureBridge_nativeUpdateTexture(
    JNIEnv* env, jobject /*thiz*/,
    jobject surfaceObj,
    jlong nativeHandle) {

  if (!surfaceObj || nativeHandle == 0) return -1;

  ANativeWindow* window = ANativeWindow_fromSurface(env, surfaceObj);
  if (!window) return -1;

  jint w = nativeImage_width(nativeHandle);
  jint h = nativeImage_height(nativeHandle);
  if (w <= 0 || h <= 0) { ANativeWindow_release(window); return -1; }

  ANativeWindow_setBuffersGeometry(
      window, w, h, AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM);

  ANativeWindow_Buffer buffer;
  if (ANativeWindow_lock(window, &buffer, nullptr) != 0) {
    ANativeWindow_release(window);
    return -1;
  }

  jint result = nativeImage_copyToWindowBuffer(nativeHandle, &buffer);

  ANativeWindow_unlockAndPost(window);
  ANativeWindow_release(window);
  return result;
}

// ── JNI: query image dimensions (used by Kotlin for buffer sizing) ──

JNIEXPORT jint JNICALL
Java_com_example_fautomatik_app_TextureBridge_nativeImageWidth(
    JNIEnv*, jobject, jlong handle) {
  return nativeImage_width(handle);
}

JNIEXPORT jint JNICALL
Java_com_example_fautomatik_app_TextureBridge_nativeImageHeight(
    JNIEnv*, jobject, jlong handle) {
  return nativeImage_height(handle);
}

} // extern "C"
