import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'dart:math' as math;
import 'light_estimation.dart';

/// Pure Dart fallback implementations for Metal shaders if GPU not available
/// or for server-side processing.

class AdvancedFilters {
  /// Bilateral Filter for Denoising
  /// [sigmaSpace] controls the spatial extent (radius).
  /// [sigmaColor] controls how much colors are mixed (edge preservation).
  static img.Image denoise(img.Image image, {double sigmaSpace = 2.0, double sigmaColor = 0.1}) {
    final width = image.width;
    final height = image.height;
    final output = img.copy(image);
    final radius = (sigmaSpace * 2).round();

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final centerPixel = image.getPixel(x, y);
        final centerColor = img.ColorRgb8(
          img.getRed(centerPixel),
          img.getGreen(centerPixel),
          img.getBlue(centerPixel),
        );
        
        double totalWeight = 0.0;
        double rSum = 0.0, gSum = 0.0, bSum = 0.0;

        for (int ky = -radius; ky <= radius; ky++) {
          for (int kx = -radius; kx <= radius; kx++) {
            final nx = x + kx;
            final ny = y + ky;

            if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
              final neighborPixel = image.getPixel(nx, ny);
              final neighborColor = img.ColorRgb8(
                img.getRed(neighborPixel),
                img.getGreen(neighborPixel),
                img.getBlue(neighborPixel),
              );

              // Spatial weight
              final distSq = kx * kx + ky * ky;
              final wSpace = math.exp(-distSq / (2 * sigmaSpace * sigmaSpace));

              // Range weight (color difference)
              final dr = centerColor.r - neighborColor.r;
              final dg = centerColor.g - neighborColor.g;
              final db = centerColor.b - neighborColor.b;
              final colorDistSq = dr * dr + dg * dg + db * db;
              final wRange = math.exp(-colorDistSq / (2 * 255 * 255 * sigmaColor * sigmaColor));

              final weight = wSpace * wRange;
              
              rSum += img.getRed(neighborPixel) * weight;
              gSum += img.getGreen(neighborPixel) * weight;
              bSum += img.getBlue(neighborPixel) * weight;
              totalWeight += weight;
            }
          }
        }

        if (totalWeight > 0) {
          output.setPixelRgba(
            x, y,
            (rSum / totalWeight).round(),
            (gSum / totalWeight).round(),
            (bSum / totalWeight).round(),
            img.getAlpha(centerPixel),
          );
        }
      }
    }
    return output;
  }

  /// Simple Dehaze implementation
  /// Increases contrast in low-frequency areas.
  static img.Image dehaze(img.Image image, {double amount = 0.5}) {
    final width = image.width;
    final height = image.height;
    final output = img.copy(image);
    final atmosphericLight = 255.0;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        final r = img.getRed(pixel).toDouble();
        final g = img.getGreen(pixel).toDouble();
        final b = img.getBlue(pixel).toDouble();

        final minChannel = math.min(r, math.min(g, b));
        
        // Estimate transmission
        final transmission = 1.0 - (amount * (1.0 - (minChannel / 255.0)));
        final tClamped = math.max(transmission, 0.1);

        final newR = ((r - atmosphericLight) / tClamped + atmosphericLight).clamp(0.0, 255.0);
        final newG = ((g - atmosphericLight) / tClamped + atmosphericLight).clamp(0.0, 255.0);
        final newB = ((b - atmosphericLight) / tClamped + atmosphericLight).clamp(0.0, 255.0);

        output.setPixelRgba(x, y, newR.round(), newG.round(), newB.round(), img.getAlpha(pixel));
      }
    }
    return output;
  }

  /// Applies lighting based on estimated or manual direction
  static img.Image applyLighting(img.Image image, Offset lightDir, double intensity) {
    return LightSourceEstimator.applyDynamicLighting(image, lightDir, intensity);
  }
}
