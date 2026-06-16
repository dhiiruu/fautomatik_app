import 'dart:typed_data';
import 'dart:ui' show Rect, Offset;
import 'package:face_detection_tflite/face_detection_tflite.dart';
import '../../core/types.dart';
import 'face_pipeline_interface.dart';

class MediaPipeFacePipeline implements FacePipeline {
  FaceDetector? _detector;

  @override
  Future<void> load() async {
    _detector = await FaceDetector.create(
      model: FaceDetectionModel.frontCamera,
    );
  }

  @override
  Future<List<FaceData>> process(Uint8List imageBytes, int width, int height) async {
    final detector = _detector;
    if (detector == null) throw StateError('FacePipeline not loaded');

    final faces = await detector.detectFacesFromMatBytes(
      _rgbaToBgr(imageBytes),
      width: width,
      height: height,
      matType: 16,
      mode: FaceDetectionMode.standard,
    );

    return faces.map((f) => _convertFace(f)).toList();
  }

  static Uint8List _rgbaToBgr(Uint8List rgba) {
    final len = rgba.length;
    final bgr = Uint8List(len ~/ 4 * 3);
    for (int i = 0, j = 0; i < len; i += 4, j += 3) {
      bgr[j] = rgba[i + 2];
      bgr[j + 1] = rgba[i + 1];
      bgr[j + 2] = rgba[i];
    }
    return bgr;
  }

  FaceData _convertFace(Face face) {
    final bb = face.boundingBox;
    final rect = Rect.fromLTWH(bb.topLeft.x, bb.topLeft.y, bb.width, bb.height);

    final mesh = face.mesh;
    final landmarks = <Offset>[];
    final landmarksZ = <double>[];

    if (mesh != null) {
      for (final p in mesh.points) {
        landmarks.add(Offset(p.x, p.y));
        landmarksZ.add(p.z ?? 0.0);
      }
    }

    return FaceData(
      boundingBox: rect,
      landmarks: landmarks,
      landmarksZ: landmarksZ,
    );
  }

  @override
  void dispose() {
    _detector?.dispose();
    _detector = null;
  }
}
