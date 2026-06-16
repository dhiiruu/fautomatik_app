import 'package:flutter/material.dart';
import '../edit/screen.dart';
import '../edit/config.dart';
import '../edit/editor.dart';

class BgColorScreen extends StatefulWidget {
  const BgColorScreen({super.key});
  @override
  State<BgColorScreen> createState() => _BgColorScreenState();
}

class _BgColorScreenState extends State<BgColorScreen> with EditScreenMixin<BgColorScreen> {
  int _bgColor = 0xFFFFFFFF;

  static const _colors = [0xFFFFFFFF, 0xFF000000, 0xFF7C4DFF, 0xFF2196F3, 0xFF4CAF50, 0xFFFF9800, 0xFFF44336, 0xFFE91E63, 0xFF9C27B0, 0xFF00BCD4, 0xFF8BC34A, 0xFFFFEB3B];

  @override
  FeatureConfig get config => FeatureConfig.all[9];

  @override
  Widget buildPreferences() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sectionHeader('Background Color'),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: _colors.map((c) {
        final selected = _bgColor == c;
        return GestureDetector(
          onTap: () => setState(() => _bgColor = c),
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: Color(c),
              shape: BoxShape.circle,
              border: Border.all(color: selected ? Colors.white : Colors.white24, width: selected ? 3 : 1),
              boxShadow: selected ? [BoxShadow(color: Colors.white.withValues(alpha: 0.3), blurRadius: 8)] : null,
            ),
            child: selected ? const Icon(Icons.check, color: Colors.black54, size: 18) : null,
          ),
        );
      }).toList()),
    ]);
  }

  @override
  EditConfig buildEditConfig() {
    return EditConfig(
      background: BackgroundConfig(color: _bgColor, maskThreshold: 0.5, featherRadius: 3),
      output: OutputConfig(format: 'png'),
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
