import 'package:image/image.dart' as img;
import '../edit/edit_config.dart';

img.Image sharpenImage(img.Image src, SharpenConfig config) {
  if (config.amount <= 0) return src;
  final blurred = img.gaussianBlur(src, radius: 1);
  final amount = config.amount;
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y), bp = blurred.getPixel(x, y);
      final r = (p.r + (p.r - bp.r) * amount).round().clamp(0, 255);
      final g = (p.g + (p.g - bp.g) * amount).round().clamp(0, 255);
      final bv = (p.b + (p.b - bp.b) * amount).round().clamp(0, 255);
      blurred.setPixel(x, y, img.ColorRgb8(r, g, bv));
    }
  }
  return blurred;
}
