// photo_editor.dart
// Full-stack mobile photo editing panel — Flutter
// Drop PhotoEditorPage into your app, or run as standalone with main().
//
// Requirements:  flutter >= 3.10 (Dart 3.0)
// Dependencies:  none (pure Flutter)
//
// Architecture:
//   PhotoEditorPage            — root page / orchestrator
//   ├── _TopBar                — filename, undo/redo, export
//   ├── Canvas (Stack)
//   │   ├── _CheckPainter      — transparent-area checker
//   │   ├── InteractiveViewer  — pinch-zoom / pan
//   │   │   └── _LandscapePainter — CSS-art photo (responds to sliders)
//   │   ├── _BeforeAfterToggle
//   │   ├── _ZoomBar
//   │   └── _CanvasInfo
//   ├── _AdjPanel (draggable, snaps 4 heights)
//   │   ├── _PanelTabs  (Develop | Color | Detail)
//   │   └── _PanelContent
//   │       ├── _DevelopTab  → _HistWidget + _PresetsStrip + sliders + _CurveWidget
//   │       ├── _ColorTab    → WB + Color + HSL channels
//   │       └── _DetailTab   → Sharpen + NR + Lens + Grain
//   └── _ToolBar (slide-in, 9 tools)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;

// ─────────────────────────────────────────────────────────────────────────────
// Entry point (remove if embedding as a widget)
// ─────────────────────────────────────────────────────────────────────────────
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF141109),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const _App());
}

class _App extends StatelessWidget {
  const _App();
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: EdC.bg,
          // ignore: deprecated_member_use
          useMaterial3: false,
        ),
        home: const PhotoEditorPage(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Color palette
// ─────────────────────────────────────────────────────────────────────────────
class EdC {
  static const bg    = Color(0xFF0C0A09);
  static const s1    = Color(0xFF141109);
  static const s3    = Color(0xFF241E17);
  static const s4    = Color(0xFF2E281F);
  static const br    = Color(0xFF382E23);
  static const brH   = Color(0xFF4C4132);
  static const gold  = Color(0xFFC9A96E);
  static const goldD = Color(0xFF8A7048);
  static const ember = Color(0xFFE05C3A);
  static const text  = Color(0xFFF0ECE6);
  static const tx2   = Color(0xFFB5A898);
  static const tx3   = Color(0xFF7A6A5A);
  static const red   = Color(0xFFE87A7A);
  static const grn   = Color(0xFF7EC995);
  static const blu   = Color(0xFF7AB8E8);
}

// ─────────────────────────────────────────────────────────────────────────────
// Adjustments model — immutable, copyWith
// ─────────────────────────────────────────────────────────────────────────────
class Adj {
  // Basic  (all in slider-native units)
  final double exposure;   // –500 … +500  (÷100 = EV stop)
  final double contrast;   // –100 … +100
  final double highlights; // –100 … +100
  final double shadows;    // –100 … +100
  final double whites;     // –100 … +100
  final double blacks;     // –100 … +100
  // Color
  final double temperature; // 2000 … 10000 K
  final double tint;        // –100 … +100
  final double saturation;  // –100 … +100
  final double vibrance;    // –100 … +100
  // Detail
  final double sharpening;
  final double detail;
  final double masking;
  final double luminanceNR;
  final double colorNR;
  // Lens & grain
  final double vignette;
  final double grain;

  const Adj({
    this.exposure    = 20,
    this.contrast    = 15,
    this.highlights  = -20,
    this.shadows     = 18,
    this.whites      = 8,
    this.blacks      = -5,
    this.temperature = 5600,
    this.tint        = 8,
    this.saturation  = 12,
    this.vibrance    = 25,
    this.sharpening  = 40,
    this.detail      = 25,
    this.masking     = 60,
    this.luminanceNR = 28,
    this.colorNR     = 35,
    this.vignette    = -22,
    this.grain       = 18,
  });

  Adj copyWith({
    double? exposure, double? contrast, double? highlights, double? shadows,
    double? whites, double? blacks, double? temperature, double? tint,
    double? saturation, double? vibrance, double? sharpening, double? detail,
    double? masking, double? luminanceNR, double? colorNR,
    double? vignette, double? grain,
  }) =>
      Adj(
        exposure    : exposure     ?? this.exposure,
        contrast    : contrast     ?? this.contrast,
        highlights  : highlights   ?? this.highlights,
        shadows     : shadows      ?? this.shadows,
        whites      : whites       ?? this.whites,
        blacks      : blacks       ?? this.blacks,
        temperature : temperature  ?? this.temperature,
        tint        : tint         ?? this.tint,
        saturation  : saturation   ?? this.saturation,
        vibrance    : vibrance     ?? this.vibrance,
        sharpening  : sharpening   ?? this.sharpening,
        detail      : detail       ?? this.detail,
        masking     : masking      ?? this.masking,
        luminanceNR : luminanceNR  ?? this.luminanceNR,
        colorNR     : colorNR      ?? this.colorNR,
        vignette    : vignette     ?? this.vignette,
        grain       : grain        ?? this.grain,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tool definitions
// ─────────────────────────────────────────────────────────────────────────────
class _Tool {
  final IconData icon;
  final String   label;
  const _Tool(this.icon, this.label);
}

const _kTools = [
  _Tool(Icons.near_me_outlined,         'Select'),
  _Tool(Icons.crop_outlined,            'Crop'),
  _Tool(Icons.brush_outlined,           'Brush'),
  _Tool(Icons.auto_fix_normal_outlined, 'Heal'),
  _Tool(Icons.gradient_outlined,        'Grad'),
  _Tool(Icons.colorize_outlined,        'Pick'),
  _Tool(Icons.title_outlined,           'Text'),
  _Tool(Icons.search_outlined,          'Zoom'),
  _Tool(Icons.pan_tool_outlined,        'Hand'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Photo Editor Page
// ─────────────────────────────────────────────────────────────────────────────
class PhotoEditorPage extends StatefulWidget {
  const PhotoEditorPage({super.key});
  @override
  State<PhotoEditorPage> createState() => _PEState();
}

class _PEState extends State<PhotoEditorPage> with TickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────
  Adj  _adj    = const Adj();
  int  _tool   = 0;
  int  _tab    = 0;   // 0=Develop | 1=Color | 2=Detail
  int  _preset = 0;
  bool _before = false;

  // Panel drag (snaps to 4 heights)
  double _panelH = 260;
  static const double _kPanelMin  = 52;
  static const double _kPanelMax  = 400;
  static const List<double> _kSnaps = [_kPanelMin, 180, 260, 360];

  // ── Animation controllers ──────────────────────────────────
  late final AnimationController _tabCtrl;
  late final AnimationController _toolCtrl;
  late final Animation<double>   _tabFade;
  late final Animation<Offset>   _toolSlide;

  final _canvasTx = TransformationController();

  // ── Lifecycle ──────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _tabCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _toolCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));

    _tabFade = CurvedAnimation(parent: _tabCtrl, curve: Curves.easeOut);
    _toolSlide = Tween<Offset>(
      begin: const Offset(0, 1.4),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _toolCtrl, curve: Curves.easeOutCubic));

    _tabCtrl.forward();
    _toolCtrl.forward();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _toolCtrl.dispose();
    _canvasTx.dispose();
    super.dispose();
  }

  // ── Callbacks ──────────────────────────────────────────────
  void _onTool(int i) {
    HapticFeedback.selectionClick();
    setState(() => _tool = i);
  }

  void _onTab(int i) {
    if (_tab == i) return;
    _tabCtrl.reset();
    setState(() => _tab = i);
    _tabCtrl.forward();
  }

  void _onAdj(Adj a)    => setState(() => _adj = a);
  void _onPreset(int i) {
    HapticFeedback.selectionClick();
    setState(() => _preset = i);
  }

  // ── Build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: EdC.bg,
        body: Column(
          children: [
            _TopBar(onExport: () {}),
            Expanded(child: _buildCanvas()),
            _buildPanel(),
          ],
        ),
        bottomNavigationBar: _buildToolBar(),
      ),
    );
  }

  // ── Canvas ──────────────────────────────────────────────────
  Widget _buildCanvas() {
    return RepaintBoundary(
      child: Stack(
        children: [
          // Checkerboard BG
          Positioned.fill(
            child: CustomPaint(painter: _CheckPainter()),
          ),

          // Photo
          Center(
            child: InteractiveViewer(
              transformationController: _canvasTx,
              minScale: 0.4,
              maxScale: 6.0,
              boundaryMargin: const EdgeInsets.all(80),
              child: RepaintBoundary(
                child: Container(
                  width: 340, height: 226,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0xCC000000),
                        blurRadius: 44,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CustomPaint(
                    painter: _LandscapePainter(adj: _adj),
                  ),
                ),
              ),
            ),
          ),

          // Before / After toggle
          Positioned(
            top: 10, left: 10,
            child: _BeforeAfterToggle(
              before: _before,
              onToggle: (v) {
                HapticFeedback.selectionClick();
                setState(() => _before = v);
              },
            ),
          ),

          // Zoom bar
          Positioned(
            top: 10, right: 10,
            child: _ZoomBar(controller: _canvasTx),
          ),

          // Bottom info strip
          Positioned(
            bottom: 10, left: 0, right: 0,
            child: const _CanvasInfo(),
          ),
        ],
      ),
    );
  }

  // ── Adjustments panel ───────────────────────────────────────
  Widget _buildPanel() {
    return GestureDetector(
      // Real-time resize
      onVerticalDragUpdate: (d) => setState(() {
        _panelH = (_panelH - d.delta.dy).clamp(_kPanelMin, _kPanelMax);
      }),
      // Snap on release
      onVerticalDragEnd: (_) {
        final best = _kSnaps.reduce((a, b) =>
            (a - _panelH).abs() < (b - _panelH).abs() ? a : b);
        setState(() => _panelH = best);
        HapticFeedback.lightImpact();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        height: _panelH,
        decoration: const BoxDecoration(
          color: EdC.s1,
          border: Border(top: BorderSide(color: EdC.br)),
        ),
        child: Column(
          children: [
            // Drag handle
            const _DragHandle(),

            // Tabs (only when tall enough)
            if (_panelH > 80)
              _PanelTabs(current: _tab, onTab: _onTab),

            // Content
            if (_panelH > 120)
              Expanded(
                child: FadeTransition(
                  opacity: _tabFade,
                  child: _PanelContent(
                    tab:      _tab,
                    adj:      _adj,
                    onAdj:    _onAdj,
                    preset:   _preset,
                    onPreset: _onPreset,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Tool bar ────────────────────────────────────────────────
  Widget _buildToolBar() {
    return SlideTransition(
      position: _toolSlide,
      child: Container(
        decoration: const BoxDecoration(
          color: EdC.s1,
          border: Border(top: BorderSide(color: EdC.br)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _kTools.asMap().entries
                  .map((e) => _ToolBtn(
                        tool:   e.value,
                        active: _tool == e.key,
                        onTap:  () => _onTool(e.key),
                      ))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top Bar
// ─────────────────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final VoidCallback onExport;
  const _TopBar({required this.onExport});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: EdC.s1,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 52,
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: EdC.br))),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // Back
              _IBtn(icon: Icons.chevron_left_rounded, onTap: () {}),
              const SizedBox(width: 4),

              // Filename + meta
              const Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'coastal_dawn_RAW0492.dng',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: EdC.tx2,
                          letterSpacing: .1),
                    ),
                    Text(
                      'Canon R5 · f/2.8 · 1/250s · ISO 800',
                      style: TextStyle(fontSize: 10, color: EdC.tx3),
                    ),
                  ],
                ),
              ),

              // Undo / Redo
              _IBtn(icon: Icons.undo_rounded, onTap: () {}),
              _IBtn(icon: Icons.redo_rounded, onTap: () {}),
              const SizedBox(width: 8),

              // Export button with glow
              GestureDetector(
                onTap: onExport,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFE8693F), Color(0xFFC44A22)]),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x55E05C3A),
                          blurRadius: 12,
                          offset: Offset(0, 3)),
                    ],
                  ),
                  child: const Text(
                    '↑  Export',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Canvas overlay widgets
// ─────────────────────────────────────────────────────────────────────────────
class _BeforeAfterToggle extends StatelessWidget {
  final bool before;
  final ValueChanged<bool> onToggle;
  const _BeforeAfterToggle({required this.before, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xD8080604),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EdC.br),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ['After', 'Before'].asMap().entries.map((e) {
          final active = (e.key == 1) == before;
          return GestureDetector(
            onTap: () => onToggle(e.key == 1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: active ? EdC.s4 : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                e.value,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: active ? EdC.text : EdC.tx3),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ZoomBar extends StatelessWidget {
  final TransformationController controller;
  const _ZoomBar({required this.controller});

  void _scale(double f) {
    controller.value = controller.value * (Matrix4.identity()..scale(f));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HudBtn(label: '−', onTap: () => _scale(.8)),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xD8080604),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: EdC.br),
          ),
          child: const Text('67%',
              style: TextStyle(
                  fontSize: 11, color: EdC.tx2, fontFamily: 'monospace')),
        ),
        const SizedBox(width: 4),
        _HudBtn(label: '+', onTap: () => _scale(1.25)),
        const SizedBox(width: 4),
        _HudBtn(
            label: '⤢',
            onTap: () => controller.value = Matrix4.identity()),
      ],
    );
  }
}

class _CanvasInfo extends StatelessWidget {
  const _CanvasInfo();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xE0060402),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: EdC.br),
        ),
        child: const Wrap(
          spacing: 10,
          children: [
            _Pill(label: 'px',  value: '6720×4480'),
            _Pill(label: 'R',   value: '218'),
            _Pill(label: 'G',   value: '164'),
            _Pill(label: 'B',   value: '98'),
            _Pill(label: 'ISO', value: '800'),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label, value;
  const _Pill({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
          children: [
            TextSpan(text: '$label ', style: const TextStyle(color: EdC.tx3)),
            TextSpan(text: value,    style: const TextStyle(color: EdC.tx2)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Panel drag handle
// ─────────────────────────────────────────────────────────────────────────────
class _DragHandle extends StatelessWidget {
  const _DragHandle();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Center(
          child: Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: EdC.br, borderRadius: BorderRadius.circular(2)),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Panel tabs
// ─────────────────────────────────────────────────────────────────────────────
class _PanelTabs extends StatelessWidget {
  final int current;
  final ValueChanged<int> onTab;
  const _PanelTabs({required this.current, required this.onTab});

  static const _labels = ['Develop', 'Color', 'Detail'];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: EdC.br))),
      child: Row(
        children: _labels.asMap().entries.map((e) {
          final on = current == e.key;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTab(e.key),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                        color: on ? EdC.gold : Colors.transparent,
                        width: 2),
                  ),
                ),
                child: Text(
                  e.value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .06,
                    color: on ? EdC.gold : EdC.tx3,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Panel content router
// ─────────────────────────────────────────────────────────────────────────────
class _PanelContent extends StatelessWidget {
  final int tab;
  final Adj adj;
  final ValueChanged<Adj> onAdj;
  final int preset;
  final ValueChanged<int> onPreset;

  const _PanelContent({
    required this.tab,
    required this.adj,
    required this.onAdj,
    required this.preset,
    required this.onPreset,
  });

  @override
  Widget build(BuildContext context) {
    final Widget child;
    switch (tab) {
      case 0:
        child = _DevelopTab(adj: adj, onAdj: onAdj, preset: preset, onPreset: onPreset);
        break;
      case 1:
        child = _ColorTab(adj: adj, onAdj: onAdj);
        break;
      case 2:
        child = _DetailTab(adj: adj, onAdj: onAdj);
        break;
      default:
        child = const SizedBox.shrink();
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
      physics: const BouncingScrollPhysics(),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Develop tab
// ─────────────────────────────────────────────────────────────────────────────
class _DevelopTab extends StatelessWidget {
  final Adj adj;
  final ValueChanged<Adj> onAdj;
  final int preset;
  final ValueChanged<int> onPreset;
  const _DevelopTab({required this.adj, required this.onAdj, required this.preset, required this.onPreset});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Histogram
        const _HistWidget(),
        const SizedBox(height: 12),

        // Filter presets
        _PresetsStrip(preset: preset, onPreset: onPreset),
        const SizedBox(height: 14),

        // Basic section
        const _SecLabel('Basic'),
        _SR('Exposure',   adj.exposure,   -500, 500, (v) => onAdj(adj.copyWith(exposure: v)),
            fmt: (v) => v >= 0 ? '+${(v/100).toStringAsFixed(1)}' : (v/100).toStringAsFixed(1)),
        _SR('Contrast',   adj.contrast,   -100, 100, (v) => onAdj(adj.copyWith(contrast: v))),
        _SR('Highlights', adj.highlights, -100, 100, (v) => onAdj(adj.copyWith(highlights: v))),
        _SR('Shadows',    adj.shadows,    -100, 100, (v) => onAdj(adj.copyWith(shadows: v))),
        _SR('Whites',     adj.whites,     -100, 100, (v) => onAdj(adj.copyWith(whites: v))),
        _SR('Blacks',     adj.blacks,     -100, 100, (v) => onAdj(adj.copyWith(blacks: v))),
        const SizedBox(height: 10),

        // Tone curve
        const _SecLabel('Tone Curve'),
        const _CurveWidget(),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Color tab
// ─────────────────────────────────────────────────────────────────────────────
class _ColorTab extends StatefulWidget {
  final Adj adj;
  final ValueChanged<Adj> onAdj;
  const _ColorTab({required this.adj, required this.onAdj});
  @override
  State<_ColorTab> createState() => _ColorTabState();
}

class _ColorTabState extends State<_ColorTab> {
  // Local HSL-per-channel state (UI demo — wire into Adj if needed)
  final Map<String, double> _hsl = {
    'reds': 5, 'oranges': -8, 'yellows': 0, 'greens': 12, 'blues': -15, 'purples': 0,
  };

  static const _channelColors = {
    'reds':    Color(0xFFE87A7A),
    'oranges': Color(0xFFE8A87A),
    'yellows': Color(0xFFE8E07A),
    'greens':  Color(0xFF7EC995),
    'blues':   Color(0xFF7AB8E8),
    'purples': Color(0xFFA87AE8),
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // White balance
        const _SecLabel('White Balance'),
        _SR('Temp', widget.adj.temperature, 2000, 10000,
            (v) => widget.onAdj(widget.adj.copyWith(temperature: v)),
            fmt: (v) => '${v.toStringAsFixed(0)}K'),
        _SR('Tint', widget.adj.tint, -100, 100,
            (v) => widget.onAdj(widget.adj.copyWith(tint: v))),
        const SizedBox(height: 10),

        // Color
        const _SecLabel('Color'),
        _SR('Saturation', widget.adj.saturation, -100, 100,
            (v) => widget.onAdj(widget.adj.copyWith(saturation: v))),
        _SR('Vibrance', widget.adj.vibrance, -100, 100,
            (v) => widget.onAdj(widget.adj.copyWith(vibrance: v))),
        const SizedBox(height: 10),

        // HSL per channel
        const _SecLabel('HSL  ·  Hue'),
        ..._hsl.entries.map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 7, height: 7,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                        color: _channelColors[e.key],
                        borderRadius: BorderRadius.circular(2)),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      _cap(e.key),
                      style: const TextStyle(fontSize: 11, color: EdC.tx3),
                    ),
                  ),
                  Expanded(
                    child: _buildMiniSlider(e.value, -30, 30, (v) {
                      setState(() => _hsl[e.key] = v);
                    }),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 28,
                    child: Text(
                      e.value >= 0 ? '+${e.value.toInt()}' : '${e.value.toInt()}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 10.5, color: EdC.tx2, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  String _cap(String s) => s[0].toUpperCase() + s.substring(1);

  Widget _buildMiniSlider(double val, double min, double max, ValueChanged<double> cb) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        activeTrackColor: EdC.goldD,
        inactiveTrackColor: EdC.s4,
        thumbShape: const _GoldThumb(),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        tickMarkShape: SliderTickMarkShape.noTickMark,
      ),
      child: Slider(
        value: val.clamp(min, max),
        min: min, max: max,
        onChanged: (v) { HapticFeedback.selectionClick(); cb(v); },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Detail tab
// ─────────────────────────────────────────────────────────────────────────────
class _DetailTab extends StatelessWidget {
  final Adj adj;
  final ValueChanged<Adj> onAdj;
  const _DetailTab({required this.adj, required this.onAdj});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SecLabel('Sharpening'),
        _SR('Amount',  adj.sharpening, 0, 150, (v) => onAdj(adj.copyWith(sharpening: v)), fmt: _int),
        _SR('Detail',  adj.detail,     0, 100, (v) => onAdj(adj.copyWith(detail: v)),     fmt: _int),
        _SR('Masking', adj.masking,    0, 100, (v) => onAdj(adj.copyWith(masking: v)),    fmt: _int),
        const SizedBox(height: 10),

        const _SecLabel('Noise Reduction'),
        _SR('Luminance', adj.luminanceNR, 0, 100, (v) => onAdj(adj.copyWith(luminanceNR: v)), fmt: _int),
        _SR('Color',     adj.colorNR,     0, 100, (v) => onAdj(adj.copyWith(colorNR: v)),     fmt: _int),
        const SizedBox(height: 10),

        const _SecLabel('Lens  &  Grain'),
        _SR('Vignette', adj.vignette, -100, 100, (v) => onAdj(adj.copyWith(vignette: v))),
        _SR('Grain',    adj.grain,    0,    100,  (v) => onAdj(adj.copyWith(grain: v)), fmt: _int),
      ],
    );
  }

  static String _int(double v) => v.toInt().toString();
}

// ─────────────────────────────────────────────────────────────────────────────
// Slider row  (_SR)
// ─────────────────────────────────────────────────────────────────────────────
class _SR extends StatelessWidget {
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  final String Function(double)? fmt;

  const _SR(this.label, this.value, this.min, this.max, this.onChanged, {this.fmt});

  String _format(double v) {
    if (fmt != null) return fmt!(v);
    final n = v.toInt();
    return n >= 0 ? '+$n' : '$n';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(fontSize: 11.5, color: EdC.tx3)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                activeTrackColor: EdC.goldD,
                inactiveTrackColor: EdC.s4,
                thumbColor: EdC.text,
                thumbShape: const _GoldThumb(),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 14),
                tickMarkShape: SliderTickMarkShape.noTickMark,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  onChanged(v);
                },
              ),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              _format(value),
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 11, color: EdC.tx2, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label
// ─────────────────────────────────────────────────────────────────────────────
class _SecLabel extends StatelessWidget {
  final String text;
  const _SecLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 2),
        child: Row(
          children: [
            Text(
              text.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: EdC.tx3,
                  letterSpacing: .1),
            ),
            const SizedBox(width: 8),
            const Expanded(
                child: Divider(color: EdC.br, height: 1, thickness: 1)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Presets strip
// ─────────────────────────────────────────────────────────────────────────────
const _kPresets = [
  ('Original',  [Color(0xFF1A3D82), Color(0xFFE8B86A), Color(0xFF4A1C04)]),
  ('Velvet',    [Color(0xFF2D1A2E), Color(0xFF7A4A5A), Color(0xFF3A2018)]),
  ('Cinematic', [Color(0xFF0D2A3A), Color(0xFF2A6A5A), Color(0xFFC46A1A)]),
  ('Chrome',    [Color(0xFF1A1A2E), Color(0xFF4A5A6A), Color(0xFF9AB0C0)]),
  ('Film',      [Color(0xFF2A1A0A), Color(0xFF8A6840), Color(0xFFC09060)]),
  ('Mono',      [Color(0xFF0A0A0A), Color(0xFF4A4A4A), Color(0xFF9A9A9A)]),
  ('Fade',      [Color(0xFF3A3228), Color(0xFF8A7A6A), Color(0xFFB0A090)]),
];

class _PresetsStrip extends StatelessWidget {
  final int preset;
  final ValueChanged<int> onPreset;
  const _PresetsStrip({required this.preset, required this.onPreset});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _kPresets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final on = preset == i;
          final (name, colors) = _kPresets[i];
          return GestureDetector(
            onTap: () => onPreset(i),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 60, height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                        color: on ? EdC.gold : EdC.br, width: on ? 2 : 1.5),
                    gradient: LinearGradient(
                      colors: colors,
                      begin: const Alignment(-1, -1),
                      end: const Alignment(1, 1),
                    ),
                    boxShadow: on
                        ? [BoxShadow(
                            color: EdC.gold.withAlpha(76),
                            blurRadius: 8)]
                        : null,
                  ),
                ),
                const SizedBox(height: 3),
                Text(name,
                    style: TextStyle(
                        fontSize: 9.5,
                        color: on ? EdC.gold : EdC.tx3)),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Histogram widget
// ─────────────────────────────────────────────────────────────────────────────
class _HistWidget extends StatelessWidget {
  const _HistWidget();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Histogram  ·  ACES Log',
                style: TextStyle(
                    fontSize: 10, color: EdC.tx3, fontFamily: 'monospace')),
            Row(children: const [
              _Dot(EdC.red),   SizedBox(width: 5),
              _Dot(EdC.grn),   SizedBox(width: 5),
              _Dot(EdC.blu),   SizedBox(width: 5),
              _Dot(EdC.tx2),
            ]),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            width: double.infinity,
            height: 68,
            child: CustomPaint(painter: _HistPainter()),
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final Color c;
  const _Dot(this.c);
  @override
  Widget build(BuildContext context) => Container(
        width: 7, height: 7,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}

// ─────────────────────────────────────────────────────────────────────────────
// Tone curve widget
// ─────────────────────────────────────────────────────────────────────────────
class _CurveWidget extends StatelessWidget {
  const _CurveWidget();
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          width: double.infinity,
          height: 110,
          child: CustomPaint(painter: _CurvePainter()),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom Painters
// ─────────────────────────────────────────────────────────────────────────────

// Checkerboard
class _CheckPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cell = 16.0;
    final p = Paint();
    for (double x = 0; x < size.width; x += cell) {
      for (double y = 0; y < size.height; y += cell) {
        p.color = ((x / cell).floor() + (y / cell).floor()) % 2 == 0
            ? const Color(0xFF0F0D0C)
            : const Color(0xFF0C0A09);
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), p);
      }
    }
  }
  @override
  bool shouldRepaint(_CheckPainter _) => false;
}

// Photo landscape — responds to exposure / highlights / shadows
class _LandscapePainter extends CustomPainter {
  final Adj adj;
  const _LandscapePainter({required this.adj});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Sky ──
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF070E24), Color(0xFF0D1F4E), Color(0xFF1A3D82),
            Color(0xFF2E6AAE), Color(0xFF73A8CC), Color(0xFFE8B86A),
            Color(0xFFD9784A), Color(0xFF9D4018), Color(0xFF6A2A08),
            Color(0xFF4A1C04), Color(0xFF2E1002),
          ],
          stops: [0, .10, .22, .32, .38, .42, .44, .48, .54, .65, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // ── Sun glow ──
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(.25, -.16),
          colors: [
            const Color(0xFFFFD866).withAlpha(235),
            const Color(0xFFFFA032).withAlpha(140),
            const Color(0xFFFF6414).withAlpha(46),
            Colors.transparent,
          ],
          stops: const [0, .10, .22, .36],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // ── Mountain silhouette ──
    final mp = Path()..moveTo(0, h);
    const pts = [
      [0.00, .78], [.04, .82], [.08, .55], [.12, .70], [.16, .42],
      [.21, .62], [.27, .28], [.33, .50], [.38, .35], [.44, .52],
      [.50, .22], [.57, .44], [.63, .30], [.68, .48], [.74, .18],
      [.80, .38], [.86, .55], [.90, .38], [.94, .52], [.97, .65],
      [1.0, .58], [1.0, 1.0],
    ];
    for (final pt in pts) mp.lineTo(pt[0] * w, pt[1] * h);
    mp.close();
    canvas.drawPath(mp, Paint()..color = const Color(0xFF0F0600));

    // ── Foreground ground ──
    final fp = Path()
      ..moveTo(0, h * .72)
      ..quadraticBezierTo(w * .25, h * .68, w * .5, h * .70)
      ..quadraticBezierTo(w * .75, h * .72, w, h * .68)
      ..lineTo(w, h)..lineTo(0, h)..close();
    canvas.drawPath(
      fp,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3A1C06), Color(0xFF1A0900)],
        ).createShader(Rect.fromLTWH(0, h * .68, w, h * .32)),
    );

    // ── Trees ──
    _tree(canvas, w * .08, h * .72, 14, 30);
    _tree(canvas, w * .14, h * .70, 11, 34);
    _tree(canvas, w * .19, h * .74,  9, 24);
    _tree(canvas, w * .82, h * .70, 14, 32);
    _tree(canvas, w * .88, h * .68, 12, 36);
    _tree(canvas, w * .93, h * .73,  9, 26);

    // ── Water shimmer ──
    final sp = Paint()..color = const Color(0x18FFB850)..strokeWidth = 1;
    for (int i = 0; i < 6; i++) {
      final y = h * .76 + i * 3.5;
      final xo = math.sin(i * 1.1) * w * .04;
      canvas.drawLine(Offset(w * .14 + xo, y), Offset(w * .86 + xo, y), sp);
    }

    // ── Vignette ──
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.transparent, Colors.black.withAlpha(166)],
          stops: const [.5, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // ── Exposure overlay (live feedback) ──
    final t = adj.exposure / 500; // –1 … +1
    if (t.abs() > 0.01) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h),
        Paint()
          ..color = (t > 0 ? Colors.white : Colors.black)
              .withAlpha((t.abs() * 100).round().clamp(0, 255)),
        // Use screen blendMode for brightness lift
      );
    }
  }

  void _tree(Canvas canvas, double x, double baseY, double rx, double ry) {
    final p = Paint()..color = const Color(0xFF040200);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(x, baseY - ry * .42),
            width: rx * 2,
            height: ry * .88),
        p);
    canvas.drawRect(
        Rect.fromCenter(
            center: Offset(x, baseY + ry * .28),
            width: rx * .4,
            height: ry * .6),
        p);
  }

  @override
  bool shouldRepaint(_LandscapePainter old) =>
      old.adj.exposure   != adj.exposure   ||
      old.adj.highlights != adj.highlights ||
      old.adj.shadows    != adj.shadows;
}

// Histogram
class _HistPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h),
        Paint()..color = const Color(0xFF1A1610));

    final g = Paint()..color = const Color(0xFF2D2720)..strokeWidth = 1;
    for (final x in [w * .25, w * .5, w * .75]) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), g);
    }

    _ch(canvas, size,
        [.2, .35, .5, .72, .88, .75, .62, .48, .32],
        EdC.red.withAlpha(140), EdC.red.withAlpha(64));
    _ch(canvas, size,
        [.15, .28, .48, .68, .90, .80, .67, .50, .35],
        EdC.grn.withAlpha(140), EdC.grn.withAlpha(64));
    _ch(canvas, size,
        [.45, .62, .80, .85, .72, .58, .44, .30, .18],
        EdC.blu.withAlpha(140), EdC.blu.withAlpha(64));
    _ch(canvas, size,
        [.22, .38, .55, .78, .88, .74, .60, .45, .28],
        Colors.white.withAlpha(107), Colors.white.withAlpha(20));
  }

  void _ch(Canvas canvas, Size size, List<double> pts,
      Color stroke, Color fill) {
    final w = size.width; final h = size.height;
    final dx = w / (pts.length - 1);

    Path _build() {
      final p = Path()..moveTo(0, h);
      for (int i = 0; i < pts.length; i++) {
        final x = i * dx;
        final y = h - pts[i] * h * .88;
        if (i == 0) {
          p.lineTo(x, y);
        } else {
          final px = (i - 1) * dx;
          final py = h - pts[i - 1] * h * .88;
          final cx = (px + x) / 2;
          p.cubicTo(cx, py, cx, y, x, y);
        }
      }
      return p;
    }

    final area = _build()..lineTo(w, h)..close();
    canvas.drawPath(area, Paint()..color = fill..style = PaintingStyle.fill);
    canvas.drawPath(_build(),
        Paint()
          ..color = stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_HistPainter _) => false;
}

// Tone curve
class _CurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, w, h), const Radius.circular(7)),
      Paint()..color = EdC.s3,
    );

    final g = Paint()..color = EdC.s4..strokeWidth = 1;
    for (final x in [w * .25, w * .5, w * .75]) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), g);
    }
    for (final y in [h * .25, h * .5, h * .75]) {
      canvas.drawLine(Offset(0, y), Offset(w, y), g);
    }

    // Diagonal baseline
    canvas.drawLine(Offset(0, h), Offset(w, 0),
        Paint()
          ..color = EdC.br
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round);

    // S-curve
    final curve = Path()
      ..moveTo(0, h * 1.02)
      ..cubicTo(w * .2, h * .88, w * .3, h * .7,  w * .4,  h * .58)
      ..cubicTo(w * .5, h * .46, w * .6, h * .3,  w * .75, h * .18)
      ..cubicTo(w * .88, h * .08, w * .95, h * .04, w, h * -.02);

    final fill = Path.from(curve)..lineTo(w, h)..close();
    canvas.drawPath(fill, Paint()..color = EdC.gold.withAlpha(20));
    canvas.drawPath(
        curve,
        Paint()
          ..color = EdC.gold.withAlpha(230)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round);

    // Control point dots
    for (final pt in [Offset(w * .38, h * .6), Offset(w * .72, h * .2)]) {
      canvas.drawCircle(pt, 5, Paint()..color = EdC.gold);
      canvas.drawCircle(
          pt, 5,
          Paint()
            ..color = Colors.black.withAlpha(100)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(_CurvePainter _) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom slider thumb — gold ring, white fill, glow on press
// ─────────────────────────────────────────────────────────────────────────────
class _GoldThumb extends SliderComponentShape {
  const _GoldThumb();
  @override
  Size getPreferredSize(bool _, bool __) => const Size(14, 14);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final c = context.canvas;
    // Glow ring
    c.drawCircle(
        center, 9,
        Paint()
          ..color = EdC.gold
              .withAlpha((46 * activationAnimation.value).round()));
    // Drop shadow
    c.drawCircle(center + const Offset(0, .8), 6.5,
        Paint()..color = Colors.black.withAlpha(90));
    // White body
    c.drawCircle(center, 6.5, Paint()..color = EdC.text);
    // Gold ring
    c.drawCircle(
        center, 6.5,
        Paint()
          ..color = EdC.gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable micro-widgets
// ─────────────────────────────────────────────────────────────────────────────
class _IBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 32, height: 32,
          child: Icon(icon, size: 22, color: EdC.tx3),
        ),
      );
}

class _HudBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _HudBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: const Color(0xD8080604),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: EdC.br),
          ),
          child: Center(
            child: Text(label,
                style: const TextStyle(fontSize: 15, color: EdC.tx2)),
          ),
        ),
      );
}

class _ToolBtn extends StatelessWidget {
  final _Tool tool;
  final bool active;
  final VoidCallback onTap;
  const _ToolBtn({required this.tool, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 38, height: 44,
          decoration: BoxDecoration(
            color: active ? EdC.gold.withAlpha(30) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(tool.icon, size: 18, color: active ? EdC.gold : EdC.tx3),
              const SizedBox(height: 2),
              Text(tool.label,
                  style: TextStyle(
                      fontSize: 8.5, color: active ? EdC.gold : EdC.tx3)),
            ],
          ),
        ),
      );
}
