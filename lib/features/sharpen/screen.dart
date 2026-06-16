import 'package:flutter/material.dart';
import '../edit/screen.dart';
import '../edit/config.dart';
import '../edit/editor.dart';

class SharpenScreen extends StatefulWidget {
  const SharpenScreen({super.key});
  @override
  State<SharpenScreen> createState() => _SharpenScreenState();
}

class _SharpenScreenState extends State<SharpenScreen> with EditScreenMixin<SharpenScreen> {
  double _sharpenAmount = 0.5;

  @override
  FeatureConfig get config => FeatureConfig.all[6];

  @override
  Widget buildPreferences() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sectionHeader('Sharpen Amount'),
      const SizedBox(height: 8),
      labeledSlider('Amount', _sharpenAmount, 0, 1, (v) => setState(() => _sharpenAmount = v)),
    ]);
  }

  @override
  EditConfig buildEditConfig() {
    return EditConfig(
      sharpen: SharpenConfig(amount: _sharpenAmount),
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
