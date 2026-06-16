import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'template_engine.dart';
import 'pdf_exporter.dart';
import '../../core/app_theme.dart';
import '../../shared/widgets/app_widgets.dart';

class _PaperPreset {
  final String name;
  final double wMm;
  final double hMm;
  const _PaperPreset(this.name, this.wMm, this.hMm);
}

const _paperPresets = [
  _PaperPreset('4×6″', 101.6, 152.4),
  _PaperPreset('5×7″', 127, 177.8),
  _PaperPreset('6×8″', 152.4, 203.2),
  _PaperPreset('A4', 210, 297),
  _PaperPreset('A5', 148, 210),
];

class _PhotoSizePreset {
  final String name;
  final double wMm;
  final double hMm;
  const _PhotoSizePreset(this.name, this.wMm, this.hMm);
}

const _photoSizePresets = [
  _PhotoSizePreset('2×3″ (wallet)', 50.8, 76.2),
  _PhotoSizePreset('3.5×5″', 88.9, 127),
  _PhotoSizePreset('4×6″', 101.6, 152.4),
  _PhotoSizePreset('5×7″', 127, 177.8),
];

class TemplatePrintScreen extends StatefulWidget {
  final List<Uint8List> photos;
  const TemplatePrintScreen({super.key, required this.photos});

  @override
  State<TemplatePrintScreen> createState() => _TemplatePrintScreenState();
}

class _TemplatePrintScreenState extends State<TemplatePrintScreen> {
  final TemplateEngine _engine = TemplateEngine();
  final PdfExporter _pdfExporter = PdfExporter();

  _PaperPreset _paper = _paperPresets[0];
  _PhotoSizePreset _photoSize = _photoSizePresets[0];
  double _dpi = 300;
  double _spacingMm = 3;
  double _marginMm = 10;
  bool _cropMarks = false;
  bool _generating = false;
  bool _showSettings = true;

  TemplateResult? _previewResult;

  @override
  void initState() {
    super.initState();
    _generatePreview();
  }

  TemplateConfig _buildConfig() => TemplateConfig(
    dpi: _dpi, paperWidthMm: _paper.wMm, paperHeightMm: _paper.hMm,
    photoWidthMm: _photoSize.wMm, photoHeightMm: _photoSize.hMm,
    spacingMm: _spacingMm, marginTopMm: _marginMm, marginBottomMm: _marginMm,
    marginLeftMm: _marginMm, marginRightMm: _marginMm, cropMarks: _cropMarks,
  );

  void _generatePreview() {
    final result = _engine.place(photos: widget.photos, config: _buildConfig());
    if (mounted) setState(() => _previewResult = result);
  }

  Future<Uint8List> _generatePdf(TemplateConfig? config) async {
    config ??= _buildConfig();
    return _pdfExporter.export(templateResult: _engine.place(photos: widget.photos, config: config), config: config);
  }

  Future<void> _print() async {
    HapticFeedback.mediumImpact();
    setState(() => _generating = true);
    try {
      await Printing.layoutPdf(onLayout: (format) => _generatePdf(_buildConfig()), name: 'Fautomatik Photo Print');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _savePdf() async {
    HapticFeedback.mediumImpact();
    setState(() => _generating = true);
    try {
      final pdfBytes = await _generatePdf(null);
      await Printing.sharePdf(bytes: pdfBytes, filename: 'fautomatik_${DateTime.now().millisecondsSinceEpoch}.pdf');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
      child: Column(children: [
        // Top bar
        Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8, left: 16, right: 16, bottom: 8),
          child: Row(children: [
            Container(
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), shape: BoxShape.circle),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                onPressed: () { HapticFeedback.lightImpact(); Navigator.pop(context); },
                padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
            ),
            const SizedBox(width: 12),
            const Text('Print Layout', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            const Spacer(),
            if (_generating)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            if (!_generating)
              Container(
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), shape: BoxShape.circle),
                child: IconButton(
                  icon: Icon(_showSettings ? Icons.tune : Icons.tune, color: _showSettings ? AppTheme.primary : Colors.white54, size: 22),
                  onPressed: () { HapticFeedback.lightImpact(); setState(() => _showSettings = !_showSettings); },
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
              ),
          ]),
        ),

        // Preview
        Expanded(
          child: _previewResult == null || _previewResult!.pages.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.image_not_supported, size: 48, color: Colors.grey[700]),
                  const SizedBox(height: 12),
                  const Text('No photos to arrange', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                ]),
              )
            : Column(children: [
                Expanded(
                  child: PageView.builder(
                    itemCount: _previewResult!.totalPages,
                    itemBuilder: (ctx, i) => Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(_previewResult!.pages[i], fit: BoxFit.contain),
                      )),
                    ),
                  ),
                ),
                if (_previewResult!.totalPages > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: PageDots(count: _previewResult!.totalPages, current: 0),
                  ),
              ]),
        ),

        // Settings panel
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: _showSettings ? _buildSettingsPanel() : const SizedBox.shrink(),
        ),
      ]),
    ),
  );

  Widget _buildSettingsPanel() => Container(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      // Handle
      Center(child: Container(width: 36, height: 4,
        decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(2)),
      )),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _label('Paper')),
        Expanded(flex: 2, child: _dropdown<_PaperPreset>(value: _paper, items: _paperPresets,
          label: (p) => p.name, onChanged: (v) { _paper = v; _generatePreview(); })),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: _label('Photo')),
        Expanded(flex: 2, child: _dropdown<_PhotoSizePreset>(value: _photoSize, items: _photoSizePresets,
          label: (p) => p.name, onChanged: (v) { _photoSize = v; _generatePreview(); })),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: _label('DPI')),
        Expanded(flex: 2, child: _dpiDropdown()),
      ]),
      const SizedBox(height: 4),
      _sliderRow('Spacing', _spacingMm, 0, 10, (v) { _spacingMm = v; _generatePreview(); }),
      const SizedBox(height: 4),
      _sliderRow('Margin', _marginMm, 3, 20, (v) { _marginMm = v; _generatePreview(); }),
      const SizedBox(height: 2),
      Row(children: [
        Expanded(child: _label('Crop marks')),
        Switch(value: _cropMarks, onChanged: (v) { HapticFeedback.lightImpact(); setState(() => _cropMarks = v); _generatePreview(); },
          activeThumbColor: AppTheme.primary),
        const SizedBox(width: 60),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _generating ? null : _savePdf,
            icon: const Icon(Icons.save_alt, size: 18),
            label: const Text('Save PDF'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GradientButton(
            onPressed: _generating ? null : _print,
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.print, size: 18), SizedBox(width: 6), Text('Print'),
            ]),
          ),
        ),
      ]),
    ]),
  );

  Widget _label(String t) => Text(t, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13));

  Widget _sliderRow(String label, double val, double min, double max, void Function(double) onChange) => Row(children: [
    Expanded(child: _label(label)),
    Expanded(
      flex: 2,
      child: SliderTheme(
        data: SliderThemeData(
          activeTrackColor: AppTheme.primary, inactiveTrackColor: Colors.white12,
          thumbColor: AppTheme.primary, overlayColor: AppTheme.primary.withValues(alpha: 0.12),
          valueIndicatorColor: AppTheme.primary, valueIndicatorTextStyle: const TextStyle(color: Colors.white),
        ),
        child: Slider(value: val, min: min, max: max, divisions: ((max - min) * 2).round(),
          label: '${val.round()}mm', onChanged: (v) { setState(() => onChange(v)); }),
      ),
    ),
  ]);

  Widget _dropdown<T>({required T value, required List<T> items, required String Function(T) label, required void Function(T) onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: DropdownButton<T>(
        value: value, isDense: true, isExpanded: true, underline: const SizedBox(),
        dropdownColor: AppTheme.surfaceDark,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        icon: const Icon(Icons.expand_more, color: Colors.white54, size: 18),
        items: items.map((p) => DropdownMenuItem(value: p, child: Text(label(p)))).toList(),
        onChanged: (v) { if (v != null) { HapticFeedback.lightImpact(); onChanged(v); } },
      ),
    );
  }

  Widget _dpiDropdown() {
    const dpiValues = [72, 150, 200, 300, 600, 1200];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: DropdownButton<double>(
        value: _dpi, isDense: true, isExpanded: true, underline: const SizedBox(),
        dropdownColor: AppTheme.surfaceDark,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        icon: const Icon(Icons.expand_more, color: Colors.white54, size: 18),
        items: dpiValues.map((d) => DropdownMenuItem(value: d.toDouble(), child: Text('$d DPI'))).toList(),
        onChanged: (v) { if (v != null) { HapticFeedback.lightImpact(); setState(() => _dpi = v); _generatePreview(); } },
      ),
    );
  }
}
