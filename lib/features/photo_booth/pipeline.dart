import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class BodyData {
  final bool detected;
  final Map<PoseLandmarkType, PoseLandmark> landmarks;
  final double noseY;
  final double leftShoulderY;
  final double rightShoulderY;
  final double leftHipY;
  final double rightHipY;
  final double leftKneeY;
  final double rightKneeY;
  final double leftAnkleY;
  final double rightAnkleY;
  final double leftShoulderX;
  final double rightShoulderX;
  final double leftWristY;
  final double rightWristY;

  const BodyData({
    this.detected = false,
    this.landmarks = const {},
    this.noseY = 0,
    this.leftShoulderY = 0,
    this.rightShoulderY = 0,
    this.leftHipY = 0,
    this.rightHipY = 0,
    this.leftKneeY = 0,
    this.rightKneeY = 0,
    this.leftAnkleY = 0,
    this.rightAnkleY = 0,
    this.leftShoulderX = 0,
    this.rightShoulderX = 0,
    this.leftWristY = 0,
    this.rightWristY = 0,
  });

  double get midShoulderY => (leftShoulderY + rightShoulderY) / 2;
  double get midHipY => (leftHipY + rightHipY) / 2;
  double get midKneeY => (leftKneeY + rightKneeY) / 2;
  double get midAnkleY => (leftAnkleY + rightAnkleY) / 2;

  double get shoulderWidth => (rightShoulderX - leftShoulderX).abs();
}

class BodyPipeline {
  PoseDetector? _detector;

  Future<void> load() async {
    _detector = PoseDetector(
      options: PoseDetectorOptions(
        model: PoseDetectionModel.base,
        mode: PoseDetectionMode.stream,
      ),
    );
  }

  Future<BodyData> process({
    required Uint8List nv21Bytes,
    required int width,
    required int height,
    required int yRowStride,
    CameraLensDirection lens = CameraLensDirection.front,
    int rotation = 0,
  }) async {
    final detector = _detector;
    if (detector == null) throw StateError('BodyPipeline not loaded');

    final inputImage = InputImage.fromBytes(
      bytes: nv21Bytes,
      metadata: InputImageMetadata(
        size: Size(width.toDouble(), height.toDouble()),
        rotation: InputImageRotation.values.firstWhere(
          (r) => r.rawValue == rotation,
          orElse: () => InputImageRotation.rotation0deg,
        ),
        format: InputImageFormat.nv21,
        bytesPerRow: yRowStride,
      ),
    );

    final poses = await detector.processImage(inputImage);
    if (poses.isEmpty) return const BodyData();

    final pose = poses.first;
    final lm = pose.landmarks;

    return BodyData(
      detected: true,
      landmarks: lm,
      noseY: lm[PoseLandmarkType.nose]?.y ?? 0,
      leftShoulderY: lm[PoseLandmarkType.leftShoulder]?.y ?? 0,
      rightShoulderY: lm[PoseLandmarkType.rightShoulder]?.y ?? 0,
      leftHipY: lm[PoseLandmarkType.leftHip]?.y ?? 0,
      rightHipY: lm[PoseLandmarkType.rightHip]?.y ?? 0,
      leftKneeY: lm[PoseLandmarkType.leftKnee]?.y ?? 0,
      rightKneeY: lm[PoseLandmarkType.rightKnee]?.y ?? 0,
      leftAnkleY: lm[PoseLandmarkType.leftAnkle]?.y ?? 0,
      rightAnkleY: lm[PoseLandmarkType.rightAnkle]?.y ?? 0,
      leftShoulderX: lm[PoseLandmarkType.leftShoulder]?.x ?? 0,
      rightShoulderX: lm[PoseLandmarkType.rightShoulder]?.x ?? 0,
      leftWristY: lm[PoseLandmarkType.leftWrist]?.y ?? 0,
      rightWristY: lm[PoseLandmarkType.rightWrist]?.y ?? 0,
    );
  }

  void dispose() {
    _detector?.close();
    _detector = null;
  }
}
