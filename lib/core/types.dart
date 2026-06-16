import 'dart:typed_data';
import 'dart:ui' show Rect, Offset;

enum BackgroundModel {
  u2netp,
  modnet,
}

class MaskData {
  final Uint8List maskBytes;
  final int width;
  final int height;

  MaskData({required this.maskBytes, required this.width, required this.height});
}

class FaceData {
  final Rect boundingBox;
  final List<Offset> landmarks; // 478 2D landmarks
  final List<double> landmarksZ; // 478 depth values
  final List<double>? blendshapes; // 52 blendshape scores

  FaceData({
    required this.boundingBox,
    required this.landmarks,
    required this.landmarksZ,
    this.blendshapes,
  });
}

class PipelineResult {
  final MaskData? backgroundMask;
  final List<FaceData>? faces;
  final Duration inferenceTime;

  PipelineResult({
    this.backgroundMask,
    this.faces,
    required this.inferenceTime,
  });
}
