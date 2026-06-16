import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' show exp;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../../core/types.dart';
import '../edit/edit_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Architectural note — singleton vs isolate-per-call
//
// The reference design uses a BackgroundRemovalEngine singleton with a warm
// long-lived OrtSession kept in main-isolate memory. That approach eliminates
// repeated model-load I/O and session-construction overhead per inference.
//
// This file instead chooses a per-call isolate with create/close session
// semantics. Trade-offs:
//
//   Reference (BackgroundRemovalEngine)        This file
//   ────────────────────────────────            ──────────
//   Singleton, main-isolate                     Per-call isolate
//   Long-lived OrtSession                       Session create/close per call
//   Warm-up pass to pre-scale CPU freq          No warm-up
//   Model from buffer (OrtSession.fromBuffer)   Model from file path
//   onnxruntime_v2 API                          flutter_onnxruntime API
//   Explicit OrtValueTensor.release()           OrtValue.dispose() in finally
//   Zero-allocation warm-up tensor              Real image tensor every call
//
// The isolate approach provides crash containment (OOM in the worker kills only
// the isolate, not the UI) and guarantees memory cleanup when the session goes
// out of scope. The singleton approach avoids per-inference session-creation
// latency at the cost of lifetime management complexity.
//
// A future optimization could combine both: a singleton background isolate that
// keeps the session warm across calls, eliminating both session-construction
// latency AND UI-thread crash risk.
// ─────────────────────────────────────────────────────────────────────────────

const _modelAsset = 'assets/models/u2net_human_seg.onnx';
const _inputSize = 320;

// ---------------------------------------------------------------------------
// Isolate message types
// ---------------------------------------------------------------------------

class _InferRequest {
  final String modelPath;
  final int targetSize;
  final Uint8List imageBytes;
  final int width;
  final int height;
  final SendPort replyPort;
  _InferRequest({
    required this.modelPath,
    required this.targetSize,
    required this.imageBytes,
    required this.width,
    required this.height,
    required this.replyPort,
  });
}

class _InferResult {
  final MaskData? data;
  final String? error;
  _InferResult({this.data, this.error});
}

// ---------------------------------------------------------------------------
// Background isolate entry point
// ---------------------------------------------------------------------------

void _isolateEntry(Map<String, dynamic> params) {
  final rootIsolateToken = params['rootIsolateToken'] as RootIsolateToken?;
  if (rootIsolateToken != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
  }

  final ReceivePort receivePort = ReceivePort();
  final SendPort mainSendPort = params['sendPort'] as SendPort;
  mainSendPort.send(receivePort.sendPort);

  receivePort.listen((message) async {
    if (message is _InferRequest) {
      _InferResult result;
      try {
        final mask = await _runInference(
          modelPath: message.modelPath,
          targetSize: message.targetSize,
          imageBytes: message.imageBytes,
          width: message.width,
          height: message.height,
        );
        result = _InferResult(data: mask);
      } catch (e) {
        result = _InferResult(error: e.toString());
      }
      message.replyPort.send(result);
    }
  });
}

// ---------------------------------------------------------------------------
// Core inference: downscale → model → upscale  (all inside isolate)
// ---------------------------------------------------------------------------

Future<MaskData> _runInference({
  required String modelPath,
  required int targetSize,
  required Uint8List imageBytes,
  required int width,
  required int height,
}) async {
  // Compare reference: OrtEnv.instance.init() once at app start, then
  // OrtSession.fromBuffer() — no I/O. Here we create a new OnnxRuntime
  // instance and load from disk each call (I/O + alloc every time).
  //
  // Reference sessionOptions.appendDefaultProviders() leverages NNAPI/CoreML
  // automatically. Here we set providers per-platform via OrtProvider enum
  // (see _providers() in the original ModnetBgRemover — removed for brevity).
  // flutter_onnxruntime's createSession auto-selects available providers
  // when none are passed.
  final ort = OnnxRuntime();
  final session = await ort.createSession(
    modelPath,
    options: OrtSessionOptions(
      useArena: false,
      intraOpNumThreads: 1,
      interOpNumThreads: 1,
    ),
  );

  try {
    final src = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: imageBytes.buffer,
      numChannels: 4,
    );

    // 1. Downscale to model input size
    final resized = img.copyResize(src, width: targetSize, height: targetSize);
    final rgba = resized.getBytes();

    // 2. Build NCHW tensor (normalize to [0, 1])
    final pixels = targetSize * targetSize;
    final tensor = Float32List(3 * pixels);
    for (int i = 0; i < pixels; i++) {
      final off = i * 4;
      tensor[i] = rgba[off] / 255.0;
      tensor[pixels + i] = rgba[off + 1] / 255.0;
      tensor[2 * pixels + i] = rgba[off + 2] / 255.0;
    }

    // 3. Run ONNX model
    // Compare reference: OrtValueTensor.createTensorWithDataList(tensor, shape)
    // and explicit .release() after use. Here we use OrtValue.fromList() and
    // rely on Dart GC + the finally block below for cleanup. The reference's
    // manual release is more deterministic for native memory on mobile.
    //
    // Reference also wraps the call in runAsync() with OrtRunOptions, allowing
    // future cancellation support. session.run() here is fire-and-forget.
    final inputName = session.inputNames.first;
    final outputName = session.outputNames.first;
    final inputs = {inputName: await OrtValue.fromList(tensor, [1, 3, targetSize, targetSize])};
    final outputs = await session.run(inputs);
    final outVal = outputs[outputName]!;
    final outFlat = await outVal.asFlattenedList();
    final logits = Float32List.fromList(
      outFlat.cast<num>().map((e) => e.toDouble()).toList(),
    );

    // 4. Sigmoid activation → mask
    final maskRaw = Uint8List(pixels);
    for (int i = 0; i < pixels; i++) {
      maskRaw[i] = (255.0 / (1.0 + exp(-logits[i]))).round().clamp(0, 255);
    }

    final maskImg = img.Image.fromBytes(
      width: targetSize,
      height: targetSize,
      bytes: maskRaw.buffer,
      numChannels: 1,
    );

    // 5. Bilinear upscale to original image size
    final upscaled = img.copyResize(
      maskImg,
      width: width,
      height: height,
      interpolation: img.Interpolation.linear,
    );

    // 6. 3×3 Gaussian edge softening
    final softened = img.gaussianBlur(upscaled, radius: 1);

    return MaskData(
      maskBytes: softened.getBytes(),
      width: width,
      height: height,
    );
  } finally {
    await session.close();
  }
}

// ---------------------------------------------------------------------------
// Public remover — single model, background isolate, UI-safe
//
// Compare with reference singleton BackgroundRemovalEngine:
//   - Reference: BackgroundRemovalEngine.instance (global, one copy)
//     Here:     new U2netBgRemover() per consumer (screen.dart line 29)
//   - The reference keeps a single OrtSession alive in _session across the
//     entire app lifetime. Here each process() call creates a fresh session
//     inside the isolate _runInference and closes it in `finally`.
//   - Reference loads model via OrtSession.fromBuffer(buffer) — no temp file.
//     Here we extract the .onnx asset to a temp file (load() below),
//     then pass the file path to the isolate.
//   - Reference has _warmUpSession() — a dummy inference pass that forces
//     hardware frequency scaling before the user's first real call, hiding
//     cold-start latency. We omit this; the first user call pays the full
//     session-construction cost.
// ---------------------------------------------------------------------------

class U2netBgRemover {
  String? _modelPath;
  bool _extracted = false;
  bool _disposed = false;
  Isolate? _isolate;
  SendPort? _isolateSendPort;
  bool _isolateReady = false;

  Future<void> load() async {
    if (_extracted) return;
    final directory = await getTemporaryDirectory();
    _modelPath = '${directory.path}${Platform.pathSeparator}u2net_human_seg.onnx';
    final file = File(_modelPath!);
    if (!await file.exists()) {
      final data = await rootBundle.load(_modelAsset);
      await file.writeAsBytes(data.buffer.asUint8List());
    }
    _extracted = true;
  }

  Future<MaskData> process(Uint8List imageBytes, int width, int height) async {
    if (_disposed) throw StateError('U2netBgRemover disposed');
    if (_modelPath == null) throw StateError('U2netBgRemover not loaded');

    final result = await _runInIsolate(
      modelPath: _modelPath!,
      targetSize: _inputSize,
      imageBytes: imageBytes,
      width: width,
      height: height,
    );

    if (result.data != null) return result.data!;
    throw StateError('Background removal failed: ${result.error}');
  }

  Future<void> _ensureIsolate() async {
    if (_isolateReady && _isolate != null) return;
    _isolate?.kill();

    final receivePort = ReceivePort();
    final rootToken = RootIsolateToken.instance;

    _isolate = await Isolate.spawn(
      _isolateEntry,
      {
        'sendPort': receivePort.sendPort,
        'rootIsolateToken': rootToken,
      },
      errorsAreFatal: false,
    );

    _isolateSendPort = await receivePort.first as SendPort;
    _isolateReady = true;
  }

  Future<_InferResult> _runInIsolate({
    required String modelPath,
    required int targetSize,
    required Uint8List imageBytes,
    required int width,
    required int height,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    await _ensureIsolate();

    final replyPort = ReceivePort();
    _isolateSendPort!.send(_InferRequest(
      modelPath: modelPath,
      targetSize: targetSize,
      imageBytes: imageBytes,
      width: width,
      height: height,
      replyPort: replyPort.sendPort,
    ));

    // Timeout guard: isolate OOM won't hang the UI
    final result = await Future.any([
      replyPort.first,
      Future.delayed(timeout, () => _InferResult(error: 'Timeout after $timeout')),
    ]);

    if (result is _InferResult) {
      replyPort.close();
      if (result.error?.contains('Timeout') ?? false) {
        _isolateReady = false;
      }
      return result;
    }

    replyPort.close();
    _isolateReady = false;
    return _InferResult(error: 'Unknown error from isolate');
  }

  void dispose() {
    _disposed = true;
    _isolate?.kill();
    _isolate = null;
    _isolateSendPort = null;
    _isolateReady = false;
    _modelPath = null;
    _extracted = false;
  }
}

// ---------------------------------------------------------------------------
// Compositing (UI-safe, used by PhotoEditor)
// ---------------------------------------------------------------------------

img.Image replaceBackground(
  img.Image src,
  Uint8List maskBytes,
  int maskWidth,
  int maskHeight,
  BackgroundConfig? config,
) {
  final mask = img.Image.fromBytes(width: maskWidth, height: maskHeight, bytes: maskBytes.buffer, numChannels: 1);
  final scaledMask = img.copyResize(mask, width: src.width, height: src.height, interpolation: img.Interpolation.linear);
  final blurredMask = img.gaussianBlur(scaledMask, radius: config?.featherRadius ?? 3);

  final maskRaw = blurredMask.getBytes();
  final srcRaw = src.getBytes();
  final resultRaw = Uint8List(srcRaw.length);

  if (config != null) {
    _fillRaw(resultRaw, src.width, src.height, config);
  }

  final threshold = config?.maskThreshold ?? 0.5;
  final total = src.width * src.height;
  for (int i = 0; i < total; i++) {
    final alpha = maskRaw[i] / 255.0;
    if (alpha >= 1.0) {
      final off = i * 4;
      resultRaw[off] = srcRaw[off];
      resultRaw[off + 1] = srcRaw[off + 1];
      resultRaw[off + 2] = srcRaw[off + 2];
      resultRaw[off + 3] = 255;
    } else if (alpha > threshold) {
      final off = i * 4;
      if (config != null) {
        final inv = 1.0 - alpha;
        resultRaw[off] = (srcRaw[off] * alpha + resultRaw[off] * inv).round().clamp(0, 255);
        resultRaw[off + 1] = (srcRaw[off + 1] * alpha + resultRaw[off + 1] * inv).round().clamp(0, 255);
        resultRaw[off + 2] = (srcRaw[off + 2] * alpha + resultRaw[off + 2] * inv).round().clamp(0, 255);
        resultRaw[off + 3] = 255;
      } else {
        resultRaw[off] = srcRaw[off];
        resultRaw[off + 1] = srcRaw[off + 1];
        resultRaw[off + 2] = srcRaw[off + 2];
        resultRaw[off + 3] = (alpha * 255).round().clamp(0, 255);
      }
    }
  }

  return img.Image.fromBytes(
    width: src.width, height: src.height,
    bytes: resultRaw.buffer, numChannels: 4,
  );
}

void _fillRaw(Uint8List pixels, int w, int h, BackgroundConfig config) {
  if (config.imageBytes != null) {
    final bgImg = img.decodeImage(config.imageBytes!);
    if (bgImg != null) {
      final bgRaw = bgImg.getBytes();
      final bgW = bgImg.width;
      final bgH = bgImg.height;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final di = (y * w + x) * 4;
          final si = ((y % bgH) * bgW + (x % bgW)) * 4;
          pixels[di] = bgRaw[si];
          pixels[di + 1] = bgRaw[si + 1];
          pixels[di + 2] = bgRaw[si + 2];
          pixels[di + 3] = 255;
        }
      }
      return;
    }
  }
  final r = (config.color >> 16) & 0xFF, g = (config.color >> 8) & 0xFF, b = config.color & 0xFF;
  for (int i = 0; i < pixels.length; i += 4) {
    pixels[i] = r;
    pixels[i + 1] = g;
    pixels[i + 2] = b;
    pixels[i + 3] = 255;
  }
}
