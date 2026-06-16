import 'package:flutter/material.dart';
import '../edit/screen.dart';
import '../edit/config.dart';
import '../edit/editor.dart';

class CompressScreen extends StatefulWidget {
  const CompressScreen({super.key});
  @override
  State<CompressScreen> createState() => _CompressScreenState();
}

class _CompressScreenState extends State<CompressScreen> with EditScreenMixin<CompressScreen> {
  int _jpgQuality = 95;
  int _targetSizeKB = 500;

  @override
  FeatureConfig get config => FeatureConfig.all[3];

  @override
  Widget buildPreferences() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sectionHeader('Compression Settings'),
      const SizedBox(height: 8),
      labeledSlider('JPEG Quality', _jpgQuality.toDouble(), 10, 100, (v) => setState(() => _jpgQuality = v.round())),
      const SizedBox(height: 12),
      labeledInput('Target Size (KB)', _targetSizeKB.toString(), (v) {
        final n = int.tryParse(v); if (n != null && n > 0) setState(() => _targetSizeKB = n);
      }),
    ]);
  }

  @override
  EditConfig buildEditConfig() {
    return EditConfig(
      output: OutputConfig(format: 'jpg', quality: _jpgQuality, maxSizeKB: _targetSizeKB),
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
