import 'package:image/image.dart' as img;
import '../../core/types.dart';

img.Image fixRedEye(img.Image src, FaceData face) {
  if (face.landmarks.length < 468) return src;
  for (final idx in [33, 263]) {
    final cx = face.landmarks[idx].dx.round(), cy = face.landmarks[idx].dy.round();
    final x1 = (cx - 12).clamp(0, src.width - 1), y1 = (cy - 12).clamp(0, src.height - 1);
    final x2 = (cx + 12).clamp(0, src.width - 1), y2 = (cy + 12).clamp(0, src.height - 1);
    for (var y = y1; y < y2; y++) {
      for (var x = x1; x < x2; x++) {
        final p = src.getPixel(x, y);
        if (p.r > p.g * 1.5 && p.r > p.b * 1.5) {
          final avg = (p.g + p.b) ~/ 2;
          src.setPixel(x, y, img.ColorRgb8(avg, avg, avg));
        }
      }
    }
  }
  return src;
}
