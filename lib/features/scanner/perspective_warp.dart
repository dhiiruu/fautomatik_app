import 'dart:typed_data';
import 'dart:ui' show Offset;

class WarpResult {
  final Uint8List rgba;
  final int width;
  final int height;

  WarpResult({required this.rgba, required this.width, required this.height});
}

class PerspectiveWarp {
  /// Warp a quadrilateral to a rectangle using bilinear interpolation.
  WarpResult warp({
    required Uint8List sourceRgba,
    required int srcW,
    required int srcH,
    required Offset srcTL,
    required Offset srcTR,
    required Offset srcBR,
    required Offset srcBL,
    int? dstW,
    int? dstH,
  }) {
    dstW ??= srcW;
    dstH ??= srcH;
    final out = Uint8List(dstW * dstH * 4);

    for (var dy = 0; dy < dstH; dy++) {
      for (var dx = 0; dx < dstW; dx++) {
        final u = dx / dstW;
        final v = dy / dstH;

        final topX = _lerp(srcTL.dx, srcTR.dx, u);
        final topY = _lerp(srcTL.dy, srcTR.dy, u);
        final botX = _lerp(srcBL.dx, srcBR.dx, u);
        final botY = _lerp(srcBL.dy, srcBR.dy, u);

        final sx = _lerp(topX, botX, v);
        final sy = _lerp(topY, botY, v);

        final ci = sx.round().clamp(0, srcW - 1);
        final ri = sy.round().clamp(0, srcH - 1);
        final srcIdx = (ri * srcW + ci) * 4;

        final di = (dy * dstW + dx) * 4;
        out[di] = sourceRgba[srcIdx];
        out[di + 1] = sourceRgba[srcIdx + 1];
        out[di + 2] = sourceRgba[srcIdx + 2];
        out[di + 3] = 255;
      }
    }
    return WarpResult(rgba: out, width: dstW, height: dstH);
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// Auto-crop to remove black borders from the transform.
  WarpResult autoCrop(WarpResult input) {
    final rgba = input.rgba;
    final w = input.width;
    final h = input.height;
    var minX = w, minY = h, maxX = 0, maxY = 0;
    final step = (w * h > 500000) ? 2 : 1;

    for (var y = 0; y < h; y += step) {
      for (var x = 0; x < w; x += step) {
        final i = (y * w + x) * 4;
        if (rgba[i] > 10 || rgba[i + 1] > 10 || rgba[i + 2] > 10) {
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }
    }

    if (minX >= maxX || minY >= maxY) return input;

    final cw = maxX - minX + 1;
    final ch = maxY - minY + 1;
    final cropped = Uint8List(cw * ch * 4);
    for (var y = 0; y < ch; y++) {
      for (var x = 0; x < cw; x++) {
        final si = ((minY + y) * w + (minX + x)) * 4;
        final di = (y * cw + x) * 4;
        cropped[di] = rgba[si];
        cropped[di + 1] = rgba[si + 1];
        cropped[di + 2] = rgba[si + 2];
        cropped[di + 3] = 255;
      }
    }
    return WarpResult(rgba: cropped, width: cw, height: ch);
  }
}
