import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/app_theme.dart';
import '../../features/print_template/screen.dart';

class PhotoPreviewSheet extends StatelessWidget {
  final String photoPath;
  final VoidCallback onRetake;
  final String? editedPath;

  const PhotoPreviewSheet({
    super.key,
    required this.photoPath,
    required this.onRetake,
    this.editedPath,
  });

  @override
  Widget build(BuildContext context) {
    final displayPath = editedPath ?? photoPath;
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            // Handle
            Center(child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[700],
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            const SizedBox(height: 16),
            // Photo
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(File(displayPath), fit: BoxFit.contain, height: 280),
            ),
            const SizedBox(height: 20),
            // Info
            if (editedPath != null)
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_fix_high, size: 16, color: AppTheme.success),
                  SizedBox(width: 6),
                  Text('Enhanced', style: TextStyle(color: AppTheme.success, fontSize: 13)),
                ],
              ),
            const SizedBox(height: 20),
            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () { HapticFeedback.lightImpact(); onRetake(); },
                    icon: const Icon(Icons.replay, size: 18),
                    label: const Text('Retake'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () {
                      HapticFeedback.heavyImpact();
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => TemplatePrintScreen(photos: [File(displayPath).readAsBytesSync()]),
                      ));
                    },
                    icon: const Icon(Icons.dashboard, size: 18),
                    label: const Text('Layout & Print'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
