import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'guidance_checker.dart';
import 'pipeline.dart';
import 'pose_checker.dart';
import '../../core/types.dart';
import '../../shared/face/face_pipeline.dart';
import '../camera/camera_engine.dart';
import '../../shared/audio/audio_guide.dart';
import '../../core/app_theme.dart';
import '../../shared/widgets/app_widgets.dart';
import '../../shared/widgets/photo_preview_sheet.dart';

class GuidedCameraScreen extends StatefulWidget {
  final CameraLens initialLens;
  const GuidedCameraScreen({super.key, this.initialLens = CameraLens.front});

  @override
  State<GuidedCameraScreen> createState() => _GuidedCameraScreenState();
}

class _GuidedCameraScreenState extends State<GuidedCameraScreen> with WidgetsBindingObserver {
  final CameraEngine _engine = CameraEngine();
  final MediaPipeFacePipeline _facePipeline = MediaPipeFacePipeline();
  final GuidanceChecker _guidanceChecker = GuidanceChecker();
  final BodyPipeline _bodyPipeline = BodyPipeline();
  final PoseChecker _poseChecker = PoseChecker();
  final AudioGuide _audioGuide = AudioGuide();

  StreamSubscription<ProcessedFrame>? _frameSub;
  GuidanceResult _lastGuidance = const GuidanceResult();
  GuidanceResult _stableGuidance = const GuidanceResult();
  PoseCheckResult _lastPose = const PoseCheckResult();
  BodyData _lastBody = const BodyData();
  FaceData? _lastFace;
  bool _isReady = false;
  String _error = '';
  bool _pipelineLoading = true;
  bool _autoCaptureEnabled = false;
  int _stableFrames = 0;
  int _showPreview = -1; // -1=no, 0=capturing, 1=captured
  String? _capturedPath;
  bool _muted = false;

  static const int stableFramesNeeded = 10;
  static const int autoCaptureDelayMs = 1500;

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
    _captureTimer?.cancel();
    _facePipeline.dispose();
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

  Future<void> _init() async {
    try {
      await Future.wait([_facePipeline.load(), _bodyPipeline.load()]);
      if (mounted) setState(() => _pipelineLoading = false);
      await _engine.init(lens: widget.initialLens);
      if (mounted) setState(() => _isReady = true);
      await _startDetection();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _startDetection() async {
    await _engine.startFrameStream(
      onFaceDetect: (b, w, h) => _facePipeline.process(b, w, h),
      onRawFrame: (nv21, w, h, stride) {
        _bodyPipeline.process(nv21Bytes: nv21, width: w, height: h, yRowStride: stride)
          .then((body) { if (mounted) setState(() => _lastBody = body); });
      },
      throttleMs: 150,
    );
    _frameSub = _engine.frameStream?.listen((frame) {
      if (!mounted) return;
      final g = _guidanceChecker.check(
        frameW: frame.width, frameH: frame.height, face: frame.face,
        frameBytes: frame.rgbaBytes, isMirrored: frame.isMirrored,
      );
      _lastFace = frame.face;
      final pose = _poseChecker.check(frameW: frame.width, frameH: frame.height, body: _lastBody);
      _lastPose = pose;
      final allGood = g.allGood && pose.allGood;
      if (allGood) { _stableFrames++; if (_stableFrames >= 3) _stableGuidance = g; }
      else { _stableFrames = 0; }
      setState(() {
        final prev = _lastGuidance;
        _lastGuidance = g;
        if (prev.faceDetected != g.faceDetected || prev.faceCentered != g.faceCentered ||
            prev.faceSized != g.faceSized || prev.headLevel != g.headLevel ||
            prev.eyesOpen != g.eyesOpen || prev.neutralExpression != g.neutralExpression ||
            prev.brightnessOk != g.brightnessOk || prev.backlit != g.backlit) {
          if (!_muted) _audioGuide.speak(_instructionText(g));
        }
      });
    });
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
    if (g.hasShadow) return 'Move to even lighting';
    if (!_lastPose.bodyDetected) return 'Step into the frame';
    if (!_lastPose.fullBodyVisible) return 'Step back to show full body';
    if (!_lastPose.centered) return 'Center your body';
    if (!_lastPose.upright) return 'Stand up straight';
    if (!_lastPose.armsDown) return 'Lower your arms';
    if (_autoCaptureEnabled) return 'Hold still...';
    return 'Looks good!';
  }

  Timer? _captureTimer;

  Future<void> _capture() async {
    if (_engine.isCapturing) return;
    setState(() => _showPreview = 0);
    try {
      final result = await _engine.takePhoto();
      if (!mounted) return;
      setState(() { _capturedPath = result.filePath; _showPreview = 1; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _toggleAutoCapture() {
    setState(() { _autoCaptureEnabled = !_autoCaptureEnabled; _stableFrames = 0; });
    if (_autoCaptureEnabled) { _scheduleAutoCapture(); }
    else { _captureTimer?.cancel(); }
  }

  void _scheduleAutoCapture() {
    _captureTimer?.cancel();
    if (!_autoCaptureEnabled) return;
    _captureTimer = Timer(const Duration(milliseconds: autoCaptureDelayMs), () {
      if (!mounted || !_autoCaptureEnabled) return;
      if (_stableGuidance.allGood && _lastPose.allGood) { _capture(); } else { _scheduleAutoCapture(); }
    });
  }

  Future<void> _switchCamera() async {
    _frameSub?.cancel(); _frameSub = null; setState(() => _isReady = false);
    await _engine.switchCamera();
    setState(() => _isReady = true);
    await _startDetection();
  }

  @override
  Widget build(BuildContext context) {
    if (_error.isNotEmpty) return _buildError();
    if (_showPreview == 1 && _capturedPath != null) {
      return Stack(children: [
        if (_engine.controller != null) Positioned.fill(child: _buildPreview()),
        PhotoPreviewSheet(
          photoPath: _capturedPath!,
          onRetake: () => setState(() { _showPreview = -1; _capturedPath = null; _init(); }),
        ),
      ]);
    }
    return Scaffold(
      body: Stack(children: [
        if (_isReady && _engine.controller != null)
          Positioned.fill(child: ClipRect(child: _buildPreview()))
        else
          Center(child: _pipelineLoading
            ? const Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(), SizedBox(height: 12),
                Text('Loading...', style: TextStyle(color: AppTheme.textSecondary)),
              ])
            : const CircularProgressIndicator()),
        if (_isReady) Positioned.fill(child: _buildOverlay()),
        if (_isReady) _buildTopBar(),
        if (_isReady) _buildGuidancePanel(),
        if (_isReady) _buildBottomBar(),
      ]),
    );
  }

  Widget _buildPreview() {
    final ctrl = _engine.controller;
    if (ctrl == null) return const SizedBox();
    final ar = ctrl.value.previewSize != null ? ctrl.value.aspectRatio : 1.0;
    return AspectRatio(aspectRatio: ar, child: CameraPreview(ctrl));
  }

  Widget _buildOverlay() => LayoutBuilder(builder: (ctx, c) => CustomPaint(
    size: Size(c.maxWidth, c.maxHeight),
    painter: _GuidanceOverlayPainter(
      guidance: _lastGuidance, face: _lastFace, body: _lastBody,
      viewWidth: c.maxWidth, viewHeight: c.maxHeight,
      isMirrored: _engine.lens == CameraLens.front,
      autoCaptureEnabled: _autoCaptureEnabled, stableFrames: _stableFrames, stableFramesNeeded: stableFramesNeeded,
    ),
  ));

  Widget _buildTopBar() => Positioned(
    top: MediaQuery.of(context).padding.top + 8, left: 16, right: 16,
    child: Row(children: [
      _topBtn(Icons.arrow_back, () => Navigator.pop(context)),
      const Spacer(),
      if (_autoCaptureEnabled)
        CountdownPill(
          text: 'Auto $_stableFrames/$stableFramesNeeded',
          color: _stableGuidance.allGood && _lastPose.allGood ? AppTheme.success : AppTheme.warning,
          icon: Icons.timer,
        ),
      const SizedBox(width: 8),
      if (_engine.isCapturing)
        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
    ]),
  );

  Widget _buildGuidancePanel() => Positioned(
    left: 20, right: 20, bottom: 100,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(child: Text(_instructionText(_lastGuidance),
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            )),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _muted = !_muted),
              child: Icon(_muted ? Icons.volume_off : Icons.volume_up, color: Colors.white54, size: 18),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 5, runSpacing: 4, alignment: WrapAlignment.center, children: [
        IndicatorChip(label: 'Face', ok: _lastGuidance.faceDetected),
        IndicatorChip(label: 'Center', ok: _lastGuidance.faceCentered),
        IndicatorChip(label: 'Size', ok: _lastGuidance.faceSized),
        IndicatorChip(label: 'Level', ok: _lastGuidance.headLevel),
        IndicatorChip(label: 'Eyes', ok: _lastGuidance.eyesOpen),
        IndicatorChip(label: 'Face', ok: _lastGuidance.neutralExpression),
        IndicatorChip(label: 'Light', ok: _lastGuidance.brightnessOk),
        IndicatorChip(label: 'Backlit', ok: !_lastGuidance.backlit),
        IndicatorChip(label: 'Body', ok: _lastPose.bodyDetected),
        IndicatorChip(label: 'Full', ok: _lastPose.fullBodyVisible),
        IndicatorChip(label: 'Upright', ok: _lastPose.upright),
        IndicatorChip(label: 'Arms', ok: _lastPose.armsDown),
      ]),
    ]),
  );

  Widget _buildBottomBar() => Positioned(
    left: 0, right: 0, bottom: 0,
    child: Container(
      padding: EdgeInsets.only(left: 24, right: 24, top: 12, bottom: MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0), Colors.black.withValues(alpha: 0.5)],
        ),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _bottomBtn(Icons.flip_camera_android, _switchCamera),
        GestureDetector(
          onTapDown: (_) => HapticFeedback.heavyImpact(),
          onTap: _engine.isCapturing ? null : _capture,
          child: Container(
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
        _bottomBtn(
          _autoCaptureEnabled ? Icons.timer : Icons.timer_off,
          _toggleAutoCapture,
          color: _autoCaptureEnabled ? AppTheme.success : Colors.white54,
        ),
      ]),
    ),
  );

  Widget _bottomBtn(IconData icon, VoidCallback onTap, {Color? color}) => IconButton(
    icon: Icon(icon, color: color ?? Colors.white, size: 26), onPressed: onTap,
  );

  Widget _topBtn(IconData icon, VoidCallback onTap) => Container(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.3),
      shape: BoxShape.circle,
    ),
    child: IconButton(icon: Icon(icon, color: Colors.white, size: 22), onPressed: onTap, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 40, minHeight: 40)),
  );

  Widget _buildError() => Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
    const SizedBox(height: 12), Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
    const SizedBox(height: 20), FilledButton.icon(onPressed: () { setState(() => _error = ''); _init(); }, icon: const Icon(Icons.refresh), label: const Text('Retry')),
  ])));
}

class _GuidanceOverlayPainter extends CustomPainter {
  final GuidanceResult guidance;
  final FaceData? face;
  final BodyData body;
  final double viewWidth, viewHeight;
  final bool isMirrored;
  final bool autoCaptureEnabled;
  final int stableFrames, stableFramesNeeded;

  _GuidanceOverlayPainter({
    required this.guidance, this.face, this.body = const BodyData(),
    required this.viewWidth, required this.viewHeight, required this.isMirrored,
    this.autoCaptureEnabled = false, this.stableFrames = 0, this.stableFramesNeeded = 10,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawFaceGuide(canvas, size);
    if (face != null) { _drawFaceMesh(canvas, size); _drawTiltIndicator(canvas, size); }
    if (body.detected) _drawBodySkeleton(canvas, size);
    if (autoCaptureEnabled) _drawAutoCaptureProgress(canvas, size);
  }

  void _drawFaceGuide(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final idealW = size.width * 0.25, idealH = idealW * 1.3;
    final paint = Paint()
      ..color = guidance.faceDetected ? Colors.greenAccent.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke ..strokeWidth = 2;
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: idealW, height: idealH), paint);
    if (guidance.faceDetected && !guidance.faceCentered) {
      final dx = guidance.faceOffsetFraction;
      if (dx.abs() > 0.05) {
        final p = Paint()..color = Colors.orangeAccent.withValues(alpha: 0.5)..strokeWidth = 3;
        final d = dx > 0 ? -1.0 : 1.0;
        canvas.drawLine(Offset(cx + d * 40, cy), Offset(cx + d * 20, cy), p);
      }
    }
  }

  void _drawFaceMesh(Canvas canvas, Size size) {
    if (face == null || face!.landmarks.length < 468) return;
    final sx = size.width / viewWidth, sy = size.height / viewHeight;
    final p = Paint()..color = Colors.cyanAccent.withValues(alpha: 0.4)..strokeWidth = 1;
    final path = Path();
    const contour = [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109, 10];
    for (var i = 0; i < contour.length; i++) {
      final pt = face!.landmarks[contour[i]];
      final x = (isMirrored ? viewWidth - pt.dx : pt.dx) * sx, y = pt.dy * sy;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close(); canvas.drawPath(path, p);
    _drawEyeContour(canvas, [33, 160, 158, 133, 153, 144], sx, sy);
    _drawEyeContour(canvas, [362, 385, 387, 263, 373, 380], sx, sy);
    _drawEyeContour(canvas, [61, 185, 40, 39, 37, 0, 267, 269, 270, 409, 291, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291], sx, sy);
  }

  void _drawEyeContour(Canvas canvas, List<int> indices, double sx, double sy) {
    if (face == null) return;
    final p = Paint()..color = Colors.yellowAccent.withValues(alpha: 0.5)..strokeWidth = 1.5..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < indices.length; i++) {
      final pt = face!.landmarks[indices[i]];
      final x = (isMirrored ? viewWidth - pt.dx : pt.dx) * sx, y = pt.dy * sy;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close(); canvas.drawPath(path, p);
  }

  void _drawTiltIndicator(Canvas canvas, Size size) {
    if (face == null || face!.landmarks.length < 468) return;
    final sx = size.width / viewWidth, sy = size.height / viewHeight;
    final l = face!.landmarks[33], r = face!.landmarks[263];
    final lx = (isMirrored ? viewWidth - l.dx : l.dx) * sx, ly = l.dy * sy;
    final rx = (isMirrored ? viewWidth - r.dx : r.dx) * sx, ry = r.dy * sy;
    final p = Paint()..color = guidance.headLevel ? Colors.greenAccent : Colors.redAccent ..strokeWidth = 2;
    canvas.drawLine(Offset(lx, ly), Offset(rx, ry), p);
  }

  void _drawBodySkeleton(Canvas canvas, Size size) {
    final sx = size.width / viewWidth, sy = size.height / viewHeight;
    final jointP = Paint()..color = Colors.limeAccent.withValues(alpha: 0.6)..strokeWidth = 2;
    final boneP = Paint()..color = Colors.limeAccent.withValues(alpha: 0.35)..strokeWidth = 2;
    final lm = body.landmarks;
    const pairs = [
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
      [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
      [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
      [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
      [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
      [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
      [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
      [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
    ];
    Offset sc(double x, double y) => Offset((isMirrored ? viewWidth - x : x) * sx, y * sy);
    for (final pair in pairs) {
      final p1 = lm[pair[0]], p2 = lm[pair[1]];
      if (p1 != null && p2 != null && p1.likelihood > 0.3 && p2.likelihood > 0.3) {
        canvas.drawLine(sc(p1.x, p1.y), sc(p2.x, p2.y), boneP);
      }
    }
    for (final e in lm.entries) {
      if (e.value.likelihood > 0.3) canvas.drawCircle(sc(e.value.x, e.value.y), 3, jointP);
    }
  }

  void _drawAutoCaptureProgress(Canvas canvas, Size size) {
    final progress = (stableFrames / stableFramesNeeded).clamp(0.0, 1.0);
    final p = Paint()..color = Colors.greenAccent.withValues(alpha: 0.25 * progress)..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: size.width * (0.5 + 0.3 * progress), height: size.height * (0.5 + 0.3 * progress)),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _GuidanceOverlayPainter old) =>
    old.guidance != guidance || old.face != face || old.body.detected != body.detected || old.stableFrames != stableFrames;
}
