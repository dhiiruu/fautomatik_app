import 'dart:async';
import 'dart:ui' show Rect, Offset;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../../core/types.dart';

enum CameraLens { front, back }

class ProcessedFrame {
  final Uint8List rgbaBytes;
  final int width;
  final int height;
  final FaceData? face;
  final bool isMirrored;

  ProcessedFrame({
    required this.rgbaBytes,
    required this.width,
    required this.height,
    this.face,
    this.isMirrored = false,
  });
}

class CaptureResult {
  final String filePath;
  final FaceData? faceData;

  CaptureResult({required this.filePath, this.faceData});
}

class CameraEngine {
  CameraController? _controller;
  CameraLens _lens = CameraLens.front;
  StreamController<ProcessedFrame>? _frameStreamController;
  FaceData? _lastFace;
  bool _isCapturing = false;
  bool _streaming = false;
  bool _frameStreamStarted = false;
  Timer? _frameThrottle;

  CameraController? get controller => _controller;
  CameraLens get lens => _lens;
  FaceData? get lastFace => _lastFace;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isStreaming => _streaming;
  bool get isCapturing => _isCapturing;

  static const int previewWidth = 320;

  Stream<ProcessedFrame>? get frameStream => _frameStreamController?.stream;

  Future<CameraDescription> _selectCamera(CameraLens lens) async {
    final cameras = await availableCameras();
    final dir = lens == CameraLens.front ? CameraLensDirection.front : CameraLensDirection.back;
    return cameras.firstWhere((c) => c.lensDirection == dir, orElse: () => cameras.first);
  }

  Future<void> init({CameraLens lens = CameraLens.front}) async {
    await dispose();
    _lens = lens;
    final cam = await _selectCamera(lens);
    _controller = CameraController(
      cam,
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    await _controller!.initialize();
  }

  Future<void> startFrameStream({
    required Future<List<FaceData>> Function(Uint8List bgrBytes, int w, int h) onFaceDetect,
    void Function(Uint8List nv21Bytes, int w, int h, int yRowStride)? onRawFrame,
    int throttleMs = 150,
  }) async {
    if (_streaming) return;
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    _streaming = true;
    _frameStreamStarted = false;
    _frameStreamController = StreamController<ProcessedFrame>.broadcast();
    final isMirrored = _lens == CameraLens.front;

    await ctrl.startImageStream((CameraImage image) async {
      _frameStreamStarted = true;
      if (!_streaming) return;
      if (_frameThrottle?.isActive ?? false) return;
      _frameThrottle = Timer(Duration(milliseconds: throttleMs), () {});

      try {
        final nv21 = _Nv21Args(
          yBytes: image.planes[0].bytes,
          vBytes: image.planes[1].bytes,
          uBytes: image.planes[1].bytes,
          width: image.width,
          height: image.height,
          yRowStride: image.planes[0].bytesPerRow,
          uvRowStride: image.planes[1].bytesPerRow,
          uvPixelStride: image.planes[1].bytesPerPixel ?? 2,
        );

        final rgba = await compute(_nv21ToRgba, nv21);

        // Raw NV21 for body pose detection
        if (onRawFrame != null) {
          final nv21Bytes = Uint8List(image.planes[0].bytes.length + image.planes[1].bytes.length);
          nv21Bytes.setRange(0, image.planes[0].bytes.length, image.planes[0].bytes);
          nv21Bytes.setRange(image.planes[0].bytes.length, nv21Bytes.length, image.planes[1].bytes);
          onRawFrame(nv21Bytes, image.width, image.height, image.planes[0].bytesPerRow);
        }

        final scale = previewWidth / image.width;
        final smallW = previewWidth;
        final smallH = (image.height * scale).round();
        final downscale = _DownscaleArgs(rgba: rgba, srcW: image.width, srcH: image.height, dstW: smallW, dstH: smallH);
        final smallRgba = await compute(_downscaleRgba, downscale);

        final bgr = await compute(_rgbaToBgr, smallRgba);

        final faces = await onFaceDetect(bgr, smallW, smallH);
        final face = faces.isNotEmpty ? faces.first : null;
        _lastFace = face;

        FaceData? scaledFace;
        if (face != null) {
          final sX = image.width / smallW;
          final sY = image.height / smallH;
          final bb = face.boundingBox;
          scaledFace = FaceData(
            boundingBox: Rect.fromLTWH(bb.left * sX, bb.top * sY, bb.width * sX, bb.height * sY),
            landmarks: face.landmarks.map((p) => Offset(p.dx * sX, p.dy * sY)).toList(),
            landmarksZ: face.landmarksZ,
            blendshapes: face.blendshapes,
          );
        }

        _frameStreamController!.add(ProcessedFrame(
          rgbaBytes: rgba,
          width: image.width,
          height: image.height,
          face: scaledFace,
          isMirrored: isMirrored,
        ));
      } catch (_) {}
    });
  }

  Future<void> stopFrameStream() async {
    if (!_streaming) return;
    _streaming = false;
    _frameThrottle?.cancel();
    if (_frameStreamStarted) {
      try {
        await _controller?.stopImageStream();
      } catch (_) {}
      _frameStreamStarted = false;
    }
    await _frameStreamController?.close();
    _frameStreamController = null;
  }

  Future<CaptureResult> takePhoto() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) throw StateError('Camera not initialized');
    _isCapturing = true;
    try {
      final xFile = await ctrl.takePicture();
      return CaptureResult(filePath: xFile.path, faceData: _lastFace);
    } finally {
      _isCapturing = false;
    }
  }

  Future<void> switchCamera() async {
    await dispose();
    _lens = _lens == CameraLens.front ? CameraLens.back : CameraLens.front;
    await init(lens: _lens);
  }

  Future<void> dispose() async {
    await stopFrameStream();
    await _controller?.dispose();
    _controller = null;
    _lastFace = null;
  }
}

class _Nv21Args {
  final Uint8List yBytes, uBytes, vBytes;
  final int width, height, yRowStride, uvRowStride, uvPixelStride;
  _Nv21Args({required this.yBytes, required this.uBytes, required this.vBytes, required this.width, required this.height, required this.yRowStride, required this.uvRowStride, required this.uvPixelStride});
}

Uint8List _nv21ToRgba(_Nv21Args a) {
  final rgba = Uint8List(a.width * a.height * 4);
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final yi = y * a.yRowStride + x;
      final uvi = (y >> 1) * a.uvRowStride + (x >> 1) * a.uvPixelStride;
      final yy = a.yBytes[yi].toInt();
      final vv = a.vBytes[uvi].toInt() - 128;
      final uu = a.uBytes[uvi + 1].toInt() - 128;
      final ri = (y * a.width + x) * 4;
      rgba[ri] = (yy + 1.402 * vv).round().clamp(0, 255);
      rgba[ri + 1] = (yy - 0.344 * uu - 0.714 * vv).round().clamp(0, 255);
      rgba[ri + 2] = (yy + 1.772 * uu).round().clamp(0, 255);
      rgba[ri + 3] = 255;
    }
  }
  return rgba;
}

class _DownscaleArgs {
  final Uint8List rgba;
  final int srcW, srcH, dstW, dstH;
  _DownscaleArgs({required this.rgba, required this.srcW, required this.srcH, required this.dstW, required this.dstH});
}

Uint8List _downscaleRgba(_DownscaleArgs a) {
  final out = Uint8List(a.dstW * a.dstH * 4);
  final xStep = a.srcW / a.dstW;
  final yStep = a.srcH / a.dstH;
  for (var dy = 0; dy < a.dstH; dy++) {
    for (var dx = 0; dx < a.dstW; dx++) {
      final sx = (dx * xStep).round();
      final sy = (dy * yStep).round();
      final si = (sy * a.srcW + sx) * 4;
      final di = (dy * a.dstW + dx) * 4;
      out[di] = a.rgba[si];
      out[di + 1] = a.rgba[si + 1];
      out[di + 2] = a.rgba[si + 2];
      out[di + 3] = 255;
    }
  }
  return out;
}

Uint8List _rgbaToBgr(Uint8List rgba) {
  final bgr = Uint8List(rgba.length ~/ 4 * 3);
  for (int i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
    bgr[j] = rgba[i + 2];
    bgr[j + 1] = rgba[i + 1];
    bgr[j + 2] = rgba[i];
  }
  return bgr;
}
