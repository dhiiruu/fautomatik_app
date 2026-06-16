import 'dart:math' show atan2, pi, cos, sin;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../../core/types.dart';

double headTiltAngle(FaceData face) {
  if (face.landmarks.length < 468) return 0.0;
  final leftEye = face.landmarks[33];
  final rightEye = face.landmarks[263];
  final dx = rightEye.dx - leftEye.dx;
  final dy = rightEye.dy - leftEye.dy;
  return atan2(dy, dx) * 180 / pi;
}

img.Image rotateStraight(img.Image src, double angleDeg) {
  final rad = angleDeg * pi / 180;
  final c = cos(rad).abs();
  final s = sin(rad).abs();
  final newW = (src.width * c + src.height * s).ceil();
  final newH = (src.width * s + src.height * c).ceil();

  final dst = img.Image.fromBytes(
    width: newW, height: newH,
    bytes: Uint8List(newW * newH * 4).buffer, numChannels: 4,
  );

  final cx = src.width / 2, cy = src.height / 2;
  final dcx = newW / 2, dcy = newH / 2;

  for (var y = 0; y < newH; y++) {
    for (var x = 0; x < newW; x++) {
      final dx = x - dcx, dy = y - dcy;
      final srcX = (dx * c + dy * s + cx).round();
      final srcY = (-dx * s + dy * c + cy).round();
      if (srcX >= 0 && srcX < src.width && srcY >= 0 && srcY < src.height) {
        dst.setPixel(x, y, src.getPixel(srcX, srcY));
      }
    }
  }

  return cropTransparent(dst);
}

img.Image cropTransparent(img.Image src) {
  int minX = src.width, minY = src.height, maxX = 0, maxY = 0;
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      if (src.getPixel(x, y).a > 0) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < minX || maxY < minY) return src;
  return img.copyCrop(src, x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1);
}
