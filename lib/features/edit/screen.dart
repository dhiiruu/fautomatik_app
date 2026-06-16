import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import '../../core/types.dart';
import '../../shared/face/face_pipeline.dart';
import '../../core/app_theme.dart';
import '../../shared/widgets/app_widgets.dart';
import 'editor.dart';
import 'config.dart';
import '../print_template/screen.dart';

mixin EditScreenMixin<T extends StatefulWidget> on State<T> {
  final ImagePicker _picker = ImagePicker();
  final PhotoEditor editor = PhotoEditor();
  final MediaPipeFacePipeline _facePipeline = MediaPipeFacePipeline();

  Uint8List? sourceBytes;
  int sourceW = 0;
  int sourceH = 0;
  Uint8List? resultBytes;
  bool processing = false;
  bool pipelineLoading = true;
  String error = '';
  bool navigating = false;

  FeatureConfig get config;
  bool get needsFace => false;
  EditConfig buildEditConfig();
  Widget buildPreferences();

  @override
  void initState() {
    super.initState();
    if (needsFace) _loadFacePipeline();
  }

  @override
  void dispose() {
    _facePipeline.dispose();
    super.dispose();
  }

  Future<void> _loadFacePipeline() async {
    try {
      await _facePipeline.load();
    } catch (e) {
      debugPrint('Face pipeline load failed: $e');
    }
    if (mounted) setState(() => pipelineLoading = false);
  }

  Future<void> pickFromGallery() async {
    HapticFeedback.lightImpact();
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: null);
      if (file == null) return;
      await _loadFile(file);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> captureFromCamera() async {
    HapticFeedback.lightImpact();
    try {
      final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: null);
      if (file == null) return;
      await _loadFile(file);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _loadFile(XFile file) async {
    if (!mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      setState(() => error = 'Failed to decode image');
      return;
    }
    setState(() {
      sourceBytes = bytes;
      sourceW = decoded.width;
      sourceH = decoded.height;
      resultBytes = null;
      error = '';
    });
  }

  Uint8List rgbaBytes(Uint8List fileBytes, int w, int h) {
    final decoded = img.decodeImage(fileBytes);
    if (decoded == null) return fileBytes;
    final rgba = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = decoded.getPixel(x, y);
        final i = (y * w + x) * 4;
        rgba[i] = p.r.toInt();
        rgba[i + 1] = p.g.toInt();
        rgba[i + 2] = p.b.toInt();
        rgba[i + 3] = 255;
      }
    }
    return rgba;
  }

  Future<void> applyEdit() async {
    if (sourceBytes == null) return;
    setState(() => processing = true);

    try {
      final rgba = rgbaBytes(sourceBytes!, sourceW, sourceH);
      FaceData? faceData;
      if (needsFace && !pipelineLoading) {
        final faces = await _facePipeline.process(rgba, sourceW, sourceH);
        faceData = faces.isNotEmpty ? faces.first : null;
      }

      final editConfig = buildEditConfig();
      final result = await editor.edit(
        sourceBytes: sourceBytes!,
        sourceWidth: sourceW,
        sourceHeight: sourceH,
        faceData: faceData,
        config: editConfig,
      );
      if (mounted) {
        setState(() {
          resultBytes = result;
          processing = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { processing = false; error = e.toString(); });
    }
  }

  Future<void> saveResult() async {
    final bytes = resultBytes;
    if (bytes == null) return;
    HapticFeedback.mediumImpact();
    final granted = await Gal.requestAccess();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gallery access denied')),
        );
      }
      return;
    }
    try {
      await Gal.putImageBytes(bytes, name: 'edit_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to gallery'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  void goToPrint(Uint8List bytes) {
    HapticFeedback.heavyImpact();
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => TemplatePrintScreen(photos: [bytes]),
    ));
  }

  Widget buildSourcePicker() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(config.icon, size: 64, color: config.color),
            const SizedBox(height: 20),
            Text(config.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white)),
            const SizedBox(height: 8),
            Text(config.description, textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.5)),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: GradientButton(
                icon: Icons.photo_library,
                label: 'Select from Gallery',
                onPressed: pickFromGallery,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: captureFromCamera,
                icon: const Icon(Icons.camera_alt, size: 20),
                label: const Text('Open Camera'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildEditView() {
    final hasResult = resultBytes != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              hasResult ? resultBytes! : sourceBytes!,
              fit: BoxFit.contain,
              height: 260,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasResult ? 'Edited' : 'Original',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 24),
          buildPreferences(),
          const SizedBox(height: 24),
          EditActionBar(
            hasResult: hasResult,
            processing: processing,
            onSave: saveResult,
            onPrint: () => goToPrint(resultBytes!),
            onApply: applyEdit,
          ),
          if (!hasResult) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => setState(() { sourceBytes = null; resultBytes = null; error = ''; }),
              icon: const Icon(Icons.replay, size: 18),
              label: const Text('Choose Different Photo'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget sectionHeader(String text) {
    return Text(text, style: const TextStyle(
      color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5,
    ));
  }

  Widget labeledSlider(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        Text(value.toStringAsFixed(value > 10 ? 0 : 1), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
      SliderTheme(
        data: SliderThemeData(
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          activeTrackColor: AppTheme.primary,
          inactiveTrackColor: AppTheme.surfaceBorder,
          thumbColor: Colors.white,
          overlayColor: AppTheme.primary.withValues(alpha: 0.12),
        ),
        child: Slider(value: value, min: min, max: max, onChanged: onChanged),
      ),
    ]);
  }

  Widget labeledInput(String label, String initial, ValueChanged<String> onSubmitted) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      const SizedBox(height: 4),
      TextFormField(
        initialValue: initial,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: inputDeco(),
        onFieldSubmitted: onSubmitted,
      ),
    ]);
  }

  InputDecoration inputDeco() {
    return InputDecoration(
      filled: true,
      fillColor: AppTheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.surfaceBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.surfaceBorder),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      isDense: true,
    );
  }

  Widget autoNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: const Row(children: [
        Icon(Icons.auto_awesome, color: AppTheme.primary, size: 20),
        SizedBox(width: 12),
        Expanded(child: Text('This feature runs automatically. Just tap Apply.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
      ]),
    );
  }

  Widget buildError() {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
      const SizedBox(height: 12),
      Text(error, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: () { setState(() { error = ''; sourceBytes = null; resultBytes = null; }); },
        icon: const Icon(Icons.refresh),
        label: const Text('Try Again'),
      ),
    ]));
  }

  Widget buildPresetChips(List<PresetChip> chips) {
    return Wrap(spacing: 6, runSpacing: 6, children: chips.map((c) {
      return ChoiceChip(
        label: Text(c.label, style: const TextStyle(fontSize: 12)),
        selected: c.selected,
        onSelected: (_) => c.onTap(),
        selectedColor: AppTheme.primary.withValues(alpha: 0.3),
        backgroundColor: AppTheme.surface,
        labelStyle: TextStyle(
          color: c.selected ? Colors.white : AppTheme.textSecondary,
          fontSize: 12,
        ),
        side: BorderSide(color: c.selected ? AppTheme.primary : AppTheme.surfaceBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      );
    }).toList());
  }

  Widget buildBody() {
    if (error.isNotEmpty) return buildError();
    if (sourceBytes == null) return buildSourcePicker();
    return buildEditView();
  }
}

class PresetChip {
  final String label;
  final VoidCallback onTap;
  final bool selected;
  PresetChip(this.label, this.onTap, this.selected);
}
