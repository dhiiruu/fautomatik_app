import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'edge_detector.dart';
import 'pipeline.dart';
import '../camera/camera_engine.dart';
import '../../core/app_theme.dart';
import '../../shared/widgets/app_widgets.dart';
import '../print_template/screen.dart';

class ScanCameraScreen extends StatefulWidget {
  const ScanCameraScreen({super.key});

  @override
  State<ScanCameraScreen> createState() => _ScanCameraScreenState();
}

class _ScanCameraScreenState extends State<ScanCameraScreen> with WidgetsBindingObserver {
  final CameraEngine _engine = CameraEngine();
  final ScanPipeline _scanPipeline = ScanPipeline();

  StreamSubscription<ProcessedFrame>? _frameSub;
  bool _isReady = false;
  String _error = '';
  bool _torchOn = false;
  EdgeDetectorResult _lastEdges = const EdgeDetectorResult();
  bool _showResult = false;
  String? _resultPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _frameSub?.cancel();
    _engine.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_engine.isInitialized) _init();
    } else if (state == AppLifecycleState.paused) {
      _frameSub?.cancel();
      _frameSub = null;
      _engine.dispose();
    }
  }

  Future<void> _init() async {
    try {
      await _engine.init(lens: CameraLens.back);
      if (mounted) setState(() => _isReady = true);
      await _startEdgeDetection();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _startEdgeDetection() async {
    await _engine.startFrameStream(
      onFaceDetect: (a, b, c) async => [],
      throttleMs: 100,
    );

    _frameSub = _engine.frameStream?.listen((frame) {
      if (!mounted || _showResult) return;
      final scale = CameraEngine.previewWidth / frame.width;
      final smallW = CameraEngine.previewWidth;
      final smallH = (frame.height * scale).round();
      final downscaled = _downscaleRgba(frame.rgbaBytes, frame.width, frame.height, smallW, smallH);
      final edges = _scanPipeline.detectEdges(downscaled, smallW, smallH);
      if (mounted) setState(() => _lastEdges = edges);
      if (_scanPipeline.isStable(edges)) _capture();
    });
  }

  Uint8List _downscaleRgba(Uint8List rgba, int srcW, int srcH, int dstW, int dstH) {
    final out = Uint8List(dstW * dstH * 4);
    final xStep = srcW / dstW;
    final yStep = srcH / dstH;
    for (var dy = 0; dy < dstH; dy++) {
      for (var dx = 0; dx < dstW; dx++) {
        final sx = (dx * xStep).round().clamp(0, srcW - 1);
        final sy = (dy * yStep).round().clamp(0, srcH - 1);
        final si = (sy * srcW + sx) * 4;
        final di = (dy * dstW + dx) * 4;
        out[di] = rgba[si];
        out[di + 1] = rgba[si + 1];
        out[di + 2] = rgba[si + 2];
        out[di + 3] = 255;
      }
    }
    return out;
  }

  Future<void> _toggleTorch() async {
    HapticFeedback.lightImpact();
    try {
      await _engine.controller?.setFlashMode(_torchOn ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => _torchOn = !_torchOn);
    } catch (_) {}
  }

  Future<void> _capture() async {
    if (_engine.isCapturing) return;
    HapticFeedback.mediumImpact();
    try {
      final result = await _engine.takePhoto();
      if (!mounted) return;
      final fileBytes = await File(result.filePath).readAsBytes();
      final scanResult = _scanPipeline.scan(sourceBytes: fileBytes, edges: _lastEdges);
      if (scanResult.success && scanResult.jpegBytes != null) {
        final dir = await getApplicationDocumentsDirectory();
        final outPath = '${dir.path}/scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(outPath).writeAsBytes(scanResult.jpegBytes!);
        if (mounted) setState(() { _resultPath = outPath; _showResult = true; });
      } else {
        if (mounted) setState(() { _resultPath = result.filePath; _showResult = true; });
      }
      HapticFeedback.heavyImpact();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    await _engine.stopFrameStream();
  }

  @override
  Widget build(BuildContext context) {
    if (_error.isNotEmpty) return _buildError();
    if (_showResult && _resultPath != null) return _buildResultScreen();
    if (!_isReady) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: AppTheme.primary),
            const SizedBox(height: 16),
            const Text('Loading scanner...', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          ]),
        ),
      );
    }

    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: CameraPreview(_engine.controller!)),
        Positioned.fill(child: CustomPaint(
          painter: _ScanOverlayPainter(edges: _lastEdges, previewW: CameraEngine.previewWidth,
            previewH: (MediaQuery.of(context).size.width * (_engine.controller?.value.aspectRatio ?? 1.0)).round()),
        )),

        // Status
        Positioned(
          top: MediaQuery.of(context).padding.top + 80, left: 0, right: 0,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _lastEdges.photoFound
                  ? AppTheme.success.withValues(alpha: 0.85)
                  : Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_lastEdges.photoFound) ...[
                  const Icon(Icons.check_circle, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text('Photo detected ${(_lastEdges.coverage * 100).round()}%',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                ] else ...[
                  const Icon(Icons.document_scanner, color: Colors.white54, size: 16),
                  const SizedBox(width: 6),
                  const Text('Center a printed photo in the frame',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
                ],
              ]),
            ),
          ),
        ),

        // Top
        Positioned(
          top: MediaQuery.of(context).padding.top + 8, left: 16, right: 16,
          child: Row(children: [
            const Icon(Icons.document_scanner, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            const Text('Scan Photo', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
            const Spacer(),
            if (_engine.isCapturing)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          ]),
        ),

        // Bottom
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
              _GlassBtn(icon: _torchOn ? Icons.flash_on : Icons.flash_off,
                color: _torchOn ? Colors.yellowAccent : Colors.white70, onTap: _toggleTorch),
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
                    : const Icon(Icons.document_scanner, color: Colors.white, size: 28),
                ),
              ),
              _GlassBtn(icon: Icons.close, onTap: () => Navigator.pop(context)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildResultScreen() => Scaffold(
    body: Container(
      decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
      child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Spacer(flex: 2),
        if (_resultPath != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(File(_resultPath!), fit: BoxFit.contain, height: 380),
            ),
          ),
        const Spacer(flex: 1),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          OutlinedButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() { _showResult = false; _resultPath = null; _scanPipeline.reset(); _isReady = false; });
              _init();
            },
            icon: const Icon(Icons.replay, size: 18),
            label: const Text('Scan Again'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
          ),
          const SizedBox(width: 16),
          GradientButton(
            onPressed: () {
              HapticFeedback.heavyImpact();
              if (_resultPath == null) return;
              File(_resultPath!).readAsBytes().then((bytes) {
                if (mounted) {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => TemplatePrintScreen(photos: [bytes]),
                  ));
                }
              });
            },
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check, size: 18), SizedBox(width: 6), Text('Layout & Print'),
            ]),
          ),
        ]),
        const Spacer(flex: 2),
      ])),
    ),
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
  final Color? color;
  final VoidCallback onTap;
  const _GlassBtn({required this.icon, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), shape: BoxShape.circle),
    child: IconButton(
      icon: Icon(icon, color: color ?? Colors.white, size: 26),
      onPressed: () { HapticFeedback.lightImpact(); onTap(); },
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    ),
  );
}

class _ScanOverlayPainter extends CustomPainter {
  final EdgeDetectorResult edges;
  final int previewW;
  final int previewH;

  _ScanOverlayPainter({required this.edges, required this.previewW, required this.previewH});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3) ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = size.width / 3 * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var i = 1; i < 3; i++) {
      final y = size.height / 3 * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    if (edges.photoFound) {
      final p = Paint() ..color = Colors.greenAccent ..strokeWidth = 3 ..style = PaintingStyle.stroke;
      final sx = size.width / previewW;
      final sy = size.height / previewH;
      Offset sc(Offset c) => Offset(c.dx * sx, c.dy * sy);
      final corners = edges.corners;
      if (corners.length >= 4) {
        final path = Path()
          ..moveTo(sc(corners[0]).dx, sc(corners[0]).dy)
          ..lineTo(sc(corners[1]).dx, sc(corners[1]).dy)
          ..lineTo(sc(corners[2]).dx, sc(corners[2]).dy)
          ..lineTo(sc(corners[3]).dx, sc(corners[3]).dy) ..close();
        canvas.drawPath(path, p);
        for (final c in corners) {
          canvas.drawCircle(sc(c), 5, Paint()..color = Colors.yellowAccent);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScanOverlayPainter old) => old.edges != edges;
}
