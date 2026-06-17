import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import '../../core/algorithms/light_estimation.dart';

/// Lighting Control Widget
/// Allows users to estimate light source from image and manually adjust lighting
class LightingControl extends StatefulWidget {
  final img.Image? image;
  final Function(img.Image) onImageChanged;

  const LightingControl({
    Key? key,
    this.image,
    required this.onImageChanged,
  }) : super(key: key);

  @override
  State<LightingControl> createState() => _LightingControlState();
}

class _LightingControlState extends State<LightingControl> {
  Offset _lightDirection = const Offset(0.3, -0.5); // Default: top-right
  double _lightIntensity = 0.5;
  bool _isProcessing = false;
  bool _autoDetected = false;

  /// Estimate light source from image automatically
  Future<void> _estimateLightSource() async {
    if (widget.image == null || _isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      // Run light estimation algorithm
      final estimatedDir = LightSourceEstimator.estimate(widget.image!);
      
      setState(() {
        _lightDirection = estimatedDir;
        _autoDetected = true;
      });

      // Apply the estimated lighting
      _applyLighting();
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  /// Apply lighting effect to image
  void _applyLighting() async {
    if (widget.image == null || _isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final result = LightSourceEstimator.applyDynamicLighting(
        widget.image!,
        _lightDirection,
        _lightIntensity,
      );
      widget.onImageChanged(result);
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _reset() {
    setState(() {
      _lightDirection = const Offset(0.3, -0.5);
      _lightIntensity = 0.5;
      _autoDetected = false;
    });
    _applyLighting();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Auto-detect button
          Card(
            child: ListTile(
              leading: const Icon(Icons.lightbulb_outline),
              title: const Text('Auto-Detect Light Source'),
              subtitle: Text(
                _autoDetected 
                  ? 'Light source detected from image' 
                  : 'Analyze image to find lighting direction',
              ),
              trailing: _isProcessing 
                ? const CircularProgressIndicator() 
                : IconButton(
                    icon: const Icon(Icons.auto_fix_high),
                    onPressed: _estimateLightSource,
                  ),
            ),
          ),

          const SizedBox(height: 24),

          // Light direction visualization
          _buildDirectionPicker(),

          const SizedBox(height: 24),

          // Light intensity slider
          _buildSlider(
            label: 'Light Intensity',
            value: _lightIntensity,
            min: 0.0,
            max: 1.0,
            onChanged: (v) => setState(() => _lightIntensity = v),
          ),

          // Direction info
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Horizontal: ${_lightDirection.dx.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'Vertical: ${_lightDirection.dy.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Action buttons
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
                  onPressed: _isProcessing ? null : _applyLighting,
                  icon: const Icon(Icons.check),
                  label: const Text('Apply'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Info card
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, 
                        size: 20, 
                        color: Colors.blue.shade700,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'How it works',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The algorithm analyzes brightness gradients in your image to determine the primary light source direction. Positive X = light from right, Positive Y = light from bottom.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.blue.shade900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Interactive light direction picker
  Widget _buildDirectionPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Light Direction',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: GestureDetector(
            onPanUpdate: (details) {
              final renderBox = context.findRenderObject() as RenderBox;
              final size = renderBox.size;
              
              // Convert to normalized coordinates (-1 to 1)
              final x = ((details.localPosition.dx / size.width) - 0.5) * 2;
              final y = ((details.localPosition.dy / size.height) - 0.5) * 2;
              
              // Clamp to unit circle
              final magnitude = math.sqrt(x * x + y * y);
              if (magnitude > 1) {
                setState(() {
                  _lightDirection = Offset(x / magnitude, y / magnitude);
                });
              } else {
                setState(() {
                  _lightDirection = Offset(x, y);
                });
              }
            },
            onTapUp: (details) => _applyLighting(),
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade300, width: 2),
                gradient: RadialGradient(
                  colors: [
                    Colors.yellow.shade100,
                    Colors.orange.shade50,
                    Colors.white,
                  ],
                  center: Alignment(
                    -_lightDirection.dx,
                    -_lightDirection.dy,
                  ),
                  radius: 1.5,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Crosshair lines
                  CustomPaint(
                    size: const Size(200, 200),
                    painter: _CrosshairPainter(),
                  ),
                  // Direction indicator
                  Center(
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Arrow showing direction
                  CustomPaint(
                    size: const Size(200, 200),
                    painter: _DirectionArrowPainter(_lightDirection),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Drag to adjust light direction',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
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

/// Painter for crosshair lines
class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;

    final center = Offset(size.width / 2, size.height / 2);

    // Vertical line
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      paint,
    );

    // Horizontal line
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Painter for direction arrow
class _DirectionArrowPainter extends CustomPainter {
  final Offset direction;

  _DirectionArrowPainter(this.direction);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.orange.shade700
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final arrowLength = size.width * 0.3;
    
    final end = center + Offset(
      direction.dx * arrowLength,
      direction.dy * arrowLength,
    );

    // Draw arrow line
    canvas.drawLine(center, end, paint);

    // Draw arrowhead
    final arrowHeadPaint = Paint()..color = Colors.orange.shade700;
    final headSize = 8.0;
    final angle = math.atan2(direction.dy, direction.dx);
    
    canvas.drawPath(
      Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(
          end.dx - headSize * math.cos(angle - math.pi / 6),
          end.dy - headSize * math.sin(angle - math.pi / 6),
        )
        ..lineTo(
          end.dx - headSize * math.cos(angle + math.pi / 6),
          end.dy - headSize * math.sin(angle + math.pi / 6),
        )
        ..close(),
      arrowHeadPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _DirectionArrowPainter oldDelegate) {
    return oldDelegate.direction != direction;
  }
}
