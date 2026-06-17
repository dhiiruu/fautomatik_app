import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import '../../core/algorithms/light_estimation.dart';

/// Face Sculpting Tool Widget
/// Provides sliders for adjusting facial features (eyes, nose, jaw, face shape)
class FaceSculptTool extends StatefulWidget {
  final img.Image? image;
  final Function(img.Image) onImageChanged;

  const FaceSculptTool({
    Key? key,
    this.image,
    required this.onImageChanged,
  }) : super(key: key);

  @override
  State<FaceSculptTool> createState() => _FaceSculptToolState();
}

class _FaceSculptToolState extends State<FaceSculptTool> {
  // Eye controls
  double _eyeSize = 0.0;
  double _eyeDistance = 0.0;
  double _eyeHeight = 0.0;

  // Nose controls
  double _noseWidth = 0.0;
  double _noseLength = 0.0;

  // Face shape controls
  double _jawWidth = 0.0;
  double _faceSlim = 0.0;
  double _chinShape = 0.0;

  // Lip controls
  double _lipFullness = 0.0;

  bool _isProcessing = false;

  /// Apply face sculpting transformations
  img.Image _applyFaceSculpt(img.Image source) {
    img.Image result = img.copy(source);

    // Create control points for different facial features
    // These would ideally be detected automatically via face detection
    // For now, we use approximate positions assuming a centered face
    
    final List<ControlPoint> controlPoints = [];
    final width = source.width.toDouble();
    final height = source.height.toDouble();

    // Eye enlargement (radial expansion from eye centers)
    if (_eyeSize != 0) {
      // Left eye center (approximate position)
      controlPoints.add(ControlPoint(
        position: math.Offset(0.35, 0.35),
        displacement: math.Offset(0, 0),
        radius: 0.15,
        strength: _eyeSize * 0.5,
        type: ControlPointType.expand,
      ));
      
      // Right eye center
      controlPoints.add(ControlPoint(
        position: math.Offset(0.65, 0.35),
        displacement: math.Offset(0, 0),
        radius: 0.15,
        strength: _eyeSize * 0.5,
        type: ControlPointType.expand,
      ));
    }

    // Eye distance adjustment
    if (_eyeDistance != 0) {
      controlPoints.add(ControlPoint(
        position: math.Offset(0.35, 0.35),
        displacement: math.Offset(-_eyeDistance * 0.1, 0),
        radius: 0.2,
        strength: 1.0,
        type: ControlPointType.move,
      ));
      
      controlPoints.add(ControlPoint(
        position: math.Offset(0.65, 0.35),
        displacement: math.Offset(_eyeDistance * 0.1, 0),
        radius: 0.2,
        strength: 1.0,
        type: ControlPointType.move,
      ));
    }

    // Nose narrowing
    if (_noseWidth != 0) {
      controlPoints.add(ControlPoint(
        position: math.Offset(0.5, 0.5),
        displacement: math.Offset(0, 0),
        radius: 0.12,
        strength: -_noseWidth * 0.4,
        type: ControlPointType.expand,
      ));
    }

    // Jaw width adjustment
    if (_jawWidth != 0) {
      controlPoints.add(ControlPoint(
        position: math.Offset(0.5, 0.75),
        displacement: math.Offset(0, 0),
        radius: 0.3,
        strength: _jawWidth * 0.3,
        type: ControlPointType.expand,
      ));
    }

    // Face slimming
    if (_faceSlim != 0) {
      controlPoints.add(ControlPoint(
        position: math.Offset(0.5, 0.5),
        displacement: math.Offset(0, 0),
        radius: 0.4,
        strength: -_faceSlim * 0.2,
        type: ControlPointType.expand,
      ));
    }

    // Apply warping using control points
    result = _warpImage(result, controlPoints);

    return result;
  }

  /// Warp image based on control points
  img.Image _warpImage(img.Image source, List<ControlPoint> controlPoints) {
    final width = source.width;
    final height = source.height;
    final output = img.copy(source);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final uv = math.Offset(x / width, y / height);
        math.Offset totalDisplacement = math.Offset.zero;

        for (final point in controlPoints) {
          final diff = uv - point.position;
          final distSq = diff.dx * diff.dx + diff.dy * diff.dy;
          final radiusSq = point.radius * point.radius;

          if (distSq < radiusSq) {
            final influence = math.exp(-distSq / (0.5 * radiusSq));
            
            if (point.type == ControlPointType.move) {
              totalDisplacement += point.displacement * influence * point.strength;
            } else if (point.type == ControlPointType.expand) {
              // Radial expansion/contraction
              final direction = diff.distance;
              if (direction > 0) {
                final radialDisp = direction * point.strength * influence;
                totalDisplacement += math.Offset(
                  diff.dx / direction * radialDisp,
                  diff.dy / direction * radialDisp,
                );
              }
            }
          }
        }

        // Sample from displaced coordinate
        final sourceUV = uv + totalDisplacement;
        final sourceX = (sourceUV.dx * width).clamp(0, width - 1).round();
        final sourceY = (sourceUV.dy * height).clamp(0, height - 1).round();

        final pixel = source.getPixel(sourceX, sourceY);
        output.setPixelRgba(x, y, 
          img.getRed(pixel),
          img.getGreen(pixel),
          img.getBlue(pixel),
          img.getAlpha(pixel),
        );
      }
    }

    return output;
  }

  void _applyChanges() async {
    if (widget.image == null || _isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final result = _applyFaceSculpt(widget.image!);
      widget.onImageChanged(result);
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _reset() {
    setState(() {
      _eyeSize = 0.0;
      _eyeDistance = 0.0;
      _eyeHeight = 0.0;
      _noseWidth = 0.0;
      _noseLength = 0.0;
      _jawWidth = 0.0;
      _faceSlim = 0.0;
      _chinShape = 0.0;
      _lipFullness = 0.0;
    });
    _applyChanges();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Eyes'),
          _buildSlider(
            label: 'Eye Size',
            value: _eyeSize,
            min: -1.0,
            max: 1.0,
            onChanged: (v) => setState(() => _eyeSize = v),
          ),
          _buildSlider(
            label: 'Eye Distance',
            value: _eyeDistance,
            min: -1.0,
            max: 1.0,
            onChanged: (v) => setState(() => _eyeDistance = v),
          ),
          _buildSlider(
            label: 'Eye Height',
            value: _eyeHeight,
            min: -1.0,
            max: 1.0,
            onChanged: (v) => setState(() => _eyeHeight = v),
          ),

          const SizedBox(height: 24),
          _buildSectionTitle('Nose'),
          _buildSlider(
            label: 'Nose Width',
            value: _noseWidth,
            min: -1.0,
            max: 1.0,
            onChanged: (v) => setState(() => _noseWidth = v),
          ),
          _buildSlider(
            label: 'Nose Length',
            value: _noseLength,
            min: -1.0,
            max: 1.0,
            onChanged: (v) => setState(() => _noseLength = v),
          ),

          const SizedBox(height: 24),
          _buildSectionTitle('Face Shape'),
          _buildSlider(
            label: 'Jaw Width',
            value: _jawWidth,
            min: -1.0,
            max: 1.0,
            onChanged: (v) => setState(() => _jawWidth = v),
          ),
          _buildSlider(
            label: 'Face Slim',
            value: _faceSlim,
            min: -1.0,
            max: 1.0,
            onChanged: (v) => setState(() => _faceSlim = v),
          ),
          _buildSlider(
            label: 'Chin Shape',
            value: _chinShape,
            min: -1.0,
            max: 1.0,
            onChanged: (v) => setState(() => _chinShape = v),
          ),

          const SizedBox(height: 24),
          _buildSectionTitle('Lips'),
          _buildSlider(
            label: 'Lip Fullness',
            value: _lipFullness,
            min: -1.0,
            max: 1.0,
            onChanged: (v) => setState(() => _lipFullness = v),
          ),

          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _reset,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reset'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _applyChanges,
                  icon: const Icon(Icons.check),
                  label: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text(
                value.toStringAsFixed(2),
                style: TextStyle(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: 100,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Control point types for face sculpting
enum ControlPointType {
  move,      // Move pixels in a direction
  expand,    // Expand/contract radially
}

/// Control point for face warping
class ControlPoint {
  final math.Offset position;
  final math.Offset displacement;
  final double radius;
  final double strength;
  final ControlPointType type;

  ControlPoint({
    required this.position,
    required this.displacement,
    required this.radius,
    required this.strength,
    this.type = ControlPointType.move,
  });
}
