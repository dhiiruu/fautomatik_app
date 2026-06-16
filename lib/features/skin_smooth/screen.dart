import 'package:flutter/material.dart';
import '../edit/screen.dart';
import '../edit/config.dart';
import '../edit/editor.dart';

class SkinSmoothScreen extends StatefulWidget {
  const SkinSmoothScreen({super.key});
  @override
  State<SkinSmoothScreen> createState() => _SkinSmoothScreenState();
}

class _SkinSmoothScreenState extends State<SkinSmoothScreen> with EditScreenMixin<SkinSmoothScreen> {
  double _smoothAmount = 0.3;
  int _smoothRadius = 2;

  @override
  FeatureConfig get config => FeatureConfig.all[7];

  @override
  Widget buildPreferences() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sectionHeader('Skin Smooth Settings'),
      const SizedBox(height: 8),
      labeledSlider('Amount', _smoothAmount, 0, 1, (v) => setState(() => _smoothAmount = v)),
      const SizedBox(height: 12),
      labeledSlider('Radius', _smoothRadius.toDouble(), 1, 5, (v) => setState(() => _smoothRadius = v.round())),
    ]);
  }

  @override
  EditConfig buildEditConfig() {
    return EditConfig(
      skinSmooth: SkinSmoothConfig(amount: _smoothAmount, radius: _smoothRadius),
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
