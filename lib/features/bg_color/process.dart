import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../edit/edit_config.dart';

img.Image replaceBackground(
  img.Image src,
  Uint8List maskBytes,
  int maskWidth,
  int maskHeight,
  BackgroundConfig config,
) {
  final mask = img.Image.fromBytes(width: maskWidth, height: maskHeight, bytes: maskBytes.buffer, numChannels: 1);
  final scaledMask = img.copyResize(mask, width: src.width, height: src.height, interpolation: img.Interpolation.linear);
  final blurredMask = img.gaussianBlur(scaledMask, radius: config.featherRadius);
  final result = img.Image.fromBytes(width: src.width, height: src.height, bytes: Uint8List(src.width * src.height * 4).buffer, numChannels: 4);
  fillBackground(result, config);
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final maskPixel = blurredMask.getPixel(x, y);
      final srcPixel = src.getPixel(x, y);
      final alpha = maskPixel.r / 255.0;
      if (alpha >= 1.0) {
        result.setPixel(x, y, srcPixel);
      } else if (alpha > config.maskThreshold) {
        final bgPixel = result.getPixel(x, y);
        final r = (srcPixel.r * alpha + bgPixel.r * (1.0 - alpha)).round();
        final g = (srcPixel.g * alpha + bgPixel.g * (1.0 - alpha)).round();
        final b = (srcPixel.b * alpha + bgPixel.b * (1.0 - alpha)).round();
        result.setPixel(x, y, img.ColorRgb8(r, g, b));
      }
    }
  }
  return result;
}

void fillBackground(img.Image result, BackgroundConfig config) {
  if (config.imageBytes != null) {
    final bgImg = img.decodeImage(config.imageBytes!);
    if (bgImg != null) {
      for (var y = 0; y < result.height; y++) {
        for (var x = 0; x < result.width; x++) {
          result.setPixel(x, y, bgImg.getPixel(x % bgImg.width, y % bgImg.height));
        }
      }
      return;
    }
  }
  final r = (config.color >> 16) & 0xFF, g = (config.color >> 8) & 0xFF, b = config.color & 0xFF;
  result.clear(img.ColorRgb8(r, g, b));
}
