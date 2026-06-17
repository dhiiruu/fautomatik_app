import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Cloth Warping Algorithm with Realistic Physics
/// 
/// This implements a CPU-based cloth simulation using:
/// 1. Mass-Spring-Damper system for physics
/// 2. Fractional Brownian Motion (FBM) for wrinkle generation
/// 3. Dynamic lighting and shading adjustment
/// 4. Edge-preserving smoothing for natural fabric appearance
class ClothWarpProcessor {
  final double intensity;
  final double stiffness;
  final double damping;
  final double gravity;
  final double windStrength;
  final Duration animationTime;

  const ClothWarpProcessor({
    this.intensity = 0.5,
    this.stiffness = 0.7,
    this.damping = 0.3,
    this.gravity = 9.8,
    this.windStrength = 0.0,
    this.animationTime = Duration.zero,
  });

  /// Process image with cloth warping effect
  Future<Uint8List> process(Uint8List inputBytes, int width, int height) async {
    final image = img.decodeImage(inputBytes);
    if (image == null) throw Exception('Failed to decode image');

    // Create output image
    final output = img.Image(width: width, height: height);

    // Process each pixel
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final uv = _normalizeCoord(x, y, width, height);
        
        // Calculate displacement from wrinkles and physics
        final wrinkleDisp = _calculateWrinkles(uv, animationTime.inMilliseconds / 1000.0);
        final physicsDisp = _simulatePhysics(uv);
        final totalDisp = _addVectors(wrinkleDisp, physicsDisp);
        
        // Apply intensity scaling
        final scaledDisp = _scaleVector(totalDisp, intensity);
        
        // Sample from displaced position
        final sampleUV = _addVectors(uv, scaledDisp);
        final sampleX = _clamp((sampleUV.$1 * width).round(), 0, width - 1);
        final sampleY = _clamp((sampleUV.$2 * height).round(), 0, height - 1);
        
        final pixel = image.getPixel(sampleX, sampleY);
        
        // Calculate lighting on cloth folds
        final lighting = _calculateLighting(uv, totalDisp);
        final shadow = _calculateShadow(totalDisp);
        
        // Adjust color with realistic lighting
        final adjusted = _adjustColor(pixel, lighting, shadow);
        
        output.setPixelRgba(x, y, adjusted.r, adjusted.g, adjusted.b, pixel.a);
      }
    }

    // Apply edge-preserving smoothing
    _applySmoothing(output, width, height);
    
    final encoded = img.encodePng(output);
    return Uint8List.fromList(encoded);
  }

  /// Calculate fabric wrinkles using FBM (Fractional Brownian Motion)
  (double, double) _calculateWrinkles((double u, double v) uv, double time) {
    double displacementU = 0.0;
    double displacementV = 0.0;
    
    // Multiple octaves of noise for realistic wrinkles
    for (int i = 0; i < 5; i++) {
      final frequency = pow(2.0, i);
      final amplitude = pow(0.5, i);
      
      final noiseVal = _fbm(
        uv.$1 * frequency * 10.0,
        uv.$2 * frequency * 10.0 + time * 0.1 * frequency,
      );
      
      if (i % 2 == 0) {
        displacementU += (noiseVal - 0.5) * amplitude * 0.02;
      } else {
        displacementV += (noiseVal - 0.5) * amplitude * 0.01;
      }
    }
    
    return (displacementU, displacementV);
  }

  /// Simulate cloth physics (gravity, wind, stiffness, damping)
  (double, double) _simulatePhysics((double u, double v) uv) {
    double dispU = 0.0;
    double dispV = 0.0;
    
    // Gravity effect - cloth hangs down more at bottom
    dispV -= gravity * uv.$2 * 0.001;
    
    // Wind effect (if enabled)
    if (windStrength > 0) {
      final windForce = (uv.$1 + uv.$2) * windStrength;
      dispU += windForce * 0.005;
      dispV += windForce * 0.002;
    }
    
    // Stiffness resistance
    final stiffnessFactor = 1.0 - stiffness * 0.5;
    dispU *= stiffnessFactor;
    dispV *= stiffnessFactor;
    
    // Damping over time
    final dampingFactor = exp(-damping * animationTime.inMilliseconds / 1000.0);
    dispU *= dampingFactor;
    dispV *= dampingFactor;
    
    return (dispU, dispV);
  }

  /// Calculate lighting on cloth folds based on surface normals
  double _calculateLighting((double u, double v) uv, (double du, double dv) displacement) {
    final epsilon = 0.01;
    
    // Estimate normal from displacement gradient
    final dx = _fbm((uv.$1 + epsilon) * 20.0, uv.$2 * 20.0) - 
               _fbm(uv.$1 * 20.0, uv.$2 * 20.0);
    final dy = _fbm(uv.$1 * 20.0, (uv.$2 + epsilon) * 20.0) - 
               _fbm(uv.$1 * 20.0, uv.$2 * 20.0);
    
    // Normalize the normal vector
    final normalMag = sqrt(dx * dx * 100.0 + dy * dy * 100.0 + 1.0);
    final nx = -dx * 10.0 / normalMag;
    final ny = -dy * 10.0 / normalMag;
    final nz = 1.0 / normalMag;
    
    // Light direction
    final lx = 0.5;
    final ly = -0.3;
    final lz = 1.0;
    final lightMag = sqrt(lx * lx + ly * ly + lz * lz);
    
    // Diffuse lighting (Lambertian)
    final diffuse = (nx * lx + ny * ly + nz * lz) / lightMag;
    final diffuseClamped = diffuse > 0 ? diffuse : 0;
    
    // Specular highlights
    final vx = 0.0, vy = 0.0, vz = 1.0;
    final hx = (nx + vx) / 2.0;
    final hy = (ny + vy) / 2.0;
    final hz = (nz + vz) / 2.0;
    final specular = pow(max(0.0, nx * hx + ny * hy + nz * hz), 32.0);
    
    return diffuseClamped + specular * 0.3;
  }

  /// Calculate shadow in deep folds
  double _calculateShadow((double du, double dv) displacement) {
    final foldDepth = sqrt(displacement.$1 * displacement.$1 + 
                          displacement.$2 * displacement.$2);
    final shadow = 1.0 - foldDepth * 5.0;
    return shadow.clamp(0.6, 1.0);
  }

  /// Adjust color with realistic fabric lighting
  ({int r, int g, int b}) _adjustColor(img.Pixel pixel, double lighting, double shadow) {
    // Convert to float for calculations
    final r = pixel.r / 255.0;
    final g = pixel.g / 255.0;
    final b = pixel.b / 255.0;
    
    // Warm shadows, cool highlights
    final shadowColor = (0.9, 0.85, 0.8);
    final highlightColor = (1.0, 1.0, 1.05);
    
    // Apply lighting
    var adjustedR = r * lighting;
    var adjustedG = g * lighting;
    var adjustedB = b * lighting;
    
    // Blend with shadow color
    adjustedR = adjustedR * shadowColor.$1 * (1.0 - lighting) + adjustedR * lighting;
    adjustedG = adjustedG * shadowColor.$2 * (1.0 - lighting) + adjustedG * lighting;
    adjustedB = adjustedB * shadowColor.$3 * (1.0 - lighting) + adjustedB * lighting;
    
    // Add highlights
    if (lighting > 0.5) {
      final highlightBlend = (lighting - 0.5) * 2.0;
      adjustedR = adjustedR + adjustedR * (highlightColor.$1 - 1.0) * highlightBlend;
      adjustedG = adjustedG + adjustedG * (highlightColor.$2 - 1.0) * highlightBlend;
      adjustedB = adjustedB + adjustedB * (highlightColor.$3 - 1.0) * highlightBlend;
    }
    
    // Saturation boost in midtones
    final luminance = adjustedR * 0.299 + adjustedG * 0.587 + adjustedB * 0.114;
    final saturationBoost = 1.1 - (lighting - 0.5).abs();
    adjustedR = luminance * (1.0 - saturationBoost) + adjustedR * saturationBoost;
    adjustedG = luminance * (1.0 - saturationBoost) + adjustedG * saturationBoost;
    adjustedB = luminance * (1.0 - saturationBoost) + adjustedB * saturationBoost;
    
    // Clamp and convert back to int
    return (
      r: (adjustedR.clamp(0.0, 1.0) * 255).round(),
      g: (adjustedG.clamp(0.0, 1.0) * 255).round(),
      b: (adjustedB.clamp(0.0, 1.0) * 255).round(),
    );
  }

  /// Apply edge-preserving smoothing to fabric
  void _applySmoothing(img.Image image, int width, int height) {
    final temp = img.Image(width: width, height: height);
    final radius = 2;
    
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final center = image.getPixel(x, y);
        var sumR = center.r.toDouble();
        var sumG = center.g.toDouble();
        var sumB = center.b.toDouble();
        var totalWeight = 1.0;
        
        // Sample neighbors with bilateral weights
        for (int dy = -radius; dy <= radius; dy++) {
          for (int dx = -radius; dx <= radius; dx++) {
            if (dx == 0 && dy == 0) continue;
            
            final nx = x + dx;
            final ny = y + dy;
            
            if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
            
            final neighbor = image.getPixel(nx, ny);
            
            // Spatial weight
            final dist = sqrt(dx * dx + dy * dy);
            final spatialWeight = exp(-dist * dist / 2.0);
            
            // Color weight (preserve edges)
            final colorDiff = sqrt(
              pow(neighbor.r - center.r, 2) +
              pow(neighbor.g - center.g, 2) +
              pow(neighbor.b - center.b, 2),
            ) / 255.0;
            final colorWeight = exp(-colorDiff * colorDiff / 0.1);
            
            final weight = spatialWeight * colorWeight;
            sumR += neighbor.r * weight;
            sumG += neighbor.g * weight;
            sumB += neighbor.b * weight;
            totalWeight += weight;
          }
        }
        
        temp.setPixelRgba(
          x, y,
          (sumR / totalWeight).round(),
          (sumG / totalWeight).round(),
          (sumB / totalWeight).round(),
          center.a,
        );
      }
    }
    
    // Copy back to original
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = temp.getPixel(x, y);
        image.setPixelRgba(x, y, pixel.r, pixel.g, pixel.b, pixel.a);
      }
    }
  }

  // Helper functions
  (double, double) _normalizeCoord(int x, int y, int w, int h) {
    return ((x + 0.5) / w, (y + 0.5) / h);
  }

  (double, double) _addVectors((double, double) a, (double, double) b) {
    return (a.$1 + b.$1, a.$2 + b.$2);
  }

  (double, double) _scaleVector((double, double) v, double s) {
    return (v.$1 * s, v.$2 * s);
  }

  int _clamp(int value, int min, int max) {
    return value < min ? min : (value > max ? max : value);
  }

  double _fbm(double u, double v) {
    return (_noise(u, v) + _noise(u * 2.0, v * 2.0) * 0.5 + 
            _noise(u * 4.0, v * 4.0) * 0.25) / 1.75;
  }

  double _noise(double u, double v) {
    final iu = u.floor();
    final iv = v.floor();
    final fu = u - iu;
    final fv = v - iv;
    
    final smoothU = fu * fu * (3.0 - 2.0 * fu);
    final smoothV = fv * fv * (3.0 - 2.0 * fv);
    
    final a = _hash(iu, iv);
    final b = _hash(iu + 1, iv);
    final c = _hash(iu, iv + 1);
    final d = _hash(iu + 1, iv + 1);
    
    return (a * (1.0 - smoothU) + b * smoothU) * (1.0 - smoothV) +
           (c * (1.0 - smoothU) + d * smoothU) * smoothV;
  }

  double _hash(int x, int y) {
    final n = x + y * 57;
    final sinVal = sin(n * 12.9898);
    return (sinVal * 43758.5453) - (sinVal * 43758.5453).floor();
  }

  // Math helpers
  double pow(double base, double exp) => base is int && exp is int 
    ? base.toDouble().pow(exp.toInt()) 
    : base.toDouble().pow(exp.toInt());
  
  double sqrt(double x) => x.sqrt();
  double exp(double x) => x.exp();
  double sin(double x) => x.sin();
  double max(double a, double b) => a > b ? a : b;
}

// Extension for math operations
extension on double {
  double pow(int exp) {
    var result = this;
    for (var i = 1; i < exp; i++) result *= this;
    return result;
  }
  
  double sqrt() => _sqrt(this);
  double exp() => _exp(this);
  double sin() => _sin(this);
  
  static double _sqrt(double x) {
    if (x < 0) return double.nan;
    if (x == 0) return 0;
    var guess = x / 2;
    for (var i = 0; i < 20; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }
  
  static double _exp(double x) {
    var result = 1.0;
    var term = 1.0;
    for (var i = 1; i < 30; i++) {
      term *= x / i;
      result += term;
    }
    return result;
  }
  
  static double _sin(double x) {
    // Normalize to [-pi, pi]
    while (x > 3.14159) x -= 6.28318;
    while (x < -3.14159) x += 6.28318;
    
    var result = x;
    var term = x;
    for (var i = 1; i < 15; i++) {
      term *= -x * x / ((2 * i) * (2 * i + 1));
      result += term;
    }
    return result;
  }
}
