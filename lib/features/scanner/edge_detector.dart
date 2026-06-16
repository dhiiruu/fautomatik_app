import 'dart:math' show sqrt;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

class EdgeDetectorResult {
  final bool photoFound;
  final Offset topLeft;
  final Offset topRight;
  final Offset bottomRight;
  final Offset bottomLeft;
  final Rect boundingBox;
  final double coverage;

  const EdgeDetectorResult({
    this.photoFound = false,
    this.topLeft = Offset.zero,
    this.topRight = Offset.zero,
    this.bottomRight = Offset.zero,
    this.bottomLeft = Offset.zero,
    this.boundingBox = Rect.zero,
    this.coverage = 0,
  });

  List<Offset> get corners => [topLeft, topRight, bottomRight, bottomLeft];
}

class EdgeDetector {
  static const double edgeThreshold = 40.0;
  static const double minPhotoCoverage = 0.15;
  static const double maxPhotoCoverage = 0.95;
  static const int minEdgePixels = 50;

  EdgeDetectorResult detect(Uint8List rgba, int width, int height) {
    final gray = _grayscale(rgba, width, height);
    final gradient = _simpleGradient(gray, width, height);
    final edges = _thresholdEdge(gradient, width, height);

    final edgeCount = edges.where((e) => e).length;
    if (edgeCount < minEdgePixels) {
      return const EdgeDetectorResult();
    }

    return _findPhotoBounds(edges, width, height, edgeCount);
  }

  Uint8List _grayscale(Uint8List rgba, int w, int h) {
    final gray = Uint8List(w * h);
    for (var i = 0; i < w * h; i++) {
      final pi = i * 4;
      gray[i] = (0.299 * rgba[pi] + 0.587 * rgba[pi + 1] + 0.114 * rgba[pi + 2]).round();
    }
    return gray;
  }

  Uint8List _simpleGradient(Uint8List gray, int w, int h) {
    final grad = Uint8List(w * h);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final gx = gray[(y - 1) * w + (x + 1)] + 2 * gray[y * w + (x + 1)] + gray[(y + 1) * w + (x + 1)]
                - gray[(y - 1) * w + (x - 1)] - 2 * gray[y * w + (x - 1)] - gray[(y + 1) * w + (x - 1)];
        final gy = gray[(y + 1) * w + (x - 1)] + 2 * gray[(y + 1) * w + x] + gray[(y + 1) * w + (x + 1)]
                - gray[(y - 1) * w + (x - 1)] - 2 * gray[(y - 1) * w + x] - gray[(y - 1) * w + (x + 1)];
        final mag = sqrt(gx * gx + gy * gy).round().clamp(0, 255);
        grad[y * w + x] = mag;
      }
    }
    return grad;
  }

  List<bool> _thresholdEdge(Uint8List grad, int w, int h) {
    final edges = List<bool>.filled(w * h, false);
    for (var i = 0; i < w * h; i++) {
      edges[i] = grad[i] > edgeThreshold;
    }
    return edges;
  }

  EdgeDetectorResult _findPhotoBounds(List<bool> edges, int w, int h, int edgeCount) {
    final cx = w / 2;
    final cy = h / 2;

    // Find edge pixels in each quadrant
    final top = <int>[];
    final bottom = <int>[];
    final left = <int>[];
    final right = <int>[];

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (!edges[y * w + x]) continue;
        if (y < cy) { top.add(x); } else { bottom.add(x); }
        if (x < cx) { left.add(y); } else { right.add(y); }
      }
    }

    if (top.isEmpty || bottom.isEmpty || left.isEmpty || right.isEmpty) {
      return const EdgeDetectorResult();
    }

    // Find extreme edge points
    top.sort();
    bottom.sort();
    left.sort();
    right.sort();

    final topEdge = top.isNotEmpty ? top[top.length ~/ 4] : 0;
    final bottomEdge = bottom.isNotEmpty ? bottom[bottom.length ~/ 4] : w;
    final leftEdge = left.isNotEmpty ? left[left.length ~/ 4] : 0;
    final rightEdge = right.isNotEmpty ? right[right.length ~/ 4] : h;

    // Fit lines to edge points
    final tl = Offset(topEdge.toDouble(), leftEdge.toDouble());
    final tr = Offset(bottomEdge.toDouble(), leftEdge.toDouble());
    final br = Offset(bottomEdge.toDouble(), rightEdge.toDouble());
    final bl = Offset(topEdge.toDouble(), rightEdge.toDouble());

    final rect = Rect.fromLTRB(topEdge.toDouble(), leftEdge.toDouble(),
        bottomEdge.toDouble(), rightEdge.toDouble());
    final coverage = (rect.width * rect.height) / (w * h);

    if (coverage < minPhotoCoverage || coverage > maxPhotoCoverage) {
      return const EdgeDetectorResult();
    }

    // Refine corners by finding nearest strong edge
    final refinedTL = _refineCorner(edges, w, h, tl);
    final refinedTR = _refineCorner(edges, w, h, tr);
    final refinedBR = _refineCorner(edges, w, h, br);
    final refinedBL = _refineCorner(edges, w, h, bl);

    return EdgeDetectorResult(
      photoFound: true,
      topLeft: refinedTL,
      topRight: refinedTR,
      bottomRight: refinedBR,
      bottomLeft: refinedBL,
      boundingBox: rect,
      coverage: coverage,
    );
  }

  Offset _refineCorner(List<bool> edges, int w, int h, Offset corner) {
    const searchRadius = 10;
    double bestDist = double.infinity;
    Offset best = corner;
    final cx = corner.dx.round();
    final cy = corner.dy.round();

    for (var dy = -searchRadius; dy <= searchRadius; dy++) {
      for (var dx = -searchRadius; dx <= searchRadius; dx++) {
        final x = cx + dx;
        final y = cy + dy;
        if (x < 0 || x >= w || y < 0 || y >= h) continue;
        if (!edges[y * w + x]) continue;
        final dist = (dx * dx + dy * dy).toDouble();
        if (dist < bestDist) {
          bestDist = dist;
          best = Offset(x.toDouble(), y.toDouble());
        }
      }
    }
    return best;
  }
}
