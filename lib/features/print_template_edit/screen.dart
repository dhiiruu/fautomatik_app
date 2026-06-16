import 'package:flutter/material.dart';
import '../edit/screen.dart';
import '../edit/config.dart';
import '../edit/editor.dart';

class PrintTemplateEditScreen extends StatefulWidget {
  const PrintTemplateEditScreen({super.key});
  @override
  State<PrintTemplateEditScreen> createState() => _PrintTemplateEditScreenState();
}

class _PrintTemplateEditScreenState extends State<PrintTemplateEditScreen> with EditScreenMixin<PrintTemplateEditScreen> {
  @override
  FeatureConfig get config => FeatureConfig.all[13];

  @override
  Widget buildPreferences() => autoNotice();

  @override
  EditConfig buildEditConfig() {
    return const EditConfig(
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
