import 'dart:math' show atan2, pi, sqrt;
import 'dart:typed_data';
import '../../core/types.dart';

class GuidanceResult {
  final bool faceDetected;
  final bool faceCentered;
  final bool faceSized;
  final bool headLevel;
  final bool eyesOpen;
  final bool neutralExpression;
  final bool brightnessOk;
  final bool backlit;
  final bool hasShadow;
  final double headTiltDeg;
  final double brightnessLevel;
  final double faceOffsetFraction;
  final double eyeAspectRatio;
  final double mouthOpenFraction;

  const GuidanceResult({
    this.faceDetected = false,
    this.faceCentered = false,
    this.faceSized = false,
    this.headLevel = false,
    this.eyesOpen = true,
    this.neutralExpression = true,
    this.brightnessOk = true,
    this.backlit = false,
    this.hasShadow = false,
    this.headTiltDeg = 0,
    this.brightnessLevel = 0.5,
    this.faceOffsetFraction = 1.0,
    this.eyeAspectRatio = 0.3,
    this.mouthOpenFraction = 0.0,
  });

  bool get allGood =>
      faceDetected && faceCentered && faceSized && headLevel &&
      eyesOpen && neutralExpression && brightnessOk && !backlit && !hasShadow;
}

class GuidanceChecker {
  /// Validate face position within the frame.
  /// [frameW], [frameH]: preview resolution.
  /// [faceCenterX], [faceCenterY]: face bounding box center in relative coords (0-1).
  /// [faceWidthFraction]: face width relative to frame width.
  /// [isMirrored]: true for selfie cam (flip X).
  GuidanceResult check({
    required int frameW,
    required int frameH,
    required FaceData? face,
    required Uint8List frameBytes, // raw RGBA preview bytes
    required bool isMirrored,
    double targetFaceWidth = 0.25, // ideal face width fraction of frame
    double targetFaceTolerance = 0.08,
    double centerThreshold = 0.15,
    double maxTiltDeg = 8.0,
    double minBrightness = 0.3,
    double maxBrightness = 0.85,
  }) {
    if (face == null) {
      return const GuidanceResult();
    }

    final bb = face.boundingBox;
    var faceCx = bb.center.dx;
    if (isMirrored) {
      faceCx = frameW - faceCx;
    }
    final faceCy = bb.center.dy;
    final faceW = bb.width;

    final frameCenterX = frameW / 2;
    final frameCenterY = frameH / 2;

    final offsetX = (faceCx - frameCenterX) / frameW;
    final offsetY = (faceCy - frameCenterY) / frameH;
    final faceOffset = sqrt(offsetX * offsetX + offsetY * offsetY);

    final faceSized = (faceW / frameW - targetFaceWidth).abs() < targetFaceTolerance;
    final faceCentered = faceOffset < centerThreshold;

    final tiltAngle = _headTiltDeg(face);
    final headLevel = tiltAngle.abs() < maxTiltDeg;

    final ear = _eyeAspectRatio(face);
    final eyesOpen = ear > 0.18;

    final mouthOpen = _mouthOpenFraction(face);
    final neutralExpression = mouthOpen < 0.15;

    final brightness = _computeBrightness(frameBytes);
    final brightnessOk = brightness >= minBrightness && brightness <= maxBrightness;
    final backlit = _isBacklit(frameBytes, face, frameW, frameH);
    final shadow = _hasShadow(frameBytes, frameW, frameH);

    return GuidanceResult(
      faceDetected: true,
      faceCentered: faceCentered,
      faceSized: faceSized,
      headLevel: headLevel,
      eyesOpen: eyesOpen,
      neutralExpression: neutralExpression,
      brightnessOk: brightnessOk,
      backlit: backlit,
      hasShadow: shadow,
      headTiltDeg: tiltAngle,
      brightnessLevel: brightness,
      faceOffsetFraction: faceOffset,
      eyeAspectRatio: ear,
      mouthOpenFraction: mouthOpen,
    );
  }

  double _headTiltDeg(FaceData face) {
    if (face.landmarks.length < 468) return 0;
    final l = face.landmarks[33];
    final r = face.landmarks[263];
    return atan2(r.dy - l.dy, r.dx - l.dx) * 180 / pi;
  }

  double _eyeAspectRatio(FaceData face) {
    if (face.landmarks.length < 468) return 0.3;
    double ear = 0;
    for (final idxs in [
      // Left eye: 33(outer),160(upper-inner),158(upper-outer),133(inner),153(lower-outer),144(lower-inner)
      [33, 160, 158, 133, 153, 144],
      // Right eye: 362(outer),385(upper-inner),387(upper-outer),263(inner),373(lower-outer),380(lower-inner)
      [362, 385, 387, 263, 373, 380],
    ]) {
      final p = idxs.map((i) => face.landmarks[i]).toList();
      final w = (p[0].dx - p[3].dx).abs();
      final h1 = (p[1].dy - p[5].dy).abs();
      final h2 = (p[2].dy - p[4].dy).abs();
      if (w > 0) ear += (h1 + h2) / (2 * w);
    }
    return ear / 2;
  }

  double _mouthOpenFraction(FaceData face) {
    if (face.landmarks.length < 478) return 0;
    final upper = face.landmarks[13];
    final lower = face.landmarks[14];
    final left = face.landmarks[61];
    final right = face.landmarks[291];
    final mouthH = (lower.dy - upper.dy).abs();
    final mouthW = (right.dx - left.dx).abs();
    return mouthW > 0 ? mouthH / mouthW : 0;
  }

  double _computeBrightness(Uint8List rgba) {
    if (rgba.isEmpty) return 0.5;
    var sum = 0;
    final step = rgba.length > 100000 ? 16 : 4;
    for (var i = 0; i < rgba.length; i += step) {
      sum += rgba[i];
    }
    final count = rgba.length ~/ step;
    return count > 0 ? sum / (count * 255) : 0.5;
  }

  bool _isBacklit(Uint8List rgba, FaceData face, int w, int h) {
    if (rgba.length < w * h * 4) return false;
    final bb = face.boundingBox;
    final fx = bb.center.dx.round().clamp(0, w - 1);
    final fy = bb.center.dy.round().clamp(0, h - 1);
    final fi = (fy * w + fx) * 4;
    final faceBrightness = fi >= 0 && fi + 2 < rgba.length
        ? (rgba[fi] + rgba[fi + 1] + rgba[fi + 2]) / (3 * 255)
        : 0.5;

    double bgSum = 0;
    var bgCount = 0;
    for (var y = 0; y < h; y += 20) {
      for (var x = 0; x < w; x += 20) {
        if ((x - fx).abs() < w ~/ 6 && (y - fy).abs() < h ~/ 6) continue;
        final i = (y * w + x) * 4;
        if (i + 2 < rgba.length) {
          bgSum += (rgba[i] + rgba[i + 1] + rgba[i + 2]) / (3 * 255);
          bgCount++;
        }
      }
    }
    final bgBrightness = bgCount > 0 ? bgSum / bgCount : 0.5;
    return bgBrightness > faceBrightness + 0.2;
  }

  bool _hasShadow(Uint8List rgba, int w, int h) {
    if (rgba.length < w * h * 4) return false;
    var darkCount = 0;
    var total = 0;
    for (var y = 0; y < h; y += 8) {
      for (var x = 0; x < w; x += 8) {
        final i = (y * w + x) * 4;
        if (i + 2 < rgba.length) {
          final b = (rgba[i] + rgba[i + 1] + rgba[i + 2]) / (3 * 255);
          if (b < 0.2) darkCount++;
          total++;
        }
      }
    }
    return total > 0 && darkCount / total > 0.15;
  }
}
