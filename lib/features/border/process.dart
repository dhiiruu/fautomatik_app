import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../edit/edit_config.dart';

img.Image addBorder(img.Image src, BorderConfig config) {
  if (config.width <= 0) return src;
  final w = src.width + config.width * 2, h = src.height + config.width * 2;
  final br = (config.color >> 16) & 0xFF, bg = (config.color >> 8) & 0xFF, bb = config.color & 0xFF;
  final result = img.Image.fromBytes(
    width: w, height: h,
    bytes: Uint8List(w * h * 4).buffer, numChannels: 4,
  );
  result.clear(img.ColorRgb8(br, bg, bb));
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      result.setPixel(config.width + x, config.width + y, src.getPixel(x, y));
    }
  }
  return result;
}
