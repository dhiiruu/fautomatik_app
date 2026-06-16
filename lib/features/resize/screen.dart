import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../edit/screen.dart';
import '../edit/config.dart';
import '../edit/editor.dart';

class ResizeScreen extends StatefulWidget {
  const ResizeScreen({super.key});
  @override
  State<ResizeScreen> createState() => _ResizeScreenState();
}

class _ResizeScreenState extends State<ResizeScreen> with EditScreenMixin<ResizeScreen> {
  int _resizeW = 1200;

  @override
  FeatureConfig get config => FeatureConfig.all[11];

  @override
  Widget buildPreferences() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sectionHeader('Output Width'),
      const SizedBox(height: 8),
      labeledInput('Width (px)', _resizeW.toString(), (v) {
        final n = int.tryParse(v); if (n != null && n > 0) setState(() => _resizeW = n);
      }),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.surfaceBorder),
        ),
        child: const Row(children: [
          Icon(Icons.info_outline, color: AppTheme.textSecondary, size: 16),
          SizedBox(width: 8),
          Expanded(child: Text('Height will be calculated automatically to maintain aspect ratio.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12))),
        ]),
      ),
    ]);
  }

  @override
  EditConfig buildEditConfig() {
    return EditConfig(
      resize: ResizeConfig(width: _resizeW, maintainAspect: true),
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
