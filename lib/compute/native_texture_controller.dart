import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'vulkan_bridge.dart';

/// Manages a Flutter [Texture] widget backed by native image memory.
///
/// The image pixels live in a C++ [NativeImg] (opencv-mobile cv::Mat)
/// and are piped directly into an Android [SurfaceTexture] via JNI,
/// bypassing the Dart heap entirely.
///
/// ```dart
/// final ctrl = NativeTextureController(nativeImgHandle: img.handle);
/// await ctrl.initialize();
/// // ... in build:
/// ctrl.view  // → Texture(textureId: ...)
/// // after in-place edits:
/// await ctrl.updateDisplay();
/// ctrl.dispose();
/// ```
final class NativeTextureController {
  static const _channel = MethodChannel('com.example.fautomatik_app/texture');

  final int nativeImgHandle;
  int? _textureId;
  bool _initialized = false;

  NativeTextureController({required this.nativeImgHandle});

  int? get textureId => _textureId;
  bool get isInitialized => _initialized;

  /// Register a native SurfaceTexture and return its ID.
  Future<void> initialize() async {
    if (_initialized) return;
    final id = await _channel.invokeMethod<int>('createTexture');
    if (id == null) throw Exception('Failed to create texture');
    _textureId = id;
    _initialized = true;
  }

  /// Push the current native image pixels to the display surface.
  ///
  /// Call this after any in-place modification to the NativeImg
  /// (cvtColor, resize, gaussianBlur, etc.) to reflect the change.
  /// Width and height are obtained via FFI — no Dart heap copy.
  Future<void> updateDisplay() async {
    if (!_initialized) throw Exception('Not initialized');

    final bridge = VulkanBridge.instance;
    if (bridge == null) throw Exception('VulkanBridge not loaded');

    final w = bridge.getWidth(nativeImgHandle);
    final h = bridge.getHeight(nativeImgHandle);
    if (w <= 0 || h <= 0) throw Exception('Invalid image dimensions');

    await _channel.invokeMethod('updateTexture', {
      'textureId': _textureId,
      'nativeHandle': nativeImgHandle,
      'width': w,
      'height': h,
    });
  }

  /// Release the native surface texture entry.
  void dispose() {
    if (_textureId != null) {
      _channel.invokeMethod('disposeTexture', {'textureId': _textureId});
      _textureId = null;
    }
    _initialized = false;
  }

  /// Returns a [Texture] widget bound to this controller.
  /// Must only be called after [initialize] succeeds.
  Widget get view {
    final id = _textureId;
    if (id == null) throw Exception('Not initialized. Call initialize() first.');
    return Texture(textureId: id);
  }
}
