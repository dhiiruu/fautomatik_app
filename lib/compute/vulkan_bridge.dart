import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

// ── Native type aliases (public — used by VulkanBridge fields) ──────

typedef VkCreateC = Pointer<Void> Function();
typedef VkCreateD = Pointer<Void> Function();

typedef VkDestroyC = Void Function(Pointer<Void>);
typedef VkDestroyD = void Function(Pointer<Void>);

typedef VkInitC = Int32 Function(Pointer<Void>);
typedef VkInitD = int Function(Pointer<Void>);

typedef VkDeviceInfoC = Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32);
typedef VkDeviceInfoD = int Function(Pointer<Void>, Pointer<Uint8>, int);

typedef VkProcessC = Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Int32, Int32);
typedef VkProcessD = int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, int, int);

typedef VkBCC = Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Int32, Int32, Float, Float);
typedef VkBCD = int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, int, int, double, double);

typedef VkCompositeC = Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, Int32, Int32, Uint32, Float, Float);
typedef VkCompositeD = int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, int, int, int, double, double);

typedef NiCreateBytesC = Int64 Function(Pointer<Uint8>, Int32);
typedef NiCreateBytesD = int Function(Pointer<Uint8>, int);

typedef NiCreateEmptyC = Int64 Function(Int32, Int32);
typedef NiCreateEmptyD = int Function(int, int);

typedef NiCreateFileC = Int64 Function(Pointer<Utf8>);
typedef NiCreateFileD = int Function(Pointer<Utf8>);

typedef NiCreateRgbaC = Int64 Function(Pointer<Uint8>, Int32, Int32);
typedef NiCreateRgbaD = int Function(Pointer<Uint8>, int, int);

typedef NiReleaseC = Void Function(Int64);
typedef NiReleaseD = void Function(int);

typedef NiGetIntC = Int32 Function(Int64);
typedef NiGetIntD = int Function(int);

typedef NiTotalBytesC = Int32 Function(Int64);
typedef NiTotalBytesD = int Function(int);

typedef NiGetDataC = Pointer<Uint8> Function(Int64);
typedef NiGetDataD = Pointer<Uint8> Function(int);

typedef NiOpC = Int32 Function(Int64, Int32);
typedef NiOpD = int Function(int, int);

typedef NiResizeC = Int32 Function(Int64, Int32, Int32, Int32);
typedef NiResizeD = int Function(int, int, int, int);

typedef NiBlurC = Int32 Function(Int64, Int32, Int32, Double, Double);
typedef NiBlurD = int Function(int, int, int, double, double);

typedef NiSobelC = Int32 Function(Int64, Int32, Int32, Int32, Int32);
typedef NiSobelD = int Function(int, int, int, int, int);

typedef NiCopyRgbaC = Int32 Function(Int64, Pointer<Uint8>);
typedef NiCopyRgbaD = int Function(int, Pointer<Uint8>);

/// Low-level FFI bindings to the native Vulkan compute engine + OpenCV layer.
///
/// Manages engine lifecycle and provides thin wrappers for all native functions.
/// Most callers should use [Gpu] or [NativeImg] instead of calling these directly.
final class VulkanBridge {
  static VulkanBridge? _instance;
  late final DynamicLibrary _lib;

  // Vulkan engine function pointers
  late final VkCreateD vkCreate;
  late final VkDestroyD vkDestroy;
  late final VkInitD vkInit;
  late final VkDeviceInfoD vkGetDeviceInfo;
  late final VkProcessD grayscale;
  late final VkBCD brightnessContrast;
  late final VkCompositeD composite;

  // NativeImage function pointers
  late final NiCreateBytesD niCreateFromBytes;
  late final NiCreateEmptyD niCreateEmpty;
  late final NiCreateFileD niCreateFromFile;
  late final NiCreateRgbaD niCreateFromRgba;
  late final NiReleaseD niRelease;
  late final NiGetIntD niWidth;
  late final NiGetIntD niHeight;
  late final NiGetIntD niChannels;
  late final NiTotalBytesD niTotalBytes;
  late final NiGetDataD niData;
  late final NiOpD niCvtColor;
  late final NiResizeD niResize;
  late final NiBlurD niGaussianBlur;
  late final NiSobelD niSobel;
  late final NiCopyRgbaD niCopyToRgba;

  VulkanBridge._(this._lib) {
    vkCreate = _lib.lookupFunction<VkCreateC, VkCreateD>('vkEngine_create');
    vkDestroy = _lib.lookupFunction<VkDestroyC, VkDestroyD>('vkEngine_destroy');
    vkInit = _lib.lookupFunction<VkInitC, VkInitD>('vkEngine_init');
    vkGetDeviceInfo = _lib.lookupFunction<VkDeviceInfoC, VkDeviceInfoD>('vkEngine_getDeviceInfo');
    grayscale = _lib.lookupFunction<VkProcessC, VkProcessD>('vkEngine_processGrayscale');
    brightnessContrast = _lib.lookupFunction<VkBCC, VkBCD>('vkEngine_processBrightnessContrast');
    composite = _lib.lookupFunction<VkCompositeC, VkCompositeD>('vkEngine_processComposite');

    niCreateFromBytes = _lib.lookupFunction<NiCreateBytesC, NiCreateBytesD>('nativeImage_createFromBytes');
    niCreateEmpty = _lib.lookupFunction<NiCreateEmptyC, NiCreateEmptyD>('nativeImage_createEmpty');
    niCreateFromFile = _lib.lookupFunction<NiCreateFileC, NiCreateFileD>('nativeImage_createFromFile');
    niCreateFromRgba = _lib.lookupFunction<NiCreateRgbaC, NiCreateRgbaD>('nativeImage_fromRgba');
    niRelease = _lib.lookupFunction<NiReleaseC, NiReleaseD>('nativeImage_release');
    niWidth = _lib.lookupFunction<NiGetIntC, NiGetIntD>('nativeImage_width');
    niHeight = _lib.lookupFunction<NiGetIntC, NiGetIntD>('nativeImage_height');
    niChannels = _lib.lookupFunction<NiGetIntC, NiGetIntD>('nativeImage_channels');
    niTotalBytes = _lib.lookupFunction<NiTotalBytesC, NiTotalBytesD>('nativeImage_totalBytes');
    niData = _lib.lookupFunction<NiGetDataC, NiGetDataD>('nativeImage_data');
    niCvtColor = _lib.lookupFunction<NiOpC, NiOpD>('nativeImage_cvtColor');
    niResize = _lib.lookupFunction<NiResizeC, NiResizeD>('nativeImage_resize');
    niGaussianBlur = _lib.lookupFunction<NiBlurC, NiBlurD>('nativeImage_gaussianBlur');
    niSobel = _lib.lookupFunction<NiSobelC, NiSobelD>('nativeImage_sobel');
    niCopyToRgba = _lib.lookupFunction<NiCopyRgbaC, NiCopyRgbaD>('nativeImage_copyToRgba');
  }

  static VulkanBridge? get instance => _instance;

  static VulkanBridge? load() {
    if (_instance != null) return _instance;
    try {
      final lib = Platform.isAndroid
          ? DynamicLibrary.open('libvulkan_compute_engine.so')
          : DynamicLibrary.process();
      _instance = VulkanBridge._(lib);
      return _instance;
    } catch (_) {
      return null;
    }
  }

  Pointer<Void> _ctx = nullptr;
  bool _initialized = false;
  bool get isInitialized => _initialized;

  int init() {
    _ctx = vkCreate();
    if (_ctx == nullptr) return -1;
    final result = vkInit(_ctx);
    _initialized = (result == 0);
    return result;
  }

  void dispose() {
    if (_ctx != nullptr) {
      vkDestroy(_ctx);
      _ctx = nullptr;
      _initialized = false;
    }
  }

  String? getDeviceInfo() {
    if (!_initialized) return null;
    final buf = calloc<Uint8>(256);
    final result = vkGetDeviceInfo(_ctx, buf, 256);
    if (result != 0) { calloc.free(buf); return null; }
    final info = buf.cast<Utf8>().toDartString();
    calloc.free(buf);
    return info;
  }

  // ── Native memory helpers ─────────────────────────────────────────

  Pointer<Uint8> _toNative(Uint8List data) {
    final ptr = calloc<Uint8>(data.length);
    for (int i = 0; i < data.length; i++) { ptr[i] = data[i]; }
    return ptr;
  }

  Uint8List _fromNative(Pointer<Uint8> ptr, int length) {
    final result = Uint8List(length);
    for (int i = 0; i < length; i++) { result[i] = ptr[i]; }
    return result;
  }

  // ── Vulkan operations ─────────────────────────────────────────────

  /// Convert RGBA8 to grayscale. Returns null on failure.
  Uint8List? processGrayscale(Uint8List input, int w, int h) {
    if (!_initialized || input.length < w * h * 4) return null;
    final size = w * h * 4;
    final inPtr = _toNative(input);
    final outPtr = calloc<Uint8>(size);
    final result = grayscale(_ctx, inPtr, outPtr, w, h);
    final output = result == 0 ? _fromNative(outPtr, size) : null;
    calloc.free(inPtr); calloc.free(outPtr);
    return output;
  }

  Uint8List? processBrightnessContrast(Uint8List input, int w, int h,
                                        {double brightness = 0, double contrast = 0}) {
    if (!_initialized || input.length < w * h * 4) return null;
    final size = w * h * 4;
    final inPtr = _toNative(input);
    final outPtr = calloc<Uint8>(size);
    final result = brightnessContrast(_ctx, inPtr, outPtr, w, h, brightness, contrast);
    final output = result == 0 ? _fromNative(outPtr, size) : null;
    calloc.free(inPtr); calloc.free(outPtr);
    return output;
  }

  Uint8List? processComposite(Uint8List src, Uint8List mask, int w, int h,
                               {int bgColor = 0x000000, double maskThreshold = 0.5,
                                double featherRadius = 3}) {
    if (!_initialized || src.length < w * h * 4 || mask.length < w * h) return null;
    final size = w * h * 4;
    final srcPtr = _toNative(src);
    final maskPtr = _toNative(mask);
    final outPtr = calloc<Uint8>(size);
    final result = composite(_ctx, srcPtr, maskPtr, outPtr, w, h,
                              bgColor, maskThreshold, featherRadius);
    final output = result == 0 ? _fromNative(outPtr, size) : null;
    calloc.free(srcPtr); calloc.free(maskPtr); calloc.free(outPtr);
    return output;
  }

  // ── NativeImage operations ───────────────────────────────────────

  int createFromBytes(Uint8List data) {
    final ptr = _toNative(data);
    final handle = niCreateFromBytes(ptr, data.length);
    calloc.free(ptr);
    return handle;
  }

  int createFromFile(String path) {
    final ptr = path.toNativeUtf8();
    final handle = niCreateFromFile(ptr);
    calloc.free(ptr);
    return handle;
  }

  int createFromRgba(Uint8List pixels, int w, int h) {
    final ptr = _toNative(pixels);
    final handle = niCreateFromRgba(ptr, w, h);
    calloc.free(ptr);
    return handle;
  }

  int createEmpty(int w, int h) => niCreateEmpty(w, h);
  void release(int handle) => niRelease(handle);
  int getWidth(int handle) => niWidth(handle);
  int getHeight(int handle) => niHeight(handle);
  int getChannels(int handle) => niChannels(handle);
  int getTotalBytes(int handle) => niTotalBytes(handle);
  Pointer<Uint8> getData(int handle) => niData(handle);

  int cvtColor(int handle, int code) => niCvtColor(handle, code);
  int resize(int handle, int w, int h, {int interpolation = 1}) =>
      niResize(handle, w, h, interpolation);
  int gaussianBlur(int handle, int kx, int ky,
                   {double sigmaX = 0, double sigmaY = 0}) =>
      niGaussianBlur(handle, kx, ky, sigmaX, sigmaY);
  int sobel(int handle, int ddepth, int dx, int dy, {int ksize = 3}) =>
      niSobel(handle, ddepth, dx, dy, ksize);
  int copyToRgba(int handle, Pointer<Uint8> outBuffer) =>
      niCopyToRgba(handle, outBuffer);
}
