import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:dartcv4/dartcv.dart' as cv4;
import 'vulkan_bridge.dart';

export 'ai_staging_bridge.dart';

// ── Re-export dartcv4 types & constants ─────────────────────────────

export 'package:dartcv4/dartcv.dart' show
  Mat,
  Size,
  Point,
  Point2f,
  Scalar,
  MatType,
  Rect,
  VecI32,
  VecU8,
  RotatedRect,
  Contour,
  Contours;

export 'package:dartcv4/dartcv.dart' show
  IMREAD_COLOR,
  IMREAD_GRAYSCALE,
  IMREAD_UNCHANGED,
  IMREAD_ANYDEPTH,
  IMREAD_ANYCOLOR;

export 'package:dartcv4/dartcv.dart' show
  COLOR_BGR2GRAY,
  COLOR_BGR2RGB,
  COLOR_BGR2BGRA,
  COLOR_BGR2HSV,
  COLOR_BGR2HLS,
  COLOR_BGR2Lab,
  COLOR_BGR2Luv,
  COLOR_BGR2YUV,
  COLOR_BGR2XYZ,
  COLOR_BGR2YCrCb,
  COLOR_RGB2GRAY,
  COLOR_RGB2BGR,
  COLOR_RGB2HSV,
  COLOR_RGB2HLS,
  COLOR_RGB2Lab,
  COLOR_RGB2Luv,
  COLOR_RGB2YUV,
  COLOR_RGB2XYZ,
  COLOR_RGB2YCrCb,
  COLOR_GRAY2BGR,
  COLOR_GRAY2BGRA,
  COLOR_GRAY2RGB,
  COLOR_GRAY2RGBA,
  COLOR_BGRA2GRAY,
  COLOR_BGRA2BGR,
  COLOR_BGRA2RGB,
  COLOR_RGBA2GRAY,
  COLOR_RGBA2BGR,
  COLOR_RGBA2RGB;

export 'package:dartcv4/dartcv.dart' show
  INTER_NEAREST,
  INTER_LINEAR,
  INTER_CUBIC,
  INTER_AREA,
  INTER_LANCZOS4,
  INTER_LINEAR_EXACT,
  INTER_NEAREST_EXACT;

export 'package:dartcv4/dartcv.dart' show
  IMWRITE_JPEG_QUALITY,
  IMWRITE_JPEG_PROGRESSIVE,
  IMWRITE_PNG_COMPRESSION,
  IMWRITE_WEBP_QUALITY;

export 'package:dartcv4/dartcv.dart' show
  BORDER_DEFAULT,
  BORDER_CONSTANT,
  BORDER_REPLICATE,
  BORDER_REFLECT,
  BORDER_WRAP,
  BORDER_REFLECT_101;

// ── NativeImage: zero-copy native handle ──────────────────────────

/// A reference to an image buffer allocated in native (C++) heap memory.
///
/// Unlike [cv4.Mat], which stores pixels in the Dart heap,
/// `NativeImg` keeps data in a single native allocation.
/// Get a zero-copy [Pointer] via [data] and pass it directly to
/// Vulkan compute shaders or Flutter's texture registry.
///
/// ```dart
/// final img = NativeImg.decode(bytes);
/// // In-place operation (no copy):
/// img.cvtColor(COLOR_BGR2GRAY);
/// // Zero-copy access for Vulkan:
/// final ptr = img.data;
/// ```
final class NativeImg {
  int _handle;
  bool _valid;

  NativeImg._(this._handle) : _valid = (_handle != 0);

  /// Load an image from decoded file bytes. Returns null on failure.
  static NativeImg? decode(Uint8List bytes) {
    final bridge = VulkanBridge.instance;
    if (bridge == null) return null;
    final handle = bridge.createFromBytes(bytes);
    return handle != 0 ? NativeImg._(handle) : null;
  }

  /// Load an image directly from file path.
  static NativeImg? fromFile(String path) {
    final bridge = VulkanBridge.instance;
    if (bridge == null) return null;
    final handle = bridge.createFromFile(path);
    return handle != 0 ? NativeImg._(handle) : null;
  }

  /// Create an empty RGBA image of given dimensions.
  static NativeImg? create(int w, int h) {
    final bridge = VulkanBridge.instance;
    if (bridge == null) return null;
    final handle = bridge.createEmpty(w, h);
    return handle != 0 ? NativeImg._(handle) : null;
  }

  /// Wrap raw RGBA pixels into native memory (copies once at init).
  static NativeImg? fromRgba(Uint8List pixels, int w, int h) {
    final bridge = VulkanBridge.instance;
    if (bridge == null) return null;
    final handle = bridge.createFromRgba(pixels, w, h);
    return handle != 0 ? NativeImg._(handle) : null;
  }

  int get handle => _handle;
  bool get isValid => _valid;

  int get width {
    final bridge = VulkanBridge.instance;
    return (bridge != null && _valid) ? bridge.getWidth(_handle) : 0;
  }

  int get height {
    final bridge = VulkanBridge.instance;
    return (bridge != null && _valid) ? bridge.getHeight(_handle) : 0;
  }

  int get channels {
    final bridge = VulkanBridge.instance;
    return (bridge != null && _valid) ? bridge.getChannels(_handle) : 0;
  }

  /// Native pointer to raw pixel data. Valid until [release] is called.
  Pointer<Uint8>? get data {
    final bridge = VulkanBridge.instance;
    return (bridge != null && _valid) ? bridge.getData(_handle) : null;
  }

  // ── In-place operations ───────────────────────────────────────────

  bool cvtColor(int code) {
    final bridge = VulkanBridge.instance;
    if (bridge == null || !_valid) return false;
    return bridge.cvtColor(_handle, code) == 0;
  }

  bool resize(int w, int h, {int interpolation = 1}) {
    final bridge = VulkanBridge.instance;
    if (bridge == null || !_valid) return false;
    return bridge.resize(_handle, w, h, interpolation: interpolation) == 0;
  }

  bool gaussianBlur(int kx, int ky, {double sigmaX = 0, double sigmaY = 0}) {
    final bridge = VulkanBridge.instance;
    if (bridge == null || !_valid) return false;
    return bridge.gaussianBlur(_handle, kx, ky, sigmaX: sigmaX, sigmaY: sigmaY) == 0;
  }

  bool sobel(int ddepth, int dx, int dy, {int ksize = 3}) {
    final bridge = VulkanBridge.instance;
    if (bridge == null || !_valid) return false;
    return bridge.sobel(_handle, ddepth, dx, dy, ksize: ksize) == 0;
  }

  // ── Copy to Dart memory (for display / ONNX) ──────────────────────

  /// Copy contents into a pre-allocated RGBA [Uint8List].
  /// [out] must be at least (width * height * 4) bytes.
  /// Returns bytes written, or -1 on failure.
  int copyToRgba(Pointer<Uint8> out) {
    final bridge = VulkanBridge.instance;
    if (bridge == null || !_valid) return -1;
    return bridge.copyToRgba(_handle, out);
  }

  /// Copy contents into a new [Uint8List] RGBA buffer.
  /// This causes a heap allocation — prefer [copyToRgba] with a reused buffer.
  Uint8List? toRgba() {
    final w = width, h = height;
    if (w <= 0 || h <= 0) return null;
    final size = w * h * 4;
    // Use calloc to allocate native buffer, copy, then return Dart list
    final ptr = calloc<Uint8>(size);
    final written = copyToRgba(ptr);
    if (written < 0) { calloc.free(ptr); return null; }
    final result = Uint8List(size);
    for (int i = 0; i < size; i++) { result[i] = ptr[i]; }
    calloc.free(ptr);
    return result;
  }

  // ── Convert to dartcv4 Mat (for legacy APIs) ──────────────────────

  cv4.Mat? toMat() {
    final rgba = toRgba();
    if (rgba == null) return null;
    final w = width, h = height;
    final vec = cv4.VecU8.fromList(rgba);
    return cv4.Mat.fromVec(vec, rows: h, cols: w,
        type: cv4.MatType.CV_8UC4, copyData: false);
  }

  void release() {
    if (!_valid) return;
    final bridge = VulkanBridge.instance;
    if (bridge != null) bridge.release(_handle);
    _valid = false;
    _handle = 0;
  }
}

// ── I/O functions (Two paths: zero-copy native vs dartcv4 CPU) ─────

/// Decode image bytes. Returns a dartcv4 [Mat] for backward compatibility.
/// Internally decodes into native memory first, then wraps in Mat.
cv4.Mat imdecode(Uint8List buf, int flags, {cv4.Mat? dst}) {
  // Try native path first (zero-copy decode into native heap)
  final native = NativeImg.decode(buf);
  if (native != null) {
    final mat = native.toMat();
    native.release();
    if (mat != null) return mat;
  }
  // Fall back to dartcv4
  return cv4.imdecode(buf, flags, dst: dst);
}

(bool, Uint8List) imencode(String ext, cv4.InputArray img, {cv4.VecI32? params}) =>
    cv4.imencode(ext, img, params: params);

cv4.Mat imread(String filename, {int flags = cv4.IMREAD_COLOR}) =>
    cv4.imread(filename, flags: flags);

// ── GPU / Vulkan singleton ──────────────────────────────────────────

enum GpuStatus {
  success,
  notAvailable,
  notInitialized,
  invalidParams,
  processingError,
}

final class Gpu {
  VulkanBridge? _bridge;
  bool _ready = false;

  bool get isReady => _ready;
  String? get deviceInfo => _bridge?.getDeviceInfo();

  Future<bool> init() async {
    if (_ready) return true;
    return Future(() {
      final bridge = VulkanBridge.load();
      if (bridge == null) return false;
      if (bridge.init() != 0) { bridge.dispose(); return false; }
      _bridge = bridge;
      _ready = true;
      return true;
    });
  }

  void dispose() {
    _bridge?.dispose();
    _bridge = null;
    _ready = false;
  }

  GpuStatus grayscale(Uint8List input, Uint8List output, int w, int h) {
    if (!_ready) return GpuStatus.notAvailable;
    if (input.length < w * h * 4 || output.length < w * h * 4) {
      return GpuStatus.invalidParams;
    }
    final result = _bridge!.processGrayscale(input, w, h);
    if (result == null) return GpuStatus.processingError;
    output.setRange(0, result.length, result);
    return GpuStatus.success;
  }

  GpuStatus adjustBrightnessContrast(
    Uint8List input, Uint8List output, int w, int h, {
    double brightness = 0,
    double contrast = 0,
  }) {
    if (!_ready) return GpuStatus.notAvailable;
    final result = _bridge!.processBrightnessContrast(
      input, w, h, brightness: brightness, contrast: contrast);
    if (result == null) return GpuStatus.processingError;
    output.setRange(0, result.length, result);
    return GpuStatus.success;
  }

  GpuStatus composite(
    Uint8List src, Uint8List mask, Uint8List output, int w, int h, {
    int? bgColor,
    double maskThreshold = 0.5,
    double featherRadius = 3,
  }) {
    if (!_ready) return GpuStatus.notAvailable;
    final result = _bridge!.processComposite(
      src, mask, w, h,
      bgColor: bgColor ?? 0x000000,
      maskThreshold: maskThreshold,
      featherRadius: featherRadius);
    if (result == null) return GpuStatus.processingError;
    output.setRange(0, result.length, result);
    return GpuStatus.success;
  }

  GpuStatus removeBackground(
    Uint8List src, Uint8List mask, Uint8List output, int w, int h, {
    double maskThreshold = 0.5,
    double featherRadius = 3,
  }) {
    return composite(src, mask, output, w, h,
      bgColor: null,
      maskThreshold: maskThreshold,
      featherRadius: featherRadius);
  }
}

final Gpu gpu = Gpu();

// ── GPU-accelerated OpenCV wrappers (Mat-based, backward compat) ────

Uint8List _matToRgba(cv4.Mat src) {
  final w = src.cols, h = src.rows, total = w * h;
  final data = src.data;
  if (src.channels == 4) {
    final out = Uint8List(total * 4);
    for (int i = 0; i < total; i++) { final s = i * 4;
      out[s] = data[s + 2]; out[s + 1] = data[s + 1];
      out[s + 2] = data[s]; out[s + 3] = data[s + 3]; }
    return out;
  }
  if (src.channels == 3) {
    final out = Uint8List(total * 4);
    for (int i = 0; i < total; i++) { final s = i * 3, d = i * 4;
      out[d] = data[s + 2]; out[d + 1] = data[s + 1];
      out[d + 2] = data[s]; out[d + 3] = 255; }
    return out;
  }
  if (src.channels == 1) {
    final out = Uint8List(total * 4);
    for (int i = 0; i < total; i++) { final d = i * 4;
      out[d] = data[i]; out[d + 1] = data[i];
      out[d + 2] = data[i]; out[d + 3] = 255; }
    return out;
  }
  throw ArgumentError('Unsupported channels: ${src.channels}');
}

/// Color conversion. Tries GPU path first (for BGR→GRAY),
/// then native OpenCV (opencv-mobile) via NativeImg,
/// then falls back to dartcv4.
cv4.Mat cvtColor(cv4.Mat src, int code, {cv4.Mat? dst}) {
  // 1. Try GPU Vulkan path for grayscale
  if (gpu._ready) {
    final isGray = code == cv4.COLOR_BGR2GRAY || code == cv4.COLOR_BGRA2GRAY ||
        code == cv4.COLOR_RGB2GRAY || code == cv4.COLOR_RGBA2GRAY;
    if (isGray) {
      final w = src.cols, h = src.rows;
      if (w > 0 && h > 0) {
        final rgba = _matToRgba(src);
        final out = Uint8List(w * h * 4);
        if (gpu.grayscale(rgba, out, w, h) == GpuStatus.success) {
          final gray = Uint8List(w * h);
          for (int i = 0; i < w * h; i++) { gray[i] = out[i * 4]; }
          final vec = cv4.VecU8.fromList(gray);
          return cv4.Mat.fromVec(vec, rows: h, cols: w,
              type: cv4.MatType.CV_8UC1, copyData: false);
        }
      }
    }
  }

  // 2. Try native OpenCV (opencv-mobile) via NativeImg
  try {
    final rgba = _matToRgba(src);
    final native = NativeImg.fromRgba(rgba, src.cols, src.rows);
    if (native != null) {
      if (native.cvtColor(code)) {
        // Convert back to Mat — use toRgba for display-ready, or direct channel
        if (code == cv4.COLOR_BGR2GRAY || code == cv4.COLOR_BGRA2GRAY ||
            code == cv4.COLOR_RGB2GRAY || code == cv4.COLOR_RGBA2GRAY) {
          // Result is GRAY8 — copy directly
          final h = native.height, w = native.width;
          final ptr = native.data!;
          final gray = Uint8List(w * h);
          for (int i = 0; i < w * h; i++) { gray[i] = ptr[i]; }
          final vec = cv4.VecU8.fromList(gray);
          native.release();
          return cv4.Mat.fromVec(vec, rows: h, cols: w,
              type: cv4.MatType.CV_8UC1, copyData: false);
        }
        // For other conversions, get RGBA result
        final result = native.toMat();
        native.release();
        if (result != null) return result;
      } else {
        native.release();
      }
    }
  } catch (_) {}

  // 3. Fall back to dartcv4 CPU
  return cv4.cvtColor(src, code, dst: dst);
}

cv4.Mat toGrayscale(cv4.Mat src) => cvtColor(src, cv4.COLOR_BGR2GRAY);

cv4.Mat gaussianBlur(
  cv4.Mat src,
  (int, int) ksize,
  double sigmaX, {
  cv4.Mat? dst,
  double sigmaY = 0,
  int borderType = cv4.BORDER_DEFAULT,
}) {
  // Try native OpenCV via NativeImg
  try {
    final rgba = _matToRgba(src);
    final native = NativeImg.fromRgba(rgba, src.cols, src.rows);
    if (native != null) {
      final (kx, ky) = ksize;
      if (native.gaussianBlur(kx, ky, sigmaX: sigmaX, sigmaY: sigmaY)) {
        final result = native.toMat();
        native.release();
        if (result != null) return result;
      } else {
        native.release();
      }
    }
  } catch (_) {}
  return cv4.gaussianBlur(src, ksize, sigmaX,
      dst: dst, sigmaY: sigmaY, borderType: borderType);
}

cv4.Mat sobel(
  cv4.Mat src,
  int ddepth,
  int dx,
  int dy, {
  cv4.Mat? dst,
  int ksize = 3,
  double scale = 1,
  double delta = 0,
  int borderType = cv4.BORDER_DEFAULT,
}) {
  try {
    final rgba = _matToRgba(src);
    final native = NativeImg.fromRgba(rgba, src.cols, src.rows);
    if (native != null) {
      if (native.sobel(ddepth, dx, dy, ksize: ksize)) {
        final result = native.toMat();
        native.release();
        if (result != null) return result;
      } else {
        native.release();
      }
    }
  } catch (_) {}
  return cv4.sobel(src, ddepth, dx, dy,
      dst: dst, ksize: ksize, scale: scale, delta: delta,
      borderType: borderType);
}

cv4.Mat resize(
  cv4.InputArray src,
  (int, int) dsize, {
  cv4.OutputArray? dst,
  double fx = 0,
  double fy = 0,
  int interpolation = cv4.INTER_LINEAR,
}) {
  try {
    final mat = src; // InputArray is typedef for Mat
    final rgba = _matToRgba(mat);
    final native = NativeImg.fromRgba(rgba, mat.cols, mat.rows);
    if (native != null) {
      final (w, h) = dsize;
      final interpMap = {cv4.INTER_NEAREST: 0, cv4.INTER_LINEAR: 1,
                          cv4.INTER_CUBIC: 2, cv4.INTER_AREA: 3};
      final ni = interpMap[interpolation] ?? 1;
      if (native.resize(w, h, interpolation: ni)) {
        final result = native.toMat();
        native.release();
        if (result != null) return result;
      } else {
        native.release();
      }
    }
  } catch (_) {}
  return cv4.resize(src, dsize,
      dst: dst, fx: fx, fy: fy, interpolation: interpolation);
}
