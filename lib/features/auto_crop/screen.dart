import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../edit/screen.dart';
import '../edit/config.dart';
import '../edit/editor.dart';

class AutoCropScreen extends StatefulWidget {
  const AutoCropScreen({super.key});
  @override
  State<AutoCropScreen> createState() => _AutoCropScreenState();
}

class _AutoCropScreenState extends State<AutoCropScreen> with EditScreenMixin<AutoCropScreen> {
  int _cropW = 1200;
  int _cropH = 1600;
  int _dpi = 300;
  int _jpgQuality = 95;
  String _unit = 'px';

  final _widthCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _dpiCtrl = TextEditingController(text: '300');

  @override
  void initState() {
    super.initState();
    _syncCtrls();
  }

  @override
  void dispose() {
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    _dpiCtrl.dispose();
    super.dispose();
  }

  void _syncCtrls() {
    switch (_unit) {
      case 'px':
        _widthCtrl.text = _cropW.toString();
        _heightCtrl.text = _cropH.toString();
      case 'in':
        _widthCtrl.text = (_cropW / _dpi).toStringAsFixed(1);
        _heightCtrl.text = (_cropH / _dpi).toStringAsFixed(1);
      case 'mm':
        _widthCtrl.text = (_cropW / _dpi * 25.4).toStringAsFixed(1);
        _heightCtrl.text = (_cropH / _dpi * 25.4).toStringAsFixed(1);
    }
  }

  void _onWidth(String v) {
    final n = double.tryParse(v);
    if (n == null || n <= 0) return;
    setState(() {
      switch (_unit) {
        case 'px':
          _cropW = n.round();
          break;
        case 'in':
          _cropW = (n * _dpi).round();
          break;
        case 'mm':
          _cropW = (n / 25.4 * _dpi).round();
          break;
      }
      _syncCtrls();
    });
  }

  void _onHeight(String v) {
    final n = double.tryParse(v);
    if (n == null || n <= 0) return;
    setState(() {
      switch (_unit) {
        case 'px':
          _cropH = n.round();
          break;
        case 'in':
          _cropH = (n * _dpi).round();
          break;
        case 'mm':
          _cropH = (n / 25.4 * _dpi).round();
          break;
      }
      _syncCtrls();
    });
  }

  void _onDpi(String v) {
    final n = int.tryParse(v);
    if (n == null || n <= 0) return;
    setState(() {
      _dpi = n;
      _syncCtrls();
    });
  }

  void _setPreset(int w, int h) {
    setState(() {
      _cropW = w;
      _cropH = h;
      _syncCtrls();
    });
  }

  @override
  FeatureConfig get config => FeatureConfig.all[2];

  @override
  bool get needsFace => true;

  @override
  Widget buildPreferences() {
    final srcInfo = sourceBytes != null
        ? 'Source: $sourceW×${sourceH}px · ${(sourceW / _dpi).toStringAsFixed(1)}×${(sourceH / _dpi).toStringAsFixed(1)}in · ${(sourceW / _dpi * 25.4).toStringAsFixed(1)}×${(sourceH / _dpi * 25.4).toStringAsFixed(1)}mm'
        : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sectionHeader('Crop Dimensions'),
      const SizedBox(height: 8),
      buildPresetChips([
        PresetChip('4×6"', () => _setPreset(1200, 1600), _cropW == 1200 && _cropH == 1600),
        PresetChip('5×7"', () => _setPreset(1500, 2100), _cropW == 1500 && _cropH == 2100),
        PresetChip('Passport', () => _setPreset(600, 600), _cropW == 600 && _cropH == 600),
        PresetChip('1:1', () => _setPreset(1200, 1200), _cropW == 1200 && _cropH == 1200),
      ]),
      const SizedBox(height: 8),
      // Unit selector
      Row(children: [
        _unitChip('px'),
        const SizedBox(width: 6),
        _unitChip('in'),
        const SizedBox(width: 6),
        _unitChip('mm'),
      ]),
      const SizedBox(height: 8),
      // Dimension inputs in active unit
      Row(children: [
        Expanded(child: _dimInput('Width ($_unit)', _widthCtrl, _onWidth)),
        const SizedBox(width: 12),
        Expanded(child: _dimInput('Height ($_unit)', _heightCtrl, _onHeight)),
      ]),
      // DPI (only relevant for physical units)
      if (_unit != 'px') ...[
        const SizedBox(height: 8),
        _dimInput('DPI', _dpiCtrl, _onDpi),
      ],
      // Source info
      if (srcInfo != null) ...[
        const SizedBox(height: 8),
        Text(srcInfo, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
      ],
      const SizedBox(height: 12),
      labeledSlider('JPEG Quality', _jpgQuality.toDouble(), 10, 100, (v) => setState(() => _jpgQuality = v.round())),
    ]);
  }

  Widget _unitChip(String value) {
    final selected = _unit == value;
    return ChoiceChip(
      label: Text(value, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _unit = value;
          _syncCtrls();
        });
      },
      selectedColor: AppTheme.primary.withValues(alpha: 0.3),
      backgroundColor: AppTheme.surface,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppTheme.textSecondary,
        fontSize: 12,
      ),
      side: BorderSide(color: selected ? AppTheme.primary : AppTheme.surfaceBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    );
  }

  Widget _dimInput(String label, TextEditingController ctrl, ValueChanged<String> onSubmitted) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      const SizedBox(height: 4),
      TextFormField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: inputDeco(),
        onFieldSubmitted: onSubmitted,
      ),
    ]);
  }

  @override
  EditConfig buildEditConfig() {
    return EditConfig(
      crop: CropConfig(outputWidth: _cropW, outputHeight: _cropH),
      output: OutputConfig(format: 'jpg', quality: _jpgQuality, dpi: _dpi.toDouble()),
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
