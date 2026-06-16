import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../edit/edit_config.dart';

img.Image applyLighting(img.Image src, LightingConfig config) {
  var result = src;
  if (config.autoLevels) result = autoLevels(result);
  if (config.brightness != 0.0 || config.contrast != 0.0) {
    final b = config.brightness * 255;
    final factor = (259 * (config.contrast * 255 + 255)) / (255 * (259 - config.contrast * 255));
    for (var y = 0; y < result.height; y++) {
      for (var x = 0; x < result.width; x++) {
        final p = result.getPixel(x, y);
        final r = (factor * (p.r - 128) + 128 + b).round().clamp(0, 255);
        final g = (factor * (p.g - 128) + 128 + b).round().clamp(0, 255);
        final bv = (factor * (p.b - 128) + 128 + b).round().clamp(0, 255);
        result.setPixel(x, y, img.ColorRgb8(r, g, bv));
      }
    }
  }
  return result;
}

img.Image autoLevels(img.Image src) {
  final histR = List.filled(256, 0), histG = List.filled(256, 0), histB = List.filled(256, 0);
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      histR[p.r.toInt()]++; histG[p.g.toInt()]++; histB[p.b.toInt()]++;
    }
  }
  int findPercentile(List<int> hist, double pct) {
    final total = hist.fold(0, (a, b) => a + b);
    final target = (total * pct).round();
    var sum = 0;
    for (var i = 0; i < 256; i++) { sum += hist[i]; if (sum >= target) return i; }
    return 255;
  }
  final loR = findPercentile(histR, 0.01), hiR = findPercentile(histR, 0.99);
  final loG = findPercentile(histG, 0.01), hiG = findPercentile(histG, 0.99);
  final loB = findPercentile(histB, 0.01), hiB = findPercentile(histB, 0.99);
  final result = img.Image.fromBytes(
    width: src.width, height: src.height,
    bytes: Uint8List(src.width * src.height * 4).buffer, numChannels: 4,
  );
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      result.setPixel(x, y, img.ColorRgb8(stretch(p.r.toInt(), loR, hiR), stretch(p.g.toInt(), loG, hiG), stretch(p.b.toInt(), loB, hiB)));
    }
  }
  return result;
}

int stretch(int val, int lo, int hi) {
  if (hi <= lo) return val.clamp(0, 255);
  return ((val - lo) * 255 ~/ (hi - lo)).clamp(0, 255);
}
