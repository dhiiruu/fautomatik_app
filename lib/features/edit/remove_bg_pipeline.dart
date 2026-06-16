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
import 'bg_remover.dart';

// ---------------------------------------------------------------------------
// Model config
// ---------------------------------------------------------------------------

class _ModelConfig {
  final String assetPath;
  final int inputSize;
  const _ModelConfig({required this.assetPath, required this.inputSize});
}

const Map<BackgroundModel, _ModelConfig> _modelConfigs = {
  BackgroundModel.u2netp: _ModelConfig(
    assetPath: 'assets/models/u2netp.onnx',
    inputSize: 320,
  ),
  BackgroundModel.modnet: _ModelConfig(
    assetPath: 'assets/models/modnet.onnx',
    inputSize: 512,
  ),

};

// ---------------------------------------------------------------------------
// Core inference — runs inside the background isolate
// ---------------------------------------------------------------------------

class _OnnxSessionRunner {
  static Future<MaskData> infer({
    required String modelPath,
    required int targetSize,
    required Uint8List imageBytes,
    required int width,
    required int height,
  }) async {
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
      final inputName = session.inputNames.first;
      final outputName = session.outputNames.first;

      final src = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: imageBytes.buffer,
        numChannels: 4,
      );

      final resized = img.copyResize(src, width: targetSize, height: targetSize);

      final pixels = targetSize * targetSize;
      final tensor = Float32List(3 * pixels);
      for (int y = 0; y < targetSize; y++) {
        for (int x = 0; x < targetSize; x++) {
          final c = resized.getPixel(x, y);
          final i = y * targetSize + x;
          tensor[i] = c.r / 255.0;
          tensor[pixels + i] = c.g / 255.0;
          tensor[2 * pixels + i] = c.b / 255.0;
        }
      }

      final inputs = {inputName: await OrtValue.fromList(tensor, [1, 3, targetSize, targetSize])};
      final outputs = await session.run(inputs);
      final outVal = outputs[outputName]!;
      final outFlat = await outVal.asFlattenedList();

      final logits = Float32List.fromList(
        outFlat.cast<num>().map((e) => e.toDouble()).toList(),
      );

      final maskOut = Uint8List(pixels);
      for (int i = 0; i < pixels; i++) {
        maskOut[i] = (255.0 / (1.0 + exp(-logits[i]))).round().clamp(0, 255);
      }

      if (width == targetSize && height == targetSize) {
        return MaskData(maskBytes: maskOut, width: targetSize, height: targetSize);
      }

      return MaskData(
        maskBytes: _resizeMask(maskOut, targetSize, targetSize, width, height),
        width: width,
        height: height,
      );
    } finally {
      await session.close();
    }
  }

  static Uint8List _resizeMask(
    Uint8List src, int srcW, int srcH, int dstW, int dstH,
  ) {
    final dst = Uint8List(dstW * dstH);
    final xRatio = srcW / dstW;
    final yRatio = srcH / dstH;
    for (int dy = 0; dy < dstH; dy++) {
      final sy = (dy * yRatio).floor().clamp(0, srcH - 1);
      for (int dx = 0; dx < dstW; dx++) {
        dst[dy * dstW + dx] = src[sy * srcW + (dx * xRatio).floor().clamp(0, srcW - 1)];
      }
    }
    return dst;
  }
}

// ---------------------------------------------------------------------------
// Message types for isolate communication
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
// Top-level entry point for the background isolate
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
        final mask = await _OnnxSessionRunner.infer(
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
// OnnxBgRemover — session lifecycle: load-once (temp file), infer-close each call
// ---------------------------------------------------------------------------

class OnnxBgRemover implements BackgroundRemover {
  final BackgroundModel _model;
  int get _targetSize => _modelConfigs[_model]!.inputSize;

  String? _modelPath;
  bool _extracted = false;

  OnnxBgRemover({BackgroundModel model = BackgroundModel.modnet})
    : _model = model;

  @override
  Future<void> load() async {
    if (_extracted) return;
    final config = _modelConfigs[_model]!;
    final directory = await getTemporaryDirectory();
    final fileName = config.assetPath.split('/').last;
    _modelPath = '${directory.path}${Platform.pathSeparator}$fileName';
    final file = File(_modelPath!);
    if (!await file.exists()) {
      final data = await rootBundle.load(config.assetPath);
      await file.writeAsBytes(data.buffer.asUint8List());
    }
    _extracted = true;
  }

  @override
  Future<MaskData> process(Uint8List imageBytes, int width, int height) async {
    if (_modelPath == null) throw StateError('OnnxBgRemover not loaded');

    return _OnnxSessionRunner.infer(
      modelPath: _modelPath!,
      targetSize: _targetSize,
      imageBytes: imageBytes,
      width: width,
      height: height,
    );
  }

  @override
  void dispose() {
    _modelPath = null;
    _extracted = false;
  }
}

// ---------------------------------------------------------------------------
// IsolateBgRemover — runs inference in a background isolate for crash
// isolation and guaranteed memory cleanup.
// ---------------------------------------------------------------------------

class IsolateBgRemover implements BackgroundRemover {
  final BackgroundModel _model;
  final BackgroundModel _fallbackModel;

  int get _targetSize => _modelConfigs[_model]!.inputSize;
  int get _fallbackTargetSize => _modelConfigs[_fallbackModel]!.inputSize;

  String? _modelPath;
  String? _fallbackModelPath;
  bool _extracted = false;
  Isolate? _isolate;
  SendPort? _isolateSendPort;
  bool _isolateReady = false;
  bool _disposed = false;
  bool _useFallback = false;

  IsolateBgRemover({
    BackgroundModel model = BackgroundModel.modnet,
    BackgroundModel fallbackModel = BackgroundModel.u2netp,
  })  : _model = model,
        _fallbackModel = fallbackModel;

  @override
  Future<void> load() async {
    if (_extracted) return;
    await _extractModel(_model, (p) => _modelPath = p);
    await _extractModel(_fallbackModel, (p) => _fallbackModelPath = p);
    _extracted = true;
  }

  Future<void> _extractModel(BackgroundModel m, void Function(String) setPath) async {
    final config = _modelConfigs[m]!;
    final directory = await getTemporaryDirectory();
    final fileName = config.assetPath.split('/').last;
    final path = '${directory.path}${Platform.pathSeparator}$fileName';
    final file = File(path);
    if (!await file.exists()) {
      final data = await rootBundle.load(config.assetPath);
      await file.writeAsBytes(data.buffer.asUint8List());
    }
    setPath(path);
  }

  @override
  Future<MaskData> process(Uint8List imageBytes, int width, int height) async {
    if (_disposed) throw StateError('IsolateBgRemover disposed');
    if (_modelPath == null || _fallbackModelPath == null) {
      throw StateError('IsolateBgRemover not loaded');
    }

    await _ensureIsolate();

    // If primary already failed before, skip directly to fallback
    if (_useFallback) {
      return _runFallback(imageBytes, width, height);
    }

    // Try primary model first, fall back on failure
    final result = await _runInIsolate(
      modelPath: _modelPath!,
      targetSize: _targetSize,
      imageBytes: imageBytes,
      width: width,
      height: height,
    );

    if (result.data != null) return result.data!;

    // Primary model failed — switch to fallback for all subsequent calls
    _useFallback = true;
    return _runFallback(imageBytes, width, height);
  }

  Future<MaskData> _runFallback(Uint8List imageBytes, int width, int height) async {
    final fallbackResult = await _runInIsolate(
      modelPath: _fallbackModelPath!,
      targetSize: _fallbackTargetSize,
      imageBytes: imageBytes,
      width: width,
      height: height,
    );

    if (fallbackResult.data != null) return fallbackResult.data!;
    throw StateError(
      'Background removal failed (fallback error: ${fallbackResult.error})',
    );
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
    final replyPort = ReceivePort();

    _isolateSendPort!.send(_InferRequest(
      modelPath: modelPath,
      targetSize: targetSize,
      imageBytes: imageBytes,
      width: width,
      height: height,
      replyPort: replyPort.sendPort,
    ));

    // Timeout guard: if isolate dies silently (OOM), don't hang forever
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

  @override
  void dispose() {
    _disposed = true;
    _isolate?.kill();
    _isolate = null;
    _isolateSendPort = null;
    _isolateReady = false;
    _modelPath = null;
    _fallbackModelPath = null;
    _extracted = false;
  }
}
