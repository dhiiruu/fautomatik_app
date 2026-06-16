import 'package:flutter/material.dart';
import '../edit/screen.dart';
import '../edit/config.dart';
import '../edit/editor.dart';

class RedEyeFixScreen extends StatefulWidget {
  const RedEyeFixScreen({super.key});
  @override
  State<RedEyeFixScreen> createState() => _RedEyeFixScreenState();
}

class _RedEyeFixScreenState extends State<RedEyeFixScreen> with EditScreenMixin<RedEyeFixScreen> {
  @override
  FeatureConfig get config => FeatureConfig.all[8];

  @override
  bool get needsFace => true;

  @override
  Widget buildPreferences() => autoNotice();

  @override
  EditConfig buildEditConfig() {
    return const EditConfig(
      redEye: RedEyeConfig(),
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
