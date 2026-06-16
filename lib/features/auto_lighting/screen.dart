import 'package:flutter/material.dart';
import '../edit/screen.dart';
import '../edit/config.dart';
import '../edit/editor.dart';

class AutoLightingScreen extends StatefulWidget {
  const AutoLightingScreen({super.key});
  @override
  State<AutoLightingScreen> createState() => _AutoLightingScreenState();
}

class _AutoLightingScreenState extends State<AutoLightingScreen> with EditScreenMixin<AutoLightingScreen> {
  @override
  FeatureConfig get config => FeatureConfig.all[5];

  @override
  Widget buildPreferences() => autoNotice();

  @override
  EditConfig buildEditConfig() {
    return const EditConfig(
      lighting: LightingConfig(autoLevels: true, brightness: 0.05, contrast: 0.05),
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
