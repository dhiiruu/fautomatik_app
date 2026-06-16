import 'package:flutter/material.dart';
import '../../core/app_theme.dart';

class GradientButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool filled;
  final bool loading;
  final Widget? child;

  const GradientButton({
    super.key,
    this.label,
    this.icon,
    this.onPressed,
    this.filled = true,
    this.loading = false,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final content = loading
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : (child ?? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
              Text(label!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ));

    if (filled) {
      return FilledButton(onPressed: loading ? null : onPressed, child: content);
    }
    return OutlinedButton(onPressed: loading ? null : onPressed, child: content);
  }
}

class IndicatorChip extends StatelessWidget {
  final String label;
  final bool ok;

  const IndicatorChip({super.key, required this.label, required this.ok});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: 1,
      duration: const Duration(milliseconds: 200),
      child: AnimatedOpacity(
        opacity: ok ? 0.6 : 1,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: ok ? AppTheme.success.withValues(alpha: 0.2) : AppTheme.error.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ok ? Icons.check : Icons.close, size: 11, color: ok ? AppTheme.success : Colors.white),
              const SizedBox(width: 3),
              Text(label, style: TextStyle(
                color: ok ? AppTheme.success : Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              )),
            ],
          ),
        ),
      ),
    );
  }
}

class CountdownPill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const CountdownPill({
    super.key,
    required this.text,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class EditActionBar extends StatelessWidget {
  final bool hasResult;
  final bool processing;
  final bool canApply;
  final VoidCallback? onSave;
  final VoidCallback? onPrint;
  final VoidCallback? onApply;

  const EditActionBar({
    super.key,
    required this.hasResult,
    this.processing = false,
    this.canApply = true,
    this.onSave,
    this.onPrint,
    this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasResult) {
      return SizedBox(
        width: double.infinity,
        child: GradientButton(
          loading: processing,
          onPressed: (processing || !canApply) ? null : onApply,
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.auto_fix_high, size: 18),
            SizedBox(width: 6),
            Text('Apply'),
          ]),
        ),
      );
    }

    return Row(children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: onSave,
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Save'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white24),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: GradientButton(
          onPressed: onPrint,
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.print, size: 18),
            SizedBox(width: 6),
            Text('Print'),
          ]),
        ),
      ),
    ]);
  }
}

class PageDots extends StatelessWidget {
  final int count;
  final int current;

  const PageDots({super.key, required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        width: i == current ? 20 : 8,
        height: 8,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: i == current ? AppTheme.primary : AppTheme.surfaceBorder,
        ),
      )),
    );
  }
}
