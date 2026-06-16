import 'dart:ffi';
import 'dart:io';

// ── Native function type defs ───────────────────────────────────────

typedef _NativeConfigureSlot = Bool Function(
    Int32, Int32, Int32, Int32,
    Float, Float, Float,
    Float, Float, Float,
    Bool);

typedef _DartConfigureSlot = bool Function(
    int, int, int, int,
    double, double, double,
    double, double, double,
    bool);

typedef _NativePrepareInput = Bool Function(Int64, Int32);
typedef _DartPrepareInput = bool Function(int, int);

typedef _NativeGetPointer = Pointer<Void> Function(Int32);
typedef _DartGetPointer = Pointer<Void> Function(int);

typedef _NativeFreeSlot = Void Function(Int32);
typedef _DartFreeSlot = void Function(int);

/// Manages pre-allocated native Float32 staging buffers for ONNX model input.
///
/// The staging buffers live in native C++ heap and are reused across
/// inference calls to avoid per-frame allocation.
///
/// ```dart
/// final staging = AIStagingManager();
///
/// // Configure a slot for U2Net (320x320, planar CHW, ImageNet norms):
/// staging.initModelSlot(
///   slotId: 0,
///   width: 320, height: 320, channels: 3,
///   mean: [0.485, 0.456, 0.406],
///   stdDev: [0.229, 0.224, 0.225],
///   isPlanarCHW: true,
/// );
///
/// // On each inference:
/// staging.populateSlotInput(nativeImgHandle, slotId: 0);
/// final ptr = staging.getInputPointer(slotId: 0);
/// // Pass ptr to OrtValue.fromList or OrtSession.run
///
/// // Cleanup:
/// staging.releaseSlot(0);
/// ```
final class AIStagingManager {
  late final DynamicLibrary _lib;
  late final _DartConfigureSlot _configureSlot;
  late final _DartPrepareInput _prepareInput;
  late final _DartGetPointer _getPointer;
  late final _DartFreeSlot _freeSlot;

  AIStagingManager() {
    _lib = Platform.isAndroid
        ? DynamicLibrary.open('libvulkan_compute_engine.so')
        : DynamicLibrary.process();

    _configureSlot =
        _lib.lookupFunction<_NativeConfigureSlot, _DartConfigureSlot>(
            'configureStagingSlot');
    _prepareInput =
        _lib.lookupFunction<_NativePrepareInput, _DartPrepareInput>(
            'prepareStageInput');
    _getPointer =
        _lib.lookupFunction<_NativeGetPointer, _DartGetPointer>(
            'getStagePointer');
    _freeSlot = _lib.lookupFunction<_NativeFreeSlot, _DartFreeSlot>(
        'freeStagingSlot');
  }

  /// Allocate (or reuse if dimensions match) a fixed Float32 staging buffer.
  bool initModelSlot({
    required int slotId,
    required int width,
    required int height,
    required int channels,
    required List<double> mean,
    required List<double> stdDev,
    required bool isPlanarCHW,
  }) {
    return _configureSlot(
      slotId, width, height, channels,
      mean[0], mean[1], mean[2],
      stdDev[0], stdDev[1], stdDev[2],
      isPlanarCHW,
    );
  }

  /// Downsample the [NativeImg] into the staging buffer and normalize.
  bool populateSlotInput(int nativeImageHandle, {int slotId = 0}) {
    return _prepareInput(nativeImageHandle, slotId);
  }

  /// Get the raw pointer to the staging buffer for ONNX runtime.
  Pointer<Void> getInputPointer({int slotId = 0}) {
    return _getPointer(slotId);
  }

  /// Free the staging buffer when the feature/screen closes.
  void releaseSlot(int slotId) {
    _freeSlot(slotId);
  }
}
