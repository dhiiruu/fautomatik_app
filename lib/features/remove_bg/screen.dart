import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../shared/widgets/app_widgets.dart';
import '../edit/screen.dart';
import '../edit/config.dart';
import '../edit/editor.dart';
import 'process.dart';

class RemoveBgScreen extends StatefulWidget {
  const RemoveBgScreen({super.key});
  @override
  State<RemoveBgScreen> createState() => _RemoveBgScreenState();
}

class _RemoveBgScreenState extends State<RemoveBgScreen> with EditScreenMixin<RemoveBgScreen> {
  int? _bgColor;
  double _sliderValue = 1.0;
  U2netBgRemover? _remover;

  @override
  void initState() {
    super.initState();
    _initRemover();
  }

  Future<void> _initRemover() async {
    final r = U2netBgRemover();
    try {
      await r.load();
      if (mounted) setState(() => _remover = r);
    } catch (_) {
      r.dispose();
    }
  }

  @override
  void dispose() {
    _remover?.dispose();
    super.dispose();
  }

  static const _colors = <int?>[
    null,
    0xFFFFFFFF, 0xFF000000, 0xFF7C4DFF, 0xFF2196F3, 0xFF4CAF50,
    0xFFFF9800, 0xFFF44336, 0xFFE91E63, 0xFF9C27B0, 0xFF00BCD4,
    0xFF8BC34A, 0xFFFFEB3B,
  ];

  @override
  FeatureConfig get config => FeatureConfig.all[1];

  @override
  bool get needsFace => false;

  @override
  EditConfig buildEditConfig() {
    return EditConfig(
      background: _bgColor != null
          ? BackgroundConfig(color: _bgColor!, maskThreshold: 0.5, featherRadius: 3)
          : null,
      output: const OutputConfig(format: 'png'),
    );
  }

  @override
  Future<void> applyEdit() async {
    if (sourceBytes == null) return;
    final r = _remover;
    if (r == null) return;
    setState(() { processing = true; _sliderValue = 1.0; });

    try {
      final rgba = rgbaBytes(sourceBytes!, sourceW, sourceH);
      final mask = await r.process(rgba, sourceW, sourceH);

      final editConfig = EditConfig(
        background: _bgColor != null
            ? BackgroundConfig(color: _bgColor!, maskThreshold: 0.5, featherRadius: 3)
            : null,
        output: const OutputConfig(format: 'png'),
      );

      final result = await editor.edit(
        sourceBytes: sourceBytes!,
        sourceWidth: sourceW,
        sourceHeight: sourceH,
        maskBytes: mask.maskBytes,
        maskWidth: mask.width,
        maskHeight: mask.height,
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

  @override
  Widget buildPreferences() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sectionHeader('Background Color'),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: _colors.map((c) {
        final selected = _bgColor == c;
        Widget circle;
        if (c == null) {
          circle = Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: selected ? Colors.white : Colors.white24, width: selected ? 3 : 1),
              color: const Color(0xFF2A2A2A),
            ),
            child: Icon(Icons.block, color: selected ? Colors.white : Colors.white54, size: 18),
          );
        } else {
          circle = Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: Color(c),
              shape: BoxShape.circle,
              border: Border.all(color: selected ? Colors.white : Colors.white24, width: selected ? 3 : 1),
              boxShadow: selected ? [BoxShadow(color: Colors.white.withValues(alpha: 0.3), blurRadius: 8)] : null,
            ),
            child: selected ? const Icon(Icons.check, color: Colors.black54, size: 18) : null,
          );
        }
        return GestureDetector(onTap: () => setState(() => _bgColor = c), child: circle);
      }).toList()),
    ]);
  }

  @override
  Widget buildEditView() {
    final hasResult = resultBytes != null;
    final src = sourceBytes!;
    final modelReady = _remover != null;

    return Column(
      children: [
        // Photo area — fills remaining space
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: hasResult
                ? _BeforeAfterSlider(
                    originalBytes: src,
                    resultBytes: resultBytes!,
                    sliderValue: _sliderValue,
                    onChanged: (v) => setState(() => _sliderValue = v),
                  )
                : modelReady
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(src, fit: BoxFit.contain),
                      )
                    : const Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Loading model…', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                        ]),
                      ),
          ),
        ),
        // Compact slider
        if (hasResult) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                activeTrackColor: AppTheme.primary,
                inactiveTrackColor: AppTheme.surfaceBorder,
                thumbColor: Colors.white,
                overlayColor: AppTheme.primary.withValues(alpha: 0.12),
              ),
              child: Slider(
                value: _sliderValue,
                min: 0.0,
                max: 1.0,
                onChanged: (v) => setState(() => _sliderValue = v),
              ),
            ),
          ),
          const Text('Drag to compare before / after',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 10, fontWeight: FontWeight.w500)),
        ],
        const SizedBox(height: 8),
        // Preferences (color circles)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: buildPreferences(),
        ),
        const SizedBox(height: 12),
        // Action buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: EditActionBar(
            hasResult: hasResult,
            processing: processing,
            canApply: modelReady,
            onSave: saveResult,
            onPrint: () => goToPrint(resultBytes!),
            onApply: applyEdit,
          ),
        ),
      ],
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

class _BeforeAfterSlider extends StatelessWidget {
  final Uint8List originalBytes;
  final Uint8List resultBytes;
  final double sliderValue;
  final ValueChanged<double> onChanged;

  const _BeforeAfterSlider({
    required this.originalBytes,
    required this.resultBytes,
    required this.sliderValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final clipX = width * sliderValue;

        return GestureDetector(
          onHorizontalDragUpdate: (details) {
            final newValue = (details.localPosition.dx / width).clamp(0.0, 1.0);
            onChanged(newValue);
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                Image.memory(originalBytes, fit: BoxFit.contain, width: width, height: height),
                ClipRect(
                  clipper: _LeftClipper(clipX),
                  child: Image.memory(resultBytes, fit: BoxFit.contain, width: width, height: height),
                ),
                Positioned(
                  left: clipX - 1,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: Colors.white),
                ),
                Positioned(
                  left: clipX - 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(
                      width: 24, height: 24,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                      child: const Icon(Icons.swap_horiz, color: Colors.black87, size: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LeftClipper extends CustomClipper<Rect> {
  final double clipX;
  _LeftClipper(this.clipX);

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, 0, clipX, size.height);

  @override
  bool shouldReclip(_LeftClipper old) => old.clipX != clipX;
}
