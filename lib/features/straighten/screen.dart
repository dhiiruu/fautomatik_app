import 'package:flutter/material.dart';
import '../edit/screen.dart';
import '../edit/config.dart';
import '../edit/editor.dart';

class StraightenScreen extends StatefulWidget {
  const StraightenScreen({super.key});
  @override
  State<StraightenScreen> createState() => _StraightenScreenState();
}

class _StraightenScreenState extends State<StraightenScreen> with EditScreenMixin<StraightenScreen> {
  @override
  FeatureConfig get config => FeatureConfig.all[4];

  @override
  bool get needsFace => true;

  @override
  Widget buildPreferences() => autoNotice();

  @override
  EditConfig buildEditConfig() {
    return const EditConfig(
      straighten: StraightenConfig(),
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
