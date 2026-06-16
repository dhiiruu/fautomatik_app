import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../edit/screen.dart';
import '../edit/config.dart';
import '../edit/editor.dart';

class ConvertFormatScreen extends StatefulWidget {
  const ConvertFormatScreen({super.key});
  @override
  State<ConvertFormatScreen> createState() => _ConvertFormatScreenState();
}

class _ConvertFormatScreenState extends State<ConvertFormatScreen> with EditScreenMixin<ConvertFormatScreen> {
  String _outputFormat = 'jpg';

  @override
  FeatureConfig get config => FeatureConfig.all[12];

  Widget _formatOption(String label, String value, IconData icon) {
    final selected = _outputFormat == value;
    return GestureDetector(
      onTap: () => setState(() => _outputFormat = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary.withValues(alpha: 0.15) : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppTheme.primary : AppTheme.surfaceBorder, width: selected ? 2 : 1),
        ),
        child: Column(children: [
          Icon(icon, color: selected ? AppTheme.primary : AppTheme.textSecondary, size: 28),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(
            color: selected ? AppTheme.primary : AppTheme.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13,
          )),
        ]),
      ),
    );
  }

  @override
  Widget buildPreferences() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sectionHeader('Output Format'),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _formatOption('JPG', 'jpg', Icons.image)),
        const SizedBox(width: 12),
        Expanded(child: _formatOption('PNG', 'png', Icons.image_outlined)),
        const SizedBox(width: 12),
        Expanded(child: _formatOption('WEBP', 'webp', Icons.web)),
      ]),
    ]);
  }

  @override
  EditConfig buildEditConfig() {
    return EditConfig(
      output: OutputConfig(format: _outputFormat),
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
