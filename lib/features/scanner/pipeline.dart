import 'dart:typed_data';
import 'dart:ui' show Offset;
import 'package:image/image.dart' as img;
import 'edge_detector.dart';
import 'perspective_warp.dart';

class ScanResult {
  final bool success;
  final Uint8List? jpegBytes;
  final int? width;
  final int? height;
  final EdgeDetectorResult edges;

  const ScanResult({
    this.success = false,
    this.jpegBytes,
    this.width,
    this.height,
    this.edges = const EdgeDetectorResult(),
  });
}

class ScanPipeline {
  final EdgeDetector _edgeDetector = EdgeDetector();
  final PerspectiveWarp _warp = PerspectiveWarp();
  int _stableFrames = 0;
  EdgeDetectorResult _lastEdges = const EdgeDetectorResult();

  /// Process a preview frame for edge detection (fast, low-res).
  EdgeDetectorResult detectEdges(Uint8List rgba, int w, int h) {
    final result = _edgeDetector.detect(rgba, w, h);
    _lastEdges = result;
    return result;
  }

  /// Check if the detected photo is stable enough for auto-capture.
  bool isStable(EdgeDetectorResult current) {
    if (!current.photoFound) {
      _stableFrames = 0;
      return false;
    }

    if (_lastEdges.photoFound) {
      final dx = (current.topLeft.dx - _lastEdges.topLeft.dx).abs();
      final dy = (current.topLeft.dy - _lastEdges.topLeft.dy).abs();
      if (dx < 8 && dy < 8) {
        _stableFrames++;
      } else {
        _stableFrames = 0;
      }
    }
    _lastEdges = current;
    return _stableFrames >= 5;
  }

  /// Full scan: perspective correct + enhance a captured image.
  ScanResult scan({
    required Uint8List sourceBytes,
    required EdgeDetectorResult edges,
    int previewWidth = 320,
    int previewHeight = 240,
    bool enhance = true,
    bool autoCrop = true,
  }) {
    if (!edges.photoFound) return ScanResult(success: false, edges: edges);

    final image = img.decodeImage(sourceBytes);
    if (image == null) return ScanResult(success: false, edges: edges);

    final sourceWidth = image.width;
    final sourceHeight = image.height;
    final scaleX = sourceWidth / previewWidth;
    final scaleY = sourceHeight / previewHeight;

    Offset sc(Offset c) => Offset(c.dx * scaleX, c.dy * scaleY);

    final srcRgba = Uint8List.fromList(image.getBytes());

    var warped = _warp.warp(
      sourceRgba: srcRgba,
      srcW: sourceWidth,
      srcH: sourceHeight,
      srcTL: sc(edges.topLeft),
      srcTR: sc(edges.topRight),
      srcBR: sc(edges.bottomRight),
      srcBL: sc(edges.bottomLeft),
    );

    if (autoCrop) {
      warped = _warp.autoCrop(warped);
    }

    // Convert back to image for encoding
    var outImg = img.Image.fromBytes(
      width: warped.width,
      height: warped.height,
      bytes: warped.rgba.buffer,
      numChannels: 4,
    );

    if (enhance) {
      outImg = _enhanceScan(outImg);
    }

    final jpg = img.encodeJpg(outImg, quality: 92);

    return ScanResult(
      success: true,
      jpegBytes: jpg,
      width: warped.width,
      height: warped.height,
      edges: edges,
    );
  }

  img.Image _enhanceScan(img.Image image) {
    // Auto-levels: stretch histogram per channel
    var minR = 255, maxR = 0, minG = 255, maxG = 0, minB = 255, maxB = 0;
    final step = (image.width * image.height > 100000) ? 4 : 1;

    for (var y = 0; y < image.height; y += step) {
      for (var x = 0; x < image.width; x += step) {
        final p = image.getPixel(x, y);
        if (p.r.toInt() < minR) minR = p.r.toInt();
        if (p.r.toInt() > maxR) maxR = p.r.toInt();
        if (p.g.toInt() < minG) minG = p.g.toInt();
        if (p.g.toInt() > maxG) maxG = p.g.toInt();
        if (p.b.toInt() < minB) minB = p.b.toInt();
        if (p.b.toInt() > maxB) maxB = p.b.toInt();
      }
    }

    final rR = maxR - minR;
    final gR = maxG - minG;
    final bR = maxB - minB;
    if (rR < 5 && gR < 5 && bR < 5) return image;

    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        image.setPixel(x, y, img.ColorRgb8(
          ((p.r - minR) * 255 / rR).round().clamp(0, 255),
          ((p.g - minG) * 255 / gR).round().clamp(0, 255),
          ((p.b - minB) * 255 / bR).round().clamp(0, 255),
        ));
      }
    }
    return image;
  }

  void reset() {
    _stableFrames = 0;
    _lastEdges = const EdgeDetectorResult();
  }
}
