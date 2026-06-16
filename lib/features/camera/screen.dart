import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'camera_engine.dart';
import '../../core/app_theme.dart';
import '../../shared/widgets/app_widgets.dart';
import '../print_template/screen.dart';

class PhotoCameraScreen extends StatefulWidget {
  const PhotoCameraScreen({super.key});

  @override
  State<PhotoCameraScreen> createState() => _PhotoCameraScreenState();
}

class _PhotoCameraScreenState extends State<PhotoCameraScreen> with WidgetsBindingObserver {
  final CameraEngine _engine = CameraEngine();
  bool _isReady = false;
  String _error = '';
  String? _lastPhotoPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _engine.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_engine.isInitialized) {
      _init();
    } else if (state == AppLifecycleState.paused) {
      _engine.dispose();
    }
  }

  Future<void> _init() async {
    try {
      await _engine.init(lens: CameraLens.back);
      if (mounted) setState(() => _isReady = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _capture() async {
    if (_engine.isCapturing) return;
    HapticFeedback.mediumImpact();
    try {
      final result = await _engine.takePhoto();
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() => _lastPhotoPath = result.filePath);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _switchCamera() async {
    HapticFeedback.lightImpact();
    setState(() => _isReady = false);
    await _engine.switchCamera();
    if (mounted) setState(() => _isReady = true);
  }

  void _showPreview() {
    if (_lastPhotoPath == null) return;
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PhotoPreviewSheet(
        photoPath: _lastPhotoPath!,
        onRetake: () => setState(() => _lastPhotoPath = null),
        onLayout: () async {
          final bytes = await File(_lastPhotoPath!).readAsBytes();
          if (!mounted) return;
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => TemplatePrintScreen(photos: [bytes]),
          ));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error.isNotEmpty) return _buildError();

    if (!_isReady) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppTheme.primary),
              const SizedBox(height: 16),
              const Text('Initializing...', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(_engine.controller!)),
          Positioned.fill(child: _buildViewFinder()),

          Positioned(
            top: MediaQuery.of(context).padding.top + 8, left: 16, right: 16,
            child: Row(
              children: [
                _GlassBtn(icon: Icons.arrow_back, onTap: () => Navigator.pop(context)),
                const Spacer(),
                const Text('Camera', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                const Spacer(),
                if (_engine.isCapturing)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              ],
            ),
          ),

          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: EdgeInsets.only(left: 24, right: 24, top: 12, bottom: MediaQuery.of(context).padding.bottom + 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0), Colors.black.withValues(alpha: 0.55)],
                ),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                if (_lastPhotoPath != null)
                  GestureDetector(
                    onTap: _showPreview,
                    child: AnimatedScale(
                      scale: 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white, width: 2),
                          image: DecorationImage(image: FileImage(File(_lastPhotoPath!)), fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 48),

                GestureDetector(
                  onTapDown: (_) => HapticFeedback.heavyImpact(),
                  onTap: _engine.isCapturing ? null : _capture,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      color: _engine.isCapturing ? Colors.grey : Colors.white.withValues(alpha: 0.2),
                    ),
                    child: _engine.isCapturing
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.camera_alt, color: Colors.white, size: 30),
                  ),
                ),

                _GlassBtn(icon: Icons.flip_camera_android, onTap: _switchCamera),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewFinder() => CustomPaint(
    painter: _ViewFinderPainter(),
    child: const SizedBox.expand(),
  );

  Widget _buildError() => Scaffold(
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
      const SizedBox(height: 12),
      Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      const SizedBox(height: 20),
      FilledButton.icon(onPressed: () { setState(() => _error = ''); _init(); }, icon: const Icon(Icons.refresh), label: const Text('Retry')),
    ])),
  );
}

class _GlassBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.3),
      shape: BoxShape.circle,
    ),
    child: IconButton(
      icon: Icon(icon, color: Colors.white, size: 26),
      onPressed: () { HapticFeedback.lightImpact(); onTap(); },
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    ),
  );
}

class _ViewFinderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke ..strokeWidth = 1;
    final w = size.width, h = size.height;
    canvas.drawLine(Offset(w / 3, 0), Offset(w / 3, h), paint);
    canvas.drawLine(Offset(w * 2 / 3, 0), Offset(w * 2 / 3, h), paint);
    canvas.drawLine(Offset(0, h / 3), Offset(w, h / 3), paint);
    canvas.drawLine(Offset(0, h * 2 / 3), Offset(w, h * 2 / 3), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _PhotoPreviewSheet extends StatelessWidget {
  final String photoPath;
  final VoidCallback onRetake;
  final VoidCallback onLayout;

  const _PhotoPreviewSheet({
    required this.photoPath,
    required this.onRetake,
    required this.onLayout,
  });

  @override
  Widget build(BuildContext context) {
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
            Center(child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(File(photoPath), fit: BoxFit.contain, height: 280),
            ),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () { HapticFeedback.lightImpact(); Navigator.pop(ctx); onRetake(); },
                  icon: const Icon(Icons.replay, size: 18),
                  label: const Text('Retake'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: GradientButton(
                  onPressed: () { HapticFeedback.heavyImpact(); Navigator.pop(ctx); onLayout(); },
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.dashboard, size: 18),
                    SizedBox(width: 6),
                    Text('Layout & Print'),
                  ]),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
