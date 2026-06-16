import 'dart:math' show max, min;
import 'package:image/image.dart' as img;
import '../edit/edit_config.dart';

img.Image skinSmooth(img.Image src, SkinSmoothConfig config) {
  if (config.amount <= 0 || config.radius <= 0) return src;
  final blurred = img.gaussianBlur(src, radius: config.radius);
  final amount = config.amount;
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      if (!isSkinColor(p.r.toInt(), p.g.toInt(), p.b.toInt())) continue;
      final bp = blurred.getPixel(x, y);
      final r = (p.r * (1.0 - amount) + bp.r * amount).round();
      final g = (p.g * (1.0 - amount) + bp.g * amount).round();
      final bv = (p.b * (1.0 - amount) + bp.b * amount).round();
      blurred.setPixel(x, y, img.ColorRgb8(r, g, bv));
    }
  }
  return blurred;
}

bool isSkinColor(int r, int g, int b) {
  if (r <= 20 || g <= 10 || b <= 10) return false;
  if (r <= g || r <= b) return false;
  final mx = max(r, max(g, b)), mn = min(r, min(g, b));
  if (mx - mn < 10) return false;
  return true;
}
