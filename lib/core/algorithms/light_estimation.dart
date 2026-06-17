import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'dart:math' as math;

/// Estimates the primary light source direction from an image.
/// Returns a vector (dx, dy) normalized, where (0,0) is center.
/// Positive dx = Light from Right, Positive dy = Light from Bottom.
class LightSourceEstimator {
  static Offset estimate(img.Image image) {
    final width = image.width;
    final height = image.height;
    
    double totalX = 0.0;
    double totalY = 0.0;
    double totalWeight = 0.0;

    // Sample grid to avoid processing every pixel for speed
    final step = math.max(1, (width / 50).round()); 

    for (int y = 0; y < height; y += step) {
      for (int x = 0; x < width; x += step) {
        final pixel = image.getPixel(x, y);
        final luminance = img.Luminance(pixel);
        
        // Calculate gradient magnitude and direction
        // Simple Sobel-like approximation using neighbors
        if (x > 0 && x < width - 1 && y > 0 && y < height - 1) {
          final left = img.Luminance(image.getPixel(x - 1, y));
          final right = img.Luminance(image.getPixel(x + 1, y));
          final top = img.Luminance(image.getPixel(x, y - 1));
          final bottom = img.Luminance(image.getPixel(x, y + 1));

          final dx = right - left;
          final dy = bottom - top;
          
          // Weight by brightness (brighter areas contribute more to light source)
          // and gradient strength (edges define the light direction better)
          final weight = luminance * math.sqrt(dx * dx + dy * dy);
          
          totalX += dx * weight;
          totalY += dy * weight;
          totalWeight += weight;
        }
      }
    }

    if (totalWeight == 0) return Offset.zero;

    // Normalize
    final avgX = totalX / totalWeight;
    final avgY = totalY / totalWeight;
    
    // Invert: If gradient goes Left->Right (brighter on right), light is from Right.
    // Our dx is (Right - Left). If positive, right is brighter.
    // So the vector points TO the light.
    
    final mag = math.sqrt(avgX * avgX + avgY * avgY);
    if (mag == 0) return Offset.zero;

    return Offset(avgX / mag, avgY / mag);
  }

  /// Applies dynamic lighting based on a source direction and intensity.
  /// This simulates adding a light source to the existing image.
  static img.Image applyDynamicLighting(img.Image image, Offset lightDir, double intensity) {
    final width = image.width;
    final height = image.height;
    final output = img.copy(image);

    // Center of image
    final cx = width / 2.0;
    final cy = height / 2.0;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        
        // Normalized coordinates -1 to 1
        final nx = (x - cx) / cx;
        final ny = (y - cy) / cy;

        // Dot product with light direction to determine illumination
        // If lightDir is (1, 0) (Right), and pixel is on Right (nx > 0), dot is positive.
        final dot = (nx * lightDir.dx) + (ny * lightDir.dy);
        
        // Calculate lighting factor: 
        // Base 1.0 + intensity * (dot product clamped)
        // We only add light, don't subtract (unless doing shadows, but here we add "light source")
        final factor = 1.0 + (intensity * (dot > 0 ? dot : 0.0));

        final r = img.getRed(pixel);
        final g = img.getGreen(pixel);
        final b = img.getBlue(pixel);

        final newR = math.min(255, (r * factor).round());
        final newG = math.min(255, (g * factor).round());
        final newB = math.min(255, (b * factor).round());

        output.setPixelRgba(x, y, newR, newG, newB, img.getAlpha(pixel));
      }
    }
    return output;
  }
}
