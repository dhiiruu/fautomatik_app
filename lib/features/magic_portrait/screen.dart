import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../edit/screen.dart';
import '../edit/config.dart';
import '../edit/editor.dart';

class MagicPortraitScreen extends StatefulWidget {
  const MagicPortraitScreen({super.key});
  @override
  State<MagicPortraitScreen> createState() => _MagicPortraitScreenState();
}

class _MagicPortraitScreenState extends State<MagicPortraitScreen> with EditScreenMixin<MagicPortraitScreen> {
  int _cropW = 1200;
  int _cropH = 1600;
  double _sharpenAmount = 0.5;
  double _smoothAmount = 0.3;
  final int _smoothRadius = 2;
  int _borderWidth = 15;
  int _jpgQuality = 95;

  @override
  FeatureConfig get config => FeatureConfig.all[0];

  @override
  bool get needsFace => true;

  @override
  Widget buildPreferences() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sectionHeader('Output Size'),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: buildPresetChips([
          PresetChip('4×6" (1200×1600)', () { setState(() { _cropW = 1200; _cropH = 1600; }); }, _cropW == 1200 && _cropH == 1600),
          PresetChip('5×7" (1500×2100)', () { setState(() { _cropW = 1500; _cropH = 2100; }); }, _cropW == 1500 && _cropH == 2100),
          PresetChip('Passport (600×600)', () { setState(() { _cropW = 600; _cropH = 600; }); }, _cropW == 600 && _cropH == 600),
        ])),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: labeledSlider('Sharpen', _sharpenAmount, 0, 1, (v) => setState(() => _sharpenAmount = v))),
        const SizedBox(width: 12),
        Expanded(child: labeledSlider('Smooth', _smoothAmount, 0, 1, (v) => setState(() => _smoothAmount = v))),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: labeledSlider('Quality', _jpgQuality.toDouble(), 10, 100, (v) => setState(() => _jpgQuality = v.round()))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Border Width', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 4),
            DropdownButtonFormField<int>(
              initialValue: _borderWidth,
              dropdownColor: AppTheme.surface,
              style: const TextStyle(color: Colors.white),
              decoration: inputDeco(),
              items: [0, 5, 10, 15, 20, 30].map((w) => DropdownMenuItem(value: w, child: Text('${w}px'))).toList(),
              onChanged: (v) { if (v != null) setState(() => _borderWidth = v); },
            ),
          ]),
        ),
      ]),
    ]);
  }

  @override
  EditConfig buildEditConfig() {
    return EditConfig(
      straighten: const StraightenConfig(),
      crop: CropConfig(outputWidth: _cropW, outputHeight: _cropH),
      resize: ResizeConfig(maintainAspect: true),
      lighting: const LightingConfig(autoLevels: true, brightness: 0.05, contrast: 0.05),
      sharpen: SharpenConfig(amount: _sharpenAmount),
      skinSmooth: SkinSmoothConfig(amount: _smoothAmount, radius: _smoothRadius),
      redEye: const RedEyeConfig(),
      border: BorderConfig(color: 0xFFFFFFFF, width: _borderWidth),
      output: OutputConfig(format: 'jpg', quality: _jpgQuality, dpi: 300),
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
