import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/app_theme.dart';
import '../../core/types.dart';
import '../../shared/audio/audio_guide.dart';
import '../../shared/widgets/app_widgets.dart';
import '../../shared/widgets/photo_preview_sheet.dart';
import '../camera/camera_engine.dart';
import '../photo_booth/guidance_checker.dart';
import '../photo_booth/pose_checker.dart';
import '../photo_booth/pipeline.dart' as booth_pipeline;
import '../scanner/edge_detector.dart';
import '../scanner/pipeline.dart' as scanner_pipeline;
import '../print_template/screen.dart';

enum CameraMode { standard, faceId, scanner }

class UnifiedCameraScreen extends StatefulWidget {
  const UnifiedCameraScreen({super.key});

  @override
  State<UnifiedCameraScreen> createState() => _UnifiedCameraScreenState();
}

class _UnifiedCameraScreenState extends State<UnifiedCameraScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  final CameraEngine _engine = CameraEngine();
  final GuidanceChecker _guidanceChecker = GuidanceChecker();
  final PoseChecker _poseChecker = PoseChecker();
  final AudioGuide _audioGuide = AudioGuide();
  final booth_pipeline.BodyPipeline _bodyPipeline = booth_pipeline.BodyPipeline();
  final scanner_pipeline.ScanPipeline _scanPipeline = scanner_pipeline.ScanPipeline();

  StreamSubscription<ProcessedFrame>? _frameSub;
  
  // Mode state
  CameraMode _mode = CameraMode.standard;
  bool _leftPanelExpanded = false;
  bool _rightPanelExpanded = false;
  
  // Face/ID mode state
  GuidanceResult _lastGuidance = const GuidanceResult();
  GuidanceResult _stableGuidance = const GuidanceResult();
  PoseCheckResult _lastPose = const PoseCheckResult();
  BodyData _lastBody = const BodyData();
  FaceData? _lastFace;
  int _stableFrames = 0;
  bool _autoCaptureEnabled = true;
  bool _muted = false;
  double _faceOvalScale = 0.4; // 40% default
  int _preferredCornerRatio = 40; // stored preference
  bool _captureFullFrame = false; // false = crop to frame
  
  // Scanner mode state
  EdgeDetectorResult _lastEdges = const EdgeDetectorResult();
  bool _scannerAutoCapture = true;
  
  // Standard mode state
  double _exposure = 0.0;
  double _zoom = 1.0;
  bool _flashOn = false;
  Offset? _focusPoint;
  
  // Common state
  bool _isReady = false;
  String _error = '';
  bool _pipelineLoading = true;
  bool _isCapturing = false;
  String? _capturedPath;
  bool _showPreview = false;
  Timer? _captureTimer;
  Timer? _throttleTimer;

  static const int stableFramesNeeded = 10;
  static const int autoCaptureDelayMs = 1500;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPreferences();
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _frameSub?.cancel();
    _captureTimer?.cancel();
    _throttleTimer?.cancel();
    _savePreferences();
    _bodyPipeline.dispose();
    _engine.dispose();
    _audioGuide.dispose();
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

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _faceOvalScale = prefs.getDouble('faceOvalScale') ?? 0.4;
      _preferredCornerRatio = prefs.getInt('cornerRatio') ?? 40;
      _captureFullFrame = prefs.getBool('captureFullFrame') ?? false;
      _autoCaptureEnabled = prefs.getBool('autoCaptureEnabled') ?? true;
    });
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('faceOvalScale', _faceOvalScale);
    await prefs.setInt('cornerRatio', _preferredCornerRatio);
    await prefs.setBool('captureFullFrame', _captureFullFrame);
    await prefs.setBool('autoCaptureEnabled', _autoCaptureEnabled);
  }

  Future<void> _init() async {
    try {
      await _bodyPipeline.load();
      if (mounted) setState(() => _pipelineLoading = false);
      
      final lens = _mode == CameraMode.faceId ? CameraLens.front : CameraLens.back;
      await _engine.init(lens: lens);
      if (mounted) setState(() => _isReady = true);
      
      await _startProcessing();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _startProcessing() async {
    await _engine.startFrameStream(
      onFaceDetect: _mode == CameraMode.faceId 
          ? (b, w, h) async => [] // Will use MediaPipe separately
          : (a, b, c) async => [],
      onRawFrame: _mode == CameraMode.faceId
          ? (nv21, w, h, stride) {
              _bodyPipeline.process(nv21Bytes: nv21, width: w, height: h, yRowStride: stride)
                .then((body) { if (mounted) setState(() => _lastBody = body); });
            }
          : null,
      throttleMs: _mode == CameraMode.scanner ? 100 : 150,
    );

    _frameSub = _engine.frameStream?.listen((frame) {
      if (!mounted || _showPreview) return;
      
      switch (_mode) {
        case CameraMode.faceId:
          _processFaceIdFrame(frame);
          break;
        case CameraMode.scanner:
          _processScannerFrame(frame);
          break;
        case CameraMode.standard:
          // No special processing for standard mode
          break;
      }
    });
  }

  void _processFaceIdFrame(ProcessedFrame frame) {
    final g = _guidanceChecker.check(
      frameW: frame.width,
      frameH: frame.height,
      face: frame.face,
      frameBytes: frame.rgbaBytes,
      isMirrored: frame.isMirrored,
    );
    _lastFace = frame.face;
    final pose = _poseChecker.check(frameW: frame.width, frameH: frame.height, body: _lastBody);
    _lastPose = pose;
    
    final allGood = g.allGood && pose.allGood;
    if (allGood) {
      _stableFrames++;
      if (_stableFrames >= 3) _stableGuidance = g;
    } else {
      _stableFrames = 0;
    }
    
    setState(() {
      final prev = _lastGuidance;
      _lastGuidance = g;
      if (!_muted && (prev.faceDetected != g.faceDetected || prev.faceCentered != g.faceCentered)) {
        _audioGuide.speak(_instructionText(g));
      }
    });
    
    if (_autoCaptureEnabled && allGood && _stableFrames >= stableFramesNeeded) {
      _capture();
    }
  }

  void _processScannerFrame(ProcessedFrame frame) {
    if (_throttleTimer?.isActive ?? false) return;
    _throttleTimer = Timer(const Duration(milliseconds: 150), () {});
    
    final scale = CameraEngine.previewWidth / frame.width;
    final smallW = CameraEngine.previewWidth;
    final smallH = (frame.height * scale).round();
    final downscaled = _downscaleRgba(frame.rgbaBytes, frame.width, frame.height, smallW, smallH);
    final edges = _scanPipeline.detectEdges(downscaled, smallW, smallH);
    
    if (mounted) setState(() => _lastEdges = edges);
    
    if (_scannerAutoCapture && _scanPipeline.isStable(edges)) {
      _capture();
    }
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

  String _instructionText(GuidanceResult g) {
    if (!g.faceDetected) return 'Position your face in the frame';
    if (!g.faceCentered) return 'Center your face';
    if (!g.faceSized) return g.faceOffsetFraction < 0.1 ? 'Move closer' : 'Move back';
    if (!g.headLevel) return 'Keep your head straight';
    if (!g.eyesOpen) return 'Open your eyes';
    if (!g.neutralExpression) return 'Neutral expression please';
    if (!g.brightnessOk) return g.brightnessLevel < 0.3 ? 'Too dark' : 'Too bright';
    if (g.backlit) return 'Move away from bright background';
    if (!_lastPose.bodyDetected) return 'Step into the frame';
    if (!_lastPose.fullBodyVisible) return 'Step back to show full body';
    return 'Hold still...';
  }

  Future<void> _capture() async {
    if (_isCapturing) return;
    HapticFeedback.mediumImpact();
    setState(() { _isCapturing = true; _showPreview = false; });
    
    try {
      final result = await _engine.takePhoto();
      if (!mounted) return;
      
      String? finalPath = result.filePath;
      
      // For scanner mode, apply perspective warp
      if (_mode == CameraMode.scanner && _lastEdges.photoFound) {
        final fileBytes = await File(result.filePath).readAsBytes();
        final scanResult = _scanPipeline.scan(sourceBytes: fileBytes, edges: _lastEdges);
        if (scanResult.success && scanResult.jpegBytes != null) {
          final dir = await getApplicationDocumentsDirectory();
          finalPath = '${dir.path}/scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
          await File(finalPath!).writeAsBytes(scanResult.jpegBytes!);
        }
      }
      
      setState(() {
        _capturedPath = finalPath;
        _showPreview = true;
        _isCapturing = false;
      });
      HapticFeedback.heavyImpact();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isCapturing = false; });
    }
  }

  Future<void> _switchMode(CameraMode newMode) async {
    if (newMode == _mode) return;
    HapticFeedback.lightImpact();
    _frameSub?.cancel();
    _captureTimer?.cancel();
    setState(() {
      _mode = newMode;
      _isReady = false;
      _lastGuidance = const GuidanceResult();
      _lastEdges = const EdgeDetectorResult();
      _stableFrames = 0;
    });
    await _engine.dispose();
    await _init();
  }

  Future<void> _switchCamera() async {
    HapticFeedback.lightImpact();
    _frameSub?.cancel();
    setState(() => _isReady = false);
    await _engine.switchCamera();
    setState(() => _isReady = true);
    await _startProcessing();
  }

  Future<void> _toggleTorch() async {
    try {
      await _engine.controller?.setFlashMode(_flashOn ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => _flashOn = !_flashOn);
    } catch (_) {}
  }

  void _setFocusPoint(Offset point) {
    if (_mode != CameraMode.standard) return;
    setState(() => _focusPoint = point);
    // In a real implementation, this would call controller.setFocusPointAndExposurePoint
  }

  @override
  Widget build(BuildContext context) {
    if (_error.isNotEmpty) return _buildError();
    if (_showPreview && _capturedPath != null) {
      return Stack(children: [
        Positioned.fill(child: Container(color: Colors.black)),
        PhotoPreviewSheet(
          photoPath: _capturedPath!,
          onRetake: () => setState(() { _showPreview = false; _capturedPath = null; }),
          onDone: () {
            Navigator.pop(context);
          },
        ),
      ]);
    }
    
    if (!_isReady || _pipelineLoading) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: AppTheme.primary),
            const SizedBox(height: 12),
            Text(_pipelineLoading ? 'Loading models...' : 'Initializing camera...',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          ]),
        ),
      );
    }

    return Scaffold(
      body: Stack(children: [
        // Camera preview
        Positioned.fill(
          child: GestureDetector(
            onTapDown: (d) => _setFocusPoint(d.localPosition),
            child: _buildPreview(),
          ),
        ),
        
        // Overlays based on mode
        if (_mode == CameraMode.faceId) Positioned.fill(child: _buildFaceIdOverlay()),
        if (_mode == CameraMode.scanner) Positioned.fill(child: _buildScannerOverlay()),
        
        // Top bar
        _buildTopBar(),
        
        // Left panel (mode selector)
        _buildLeftPanel(),
        
        // Right panel (standard mode controls)
        if (_mode == CameraMode.standard) _buildRightPanel(),
        
        // Bottom bar
        _buildBottomBar(),
        
        // Guidance panel for Face/ID mode
        if (_mode == CameraMode.faceId) _buildGuidancePanel(),
      ]),
    );
  }

  Widget _buildPreview() {
    final ctrl = _engine.controller;
    if (ctrl == null) return const SizedBox();
    final ar = ctrl.value.previewSize != null ? ctrl.value.aspectRatio : 1.0;
    return ClipRect(
      child: AspectRatio(aspectRatio: ar, child: CameraPreview(ctrl)),
    );
  }

  Widget _buildFaceIdOverlay() => LayoutBuilder(builder: (ctx, constraints) {
    return Stack(children: [
      CustomPaint(
        size: Size(constraints.maxWidth, constraints.maxHeight),
        painter: _FaceIdOverlayPainter(
          guidance: _lastGuidance,
          face: _lastFace,
          body: _lastBody,
          viewWidth: constraints.maxWidth,
          viewHeight: constraints.maxHeight,
          isMirrored: _engine.lens == CameraLens.front,
          ovalScale: _faceOvalScale,
          cornerRatio: _preferredCornerRatio,
          autoCaptureEnabled: _autoCaptureEnabled,
          stableFrames: _stableFrames,
          stableFramesNeeded: stableFramesNeeded,
        ),
      ),
      // Zoom slider for oval
      Positioned(
        right: 16,
        top: MediaQuery.of(context).padding.top + 100,
        child: _VerticalSlider(
          value: _faceOvalScale,
          min: 0.2,
          max: 0.8,
          onChanged: (v) => setState(() => _faceOvalScale = v),
          icon: Icons.circle_outlined,
        ),
      ),
    ]);
  });

  Widget _buildScannerOverlay() => LayoutBuilder(builder: (ctx, constraints) {
    return CustomPaint(
      size: Size(constraints.maxWidth, constraints.maxHeight),
      painter: _ScannerOverlayPainter(
        edges: _lastEdges,
        previewW: CameraEngine.previewWidth,
        previewH: (constraints.maxWidth * (_engine.controller?.value.aspectRatio ?? 1.0)).round(),
      ),
    );
  });

  Widget _buildTopBar() => Positioned(
    top: MediaQuery.of(context).padding.top + 8,
    left: 16,
    right: 16,
    child: Row(children: [
      _topBtn(Icons.arrow_back, () => Navigator.pop(context)),
      const Spacer(),
      Text(_getModeTitle(), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w300, letterSpacing: 1)),
      const Spacer(),
      if (_isCapturing)
        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
    ]),
  );

  String _getModeTitle() {
    switch (_mode) {
      case CameraMode.faceId: return 'ID Photo';
      case CameraMode.scanner: return 'Document Scan';
      case CameraMode.standard: return 'Camera';
    }
  }

  Widget _buildLeftPanel() => Positioned(
    top: MediaQuery.of(context).padding.top + 60,
    left: 0,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: _leftPanelExpanded ? 180 : 56,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.only(topRight: Radius.circular(12), bottomRight: Radius.circular(12)),
      ),
      child: Column(children: [
        // Toggle button
        IconButton(
          icon: Icon(_leftPanelExpanded ? Icons.close : Icons.camera_alt, color: Colors.white, size: 22),
          onPressed: () => setState(() => _leftPanelExpanded = !_leftPanelExpanded),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
        ),
        if (_leftPanelExpanded) ...[
          const SizedBox(height: 8),
          _ModeToggleItem(
            icon: Icons.face,
            label: 'ID Photo',
            isActive: _mode == CameraMode.faceId,
            onTap: () => _switchMode(CameraMode.faceId),
          ),
          _ModeToggleItem(
            icon: Icons.camera_alt_outlined,
            label: 'Standard',
            isActive: _mode == CameraMode.standard,
            onTap: () => _switchMode(CameraMode.standard),
          ),
          _ModeToggleItem(
            icon: Icons.document_scanner_outlined,
            label: 'Scanner',
            isActive: _mode == CameraMode.scanner,
            onTap: () => _switchMode(CameraMode.scanner),
          ),
        ],
      ]),
    ),
  );

  Widget _buildRightPanel() => Positioned(
    top: MediaQuery.of(context).padding.top + 60,
    right: 0,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: _rightPanelExpanded ? 160 : 56,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
      ),
      child: Column(children: [
        IconButton(
          icon: Icon(_rightPanelExpanded ? Icons.close : Icons.tune, color: Colors.white, size: 22),
          onPressed: () => setState(() => _rightPanelExpanded = !_rightPanelExpanded),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
        ),
        if (_rightPanelExpanded) ...[
          const SizedBox(height: 12),
          _ControlSlider(
            label: 'Zoom',
            value: _zoom,
            min: 1.0,
            max: 5.0,
            onChanged: (v) => setState(() => _zoom = v),
          ),
          _ControlSlider(
            label: 'Exposure',
            value: _exposure,
            min: -2.0,
            max: 2.0,
            onChanged: (v) => setState(() => _exposure = v),
          ),
          const SizedBox(height: 8),
          _PanelButton(
            icon: _flashOn ? Icons.flash_on : Icons.flash_off,
            label: 'Flash',
            isActive: _flashOn,
            onTap: _toggleTorch,
          ),
        ],
      ]),
    ),
  );

  Widget _buildGuidancePanel() => Positioned(
    left: 20,
    right: 20,
    bottom: 100,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(_instructionText(_lastGuidance),
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w400),
          textAlign: TextAlign.center,
        ),
      ),
    ]),
  );

  Widget _buildBottomBar() => Positioned(
    left: 0,
    right: 0,
    bottom: 0,
    child: Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
        ),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        // Left action based on mode
        _buildLeftActionButton(),
        
        // Shutter button
        GestureDetector(
          onTapDown: (_) => HapticFeedback.heavyImpact(),
          onTap: _isCapturing ? null : _capture,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              color: _isCapturing ? Colors.grey : Colors.transparent,
            ),
            child: _isCapturing
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Container(
                    margin: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
        
        // Right action based on mode
        _buildRightActionButton(),
      ]),
    ),
  );

  Widget _buildLeftActionButton() {
    switch (_mode) {
      case CameraMode.faceId:
        return _bottomActionBtn(
          icon: _autoCaptureEnabled ? Icons.timer : Icons.timer_off,
          label: 'Auto',
          isActive: _autoCaptureEnabled,
          onTap: () => setState(() => _autoCaptureEnabled = !_autoCaptureEnabled),
        );
      case CameraMode.scanner:
        return _bottomActionBtn(
          icon: _flashOn ? Icons.flash_on : Icons.flash_off,
          label: 'Flash',
          isActive: _flashOn,
          onTap: _toggleTorch,
        );
      case CameraMode.standard:
        return _bottomActionBtn(
          icon: Icons.flip_camera_android,
          label: '',
          onTap: _switchCamera,
        );
    }
  }

  Widget _buildRightActionButton() {
    switch (_mode) {
      case CameraMode.faceId:
        return _bottomActionBtn(
          icon: _captureFullFrame ? Icons.crop_free : Icons.crop,
          label: _captureFullFrame ? 'Full' : 'Crop',
          isActive: _captureFullFrame,
          onTap: () => setState(() => _captureFullFrame = !_captureFullFrame),
        );
      case CameraMode.scanner:
        return _bottomActionBtn(
          icon: Icons.auto_awesome,
          label: 'Auto',
          isActive: _scannerAutoCapture,
          onTap: () => setState(() => _scannerAutoCapture = !_scannerAutoCapture),
        );
      case CameraMode.standard:
        return _bottomActionBtn(
          icon: Icons.settings,
          label: '',
          onTap: () => setState(() => _rightPanelExpanded = !_rightPanelExpanded),
        );
    }
  }

  Widget _bottomActionBtn({required IconData icon, String label = '', bool isActive = false, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isActive ? AppTheme.primary.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: isActive ? AppTheme.primary : Colors.white, size: 22),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: isActive ? AppTheme.primary : Colors.white70, fontSize: 10)),
        ],
      ]),
    );
  }

  Widget _topBtn(IconData icon, VoidCallback onTap) => Container(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.3),
      shape: BoxShape.circle,
    ),
    child: IconButton(
      icon: Icon(icon, color: Colors.white, size: 20),
      onPressed: onTap,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    ),
  );

  Widget _buildError() => Scaffold(
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
      const SizedBox(height: 12),
      Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: () { setState(() => _error = ''); _init(); },
        icon: const Icon(Icons.refresh),
        label: const Text('Retry'),
      ),
    ])),
  );
}

// ==================== Mode Toggle Items ====================

class _ModeToggleItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ModeToggleItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Icon(icon, color: isActive ? AppTheme.primary : Colors.white70, size: 18),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(
            color: isActive ? Colors.white : Colors.white70,
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
            letterSpacing: 0.5,
          )),
        ]),
      ),
    );
  }
}

// ==================== Control Slider ====================

class _ControlSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _ControlSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbColor: Colors.white,
            activeTrackColor: AppTheme.primary,
            inactiveTrackColor: Colors.white24,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ]),
    );
  }
}

// ==================== Panel Button ====================

class _PanelButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _PanelButton({
    required this.icon,
    required this.label,
    this.isActive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          Icon(icon, color: isActive ? AppTheme.primary : Colors.white, size: 18),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(
            color: isActive ? AppTheme.primary : Colors.white,
            fontSize: 12,
          )),
        ]),
      ),
    );
  }
}

// ==================== Face ID Overlay Painter ====================

class _FaceIdOverlayPainter extends CustomPainter {
  final GuidanceResult guidance;
  final FaceData? face;
  final BodyData body;
  final double viewWidth;
  final double viewHeight;
  final bool isMirrored;
  final double ovalScale;
  final int cornerRatio;
  final bool autoCaptureEnabled;
  final int stableFrames;
  final int stableFramesNeeded;

  _FaceIdOverlayPainter({
    required this.guidance,
    this.face,
    this.body = const BodyData(),
    required this.viewWidth,
    required this.viewHeight,
    required this.isMirrored,
    required this.ovalScale,
    required this.cornerRatio,
    this.autoCaptureEnabled = false,
    this.stableFrames = 0,
    this.stableFramesNeeded = 10,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    
    // Draw L-shaped corner frames
    _drawCornerFrames(canvas, size, cornerRatio);
    
    // Draw oval guide for face+shoulders
    _drawOvalGuide(canvas, size, cx, cy, ovalScale);
    
    // Draw face mesh if detected
    if (face != null) {
      _drawFaceMesh(canvas, size);
      _drawTiltIndicator(canvas, size);
    }
    
    // Draw auto-capture progress
    if (autoCaptureEnabled) {
      _drawAutoCaptureProgress(canvas, size);
    }
  }

  void _drawCornerFrames(Canvas canvas, Size size, int ratioPct) {
    final frameMargin = size.width * (ratioPct / 100.0);
    final frameLength = size.width * 0.15; // 15% of screen width
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // Top-left
    canvas.drawLine(Offset(frameMargin, frameMargin + frameLength), Offset(frameMargin, frameMargin), paint);
    canvas.drawLine(Offset(frameMargin, frameMargin), Offset(frameMargin + frameLength, frameMargin), paint);
    
    // Top-right
    canvas.drawLine(Offset(size.width - frameMargin, frameMargin + frameLength), Offset(size.width - frameMargin, frameMargin), paint);
    canvas.drawLine(Offset(size.width - frameMargin, frameMargin), Offset(size.width - frameMargin - frameLength, frameMargin), paint);
    
    // Bottom-left
    canvas.drawLine(Offset(frameMargin, size.height - frameMargin - frameLength), Offset(frameMargin, size.height - frameMargin), paint);
    canvas.drawLine(Offset(frameMargin, size.height - frameMargin), Offset(frameMargin + frameLength, size.height - frameMargin), paint);
    
    // Bottom-right
    canvas.drawLine(Offset(size.width - frameMargin, size.height - frameMargin - frameLength), Offset(size.width - frameMargin, size.height - frameMargin), paint);
    canvas.drawLine(Offset(size.width - frameMargin, size.height - frameMargin), Offset(size.width - frameMargin - frameLength, size.height - frameMargin), paint);
  }

  void _drawOvalGuide(Canvas canvas, Size size, double cx, double cy, double scale) {
    final idealW = size.width * scale;
    final idealH = idealW * 1.3; // Aspect ratio for face+shoulders
    
    final paint = Paint()
      ..color = guidance.faceDetected ? Colors.greenAccent.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: idealW, height: idealH), paint);
  }

  void _drawFaceMesh(Canvas canvas, Size size) {
    if (face == null || face!.landmarks.length < 468) return;
    final sx = size.width / viewWidth;
    final sy = size.height / viewHeight;
    final p = Paint()..color = Colors.cyanAccent.withValues(alpha: 0.4)..strokeWidth = 1;
    
    // Draw key landmarks (simplified for performance)
    for (final idx in [10, 338, 297, 332, 284, 251, 389, 356, 454, 323]) {
      if (idx < face!.landmarks.length) {
        final lm = face!.landmarks[idx];
        canvas.drawCircle(Offset(lm.dx * sx, lm.dy * sy), 3, p);
      }
    }
  }

  void _drawTiltIndicator(Canvas canvas, Size size) {
    if (face == null) return;
    final tilt = atan2(
      face!.landmarks[263].dy - face!.landmarks[33].dy,
      face!.landmarks[263].dx - face!.landmarks[33].dx,
    ) * 180 / math.pi;
    
    if (tilt.abs() > 5) {
      final p = Paint()..color = Colors.orangeAccent..strokeWidth = 2;
      final cx = size.width / 2;
      final cy = size.height / 2 + 80;
      canvas.drawLine(Offset(cx - 20, cy), Offset(cx + 20, cy), p);
      canvas.rotate(tilt * math.pi / 180);
    }
  }

  void _drawAutoCaptureProgress(Canvas canvas, Size size) {
    final progress = stableFrames / stableFramesNeeded;
    final cx = size.width / 2;
    final cy = 80;
    
    final bgPaint = Paint()..color = Colors.white24..strokeWidth = 4;
    final fgPaint = Paint()..color = progress >= 1 ? Colors.greenAccent : AppTheme.primary..strokeWidth = 4;
    
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: 20), -math.pi / 2, math.pi * 2 * progress, false, fgPaint);
    canvas.drawCircle(Offset(cx, cy), 20, bgPaint..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant _FaceIdOverlayPainter old) {
    return old.guidance != guidance ||
           old.face != face ||
           old.ovalScale != ovalScale ||
           old.cornerRatio != cornerRatio ||
           old.stableFrames != stableFrames;
  }
}

// ==================== Vertical Slider for Oval Zoom ====================

class _VerticalSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final IconData icon;

  const _VerticalSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(height: 8),
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbColor: AppTheme.primary,
                activeTrackColor: AppTheme.primary,
                inactiveTrackColor: Colors.white24,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('${(value * 100).round()}%', style: TextStyle(color: Colors.white70, fontSize: 9)),
      ]),
    );
  }
}

// ==================== Scanner Overlay Painter ====================

class _ScannerOverlayPainter extends CustomPainter {
  final EdgeDetectorResult edges;
  final int previewW;
  final int previewH;

  _ScannerOverlayPainter({
    required this.edges,
    required this.previewW,
    required this.previewH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw grid lines
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.2)..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = size.width / 3 * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      final y = size.height / 3 * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    
    // Draw detected edges
    if (edges.photoFound) {
      final p = Paint()..color = Colors.greenAccent..strokeWidth = 3..style = PaintingStyle.stroke;
      final sx = size.width / previewW;
      final sy = size.height / previewH;
      Offset sc(Offset c) => Offset(c.dx * sx, c.dy * sy);
      
      final corners = edges.corners;
      if (corners.length >= 4) {
        final path = Path()
          ..moveTo(sc(corners[0]).dx, sc(corners[0]).dy)
          ..lineTo(sc(corners[1]).dx, sc(corners[1]).dy)
          ..lineTo(sc(corners[2]).dx, sc(corners[2]).dy)
          ..lineTo(sc(corners[3]).dx, sc(corners[3]).dy)
          ..close();
        canvas.drawPath(path, p);
        
        for (final c in corners) {
          canvas.drawCircle(sc(c), 6, Paint()..color = Colors.yellowAccent);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter old) => old.edges != edges;
}
