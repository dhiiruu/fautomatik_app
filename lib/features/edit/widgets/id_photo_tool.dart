import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// ID/Formal Photo Editing Tool
/// Provides background replacement, crop sizing, borders, and layout options
class IdPhotoTool extends StatefulWidget {
  const IdPhotoTool({super.key});

  @override
  State<IdPhotoTool> createState() => _IdPhotoToolState();
}

class _IdPhotoToolState extends State<IdPhotoTool> {
  // Background settings
  Color _bgColor = const Color(0xFF4A90D9); // Standard passport blue
  bool _useCustomBg = false;
  
  // Crop/Size settings
  String _selectedSize = '2x2 inch (600x600)';
  final Map<String, Size> _standardSizes = {
    '2x2 inch (600x600)': const Size(600, 600),
    '3.5x4.5 cm (413x531)': const Size(413, 531),
    '2x3 inch (600x900)': const Size(600, 900),
    '35x45 mm (413x531)': const Size(413, 531),
    '50x50 mm (590x590)': const Size(590, 590),
    'Custom': const Size(600, 600),
  };
  
  double _customWidth = 600;
  double _customHeight = 600;
  
  // Border settings
  double _borderWidth = 0;
  Color _borderColor = Colors.white;
  
  // Layout for printing
  int _layoutRows = 4;
  int _layoutCols = 3;
  double _spacing = 10;
  
  // Head size ratio (for compliance)
  double _headHeightRatio = 0.7; // 70% of photo height
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'ID/Formal Photo',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Background Section
                _buildSectionTitle('Background'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildColorChip(const Color(0xFF4A90D9), 'Blue'),
                    _buildColorChip(const Color(0xFFF5F5F5), 'White'),
                    _buildColorChip(const Color(0xFF8B0000), 'Red'),
                    _buildColorChip(const Color(0xFF4A7C59), 'Green'),
                    _buildColorChip(Colors.transparent, 'Custom', isCustom: true),
                  ],
                ),
                if (_useCustomBg) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Color:', style: TextStyle(color: Colors.white70)),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _pickCustomColor(),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _bgColor,
                            border: Border.all(color: Colors.white30),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                
                const SizedBox(height: 24),
                
                // Size/Crop Section
                _buildSectionTitle('Photo Size'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedSize,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.grey[800],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  dropdownColor: Colors.grey[850],
                  style: const TextStyle(color: Colors.white),
                  items: _standardSizes.keys.map((size) {
                    return DropdownMenuItem(value: size, child: Text(size));
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _selectedSize = value!);
                  },
                ),
                
                if (_selectedSize == 'Custom') ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildNumberField('Width', _customWidth, (v) => setState(() => _customWidth = v)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildNumberField('Height', _customHeight, (v) => setState(() => _customHeight = v)),
                      ),
                    ],
                  ),
                ],
                
                const SizedBox(height: 12),
                _buildSlider(
                  'Head Height Ratio',
                  _headHeightRatio,
                  0.5,
                  0.9,
                  (v) => setState(() => _headHeightRatio = v),
                  suffix: '%',
                  multiplier: 100,
                ),
                
                const SizedBox(height: 24),
                
                // Border Section
                _buildSectionTitle('Border'),
                const SizedBox(height: 12),
                _buildSlider(
                  'Width',
                  _borderWidth,
                  0,
                  50,
                  (v) => setState(() => _borderWidth = v),
                  suffix: 'px',
                ),
                if (_borderWidth > 0) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Color:', style: TextStyle(color: Colors.white70)),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _pickBorderColor(),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _borderColor,
                            border: Border.all(color: Colors.white30),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                
                const SizedBox(height: 24),
                
                // Layout Section
                _buildSectionTitle('Print Layout'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildNumberField('Rows', _layoutRows.toDouble(), (v) => setState(() => _layoutRows = v.toInt()))),
                    const SizedBox(width: 12),
                    Expanded(child: _buildNumberField('Columns', _layoutCols.toDouble(), (v) => setState(() => _layoutCols = v.toInt()))),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSlider(
                  'Spacing',
                  _spacing,
                  0,
                  50,
                  (v) => setState(() => _spacing = v),
                  suffix: 'px',
                ),
                
                const SizedBox(height: 24),
                
                // Info card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[900]?.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[700] ?? Colors.blue),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[300], size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Standard passport photos require 70-80% head height ratio with plain background.',
                          style: TextStyle(color: Colors.blue[200], fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Apply Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _applyEdits,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Apply ID Photo Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildColorChip(Color color, String label, {bool isCustom = false}) {
    return GestureDetector(
      onTap: () {
        if (isCustom) {
          setState(() => _useCustomBg = !_useCustomBg);
        } else {
          setState(() {
            _bgColor = color;
            _useCustomBg = false;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isCustom ? Colors.grey[800] : color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: (!isCustom && color == _bgColor && !_useCustomBg) 
                ? Colors.white 
                : (isCustom && _useCustomBg) 
                    ? Colors.blue 
                    : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isCustom)
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white30),
                ),
              ),
            if (!isCustom) const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isCustom ? Colors.white : (color.computeLuminance() > 0.5 ? Colors.black : Colors.white),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, ValueChanged<double> onChanged, {String suffix = '', double multiplier = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text(
              '${(value * multiplier).toStringAsFixed(multiplier == 1 ? 0 : 1)}$suffix',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            activeTrackColor: Colors.blue,
            inactiveTrackColor: Colors.grey[700],
            thumbColor: Colors.blue,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: (max - min).toInt(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildNumberField(String label, double value, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 4),
        TextField(
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey[800],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          controller: TextEditingController(text: value.toStringAsFixed(0)),
          onChanged: (v) {
            final num = double.tryParse(v);
            if (num != null) onChanged(num);
          },
        ),
      ],
    );
  }

  Future<void> _pickCustomColor() async {
    final color = await showDialog<Color>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[900],
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Pick Background Color', style: TextStyle(color: Colors.white)),
            const SizedBox(height: 20),
            // Simple color picker grid
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Colors.red, Colors.pink, Colors.purple, Colors.deepPurple,
                Colors.indigo, Colors.blue, Colors.lightBlue, Colors.cyan,
                Colors.teal, Colors.green, Colors.lightGreen, Colors.lime,
                Colors.yellow, Colors.amber, Colors.orange, Colors.deepOrange,
                Colors.brown, Colors.grey, Colors.blueGrey, Colors.white,
              ].map((c) {
                return GestureDetector(
                  onTap: () => Navigator.pop(context, c),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white30),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
    if (color != null) setState(() => _bgColor = color);
  }

  Future<void> _pickBorderColor() async {
    final color = await showDialog<Color>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[900],
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Pick Border Color', style: TextStyle(color: Colors.white)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Colors.white, Colors.black, Colors.red, Colors.blue,
                Colors.green, Colors.yellow, Colors.orange, Colors.purple,
              ].map((c) {
                return GestureDetector(
                  onTap: () => Navigator.pop(context, c),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white30),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
    if (color != null) setState(() => _borderColor = color);
  }

  void _applyEdits() {
    // TODO: Apply ID photo edits using the configured settings
    // This would involve:
    // 1. Background removal/replacement
    // 2. Cropping to selected dimensions
    // 3. Adding border if specified
    // 4. Preparing layout for printing
    
    Navigator.pop(context);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Applying ID photo settings: ${_selectedSize}, BG: ${_bgColor}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// Applies ID photo transformations to an image
class IdPhotoProcessor {
  final Color backgroundColor;
  final Size outputSize;
  final double borderWidth;
  final Color borderColor;
  final double headHeightRatio;
  
  const IdPhotoProcessor({
    required this.backgroundColor,
    required this.outputSize,
    this.borderWidth = 0,
    this.borderColor = Colors.white,
    this.headHeightRatio = 0.7,
  });
  
  /// Process image for ID photo
  Future<Uint8List> process(Uint8List inputBytes, int inputWidth, int inputHeight) async {
    final image = img.decodeImage(inputBytes);
    if (image == null) throw Exception('Failed to decode image');
    
    // 1. Remove background (placeholder - would use actual bg removal)
    // final noBg = await _removeBackground(image);
    
    // 2. Resize/crop to target dimensions
    final resized = img.copyResize(
      image,
      width: outputSize.width.toInt(),
      height: outputSize.height.toInt(),
    );
    
    // 3. Create canvas with background color
    final canvas = img.Image(
      width: outputSize.width.toInt() + borderWidth * 2,
      height: outputSize.height.toInt() + borderWidth * 2,
    );
    
    // Fill with background color
    img.fill(canvas, color: img.ColorInt.fromRgba(
      backgroundColor.red,
      backgroundColor.green,
      backgroundColor.blue,
      255,
    ));
    
    // 4. Draw border if specified
    if (borderWidth > 0) {
      img.drawRect(canvas,
        x: 0, y: 0,
        width: canvas.width,
        height: canvas.height,
        color: img.ColorInt.fromRgba(
          borderColor.red,
          borderColor.green,
          borderColor.blue,
          255,
        ),
        thickness: borderWidth.toInt(),
      );
    }
    
    // 5. Composite the photo onto the canvas
    img.compositeImage(
      canvas,
      resized,
      dstX: borderWidth.toInt(),
      dstY: borderWidth.toInt(),
    );
    
    // 6. Encode to PNG
    final encoded = img.encodePng(canvas);
    return Uint8List.fromList(encoded);
  }
  
  /// Generate print layout with multiple copies
  Future<Uint8List> generateLayout(Uint8List photoBytes, int rows, int cols, double spacing) async {
    final photo = img.decodeImage(photoBytes);
    if (photo == null) throw Exception('Failed to decode photo');
    
    final layoutWidth = (photo.width * cols) + (spacing * (cols - 1)).toInt();
    final layoutHeight = (photo.height * rows) + (spacing * (rows - 1)).toInt();
    
    final layout = img.Image(width: layoutWidth, height: layoutHeight);
    
    // Fill with white background
    img.fill(layout, color: img.ColorInt.fromRgba(255, 255, 255, 255));
    
    // Place photos in grid
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final x = (col * photo.width) + (spacing * col).toInt();
        final y = (row * photo.height) + (spacing * row).toInt();
        
        img.compositeImage(layout, photo, dstX: x, dstY: y);
      }
    }
    
    final encoded = img.encodePng(layout);
    return Uint8List.fromList(encoded);
  }
}
