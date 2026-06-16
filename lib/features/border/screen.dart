import 'package:flutter/material.dart';
import '../edit/screen.dart';
import '../edit/config.dart';
import '../edit/editor.dart';

class BorderScreen extends StatefulWidget {
  const BorderScreen({super.key});
  @override
  State<BorderScreen> createState() => _BorderScreenState();
}

class _BorderScreenState extends State<BorderScreen> with EditScreenMixin<BorderScreen> {
  int _borderColor = 0xFFFFFFFF;
  int _borderWidth = 15;

  static const _colors = [0xFFFFFFFF, 0xFF000000, 0xFF7C4DFF, 0xFF2196F3, 0xFF4CAF50, 0xFFFF9800, 0xFFF44336, 0xFFE91E63];

  @override
  FeatureConfig get config => FeatureConfig.all[10];

  @override
  Widget buildPreferences() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sectionHeader('Border Color'),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: _colors.map((c) {
        final selected = _borderColor == c;
        return GestureDetector(
          onTap: () => setState(() => _borderColor = c),
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: Color(c),
              shape: BoxShape.circle,
              border: Border.all(color: selected ? Colors.white : Colors.white24, width: selected ? 3 : 1),
            ),
            child: selected ? const Icon(Icons.check, color: Colors.black54, size: 16) : null,
          ),
        );
      }).toList()),
      const SizedBox(height: 16),
      sectionHeader('Border Width'),
      const SizedBox(height: 8),
      labeledSlider('Width', _borderWidth.toDouble(), 1, 50, (v) => setState(() => _borderWidth = v.round())),
    ]);
  }

  @override
  EditConfig buildEditConfig() {
    return EditConfig(
      border: BorderConfig(color: _borderColor, width: _borderWidth),
      output: OutputConfig(format: 'jpg', quality: 95),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(config.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: buildBody(),
    );
  }
}
