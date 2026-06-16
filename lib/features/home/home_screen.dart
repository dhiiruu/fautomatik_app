import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/app_theme.dart';
import '../edit/config.dart';
import '../magic_portrait/screen.dart';
import '../remove_bg/screen.dart';
import '../auto_crop/screen.dart';
import '../compress/screen.dart';
import '../straighten/screen.dart';
import '../auto_lighting/screen.dart';
import '../sharpen/screen.dart';
import '../skin_smooth/screen.dart';
import '../red_eye_fix/screen.dart';
import '../bg_color/screen.dart';
import '../border/screen.dart';
import '../resize/screen.dart';
import '../convert_format/screen.dart';
import '../print_template_edit/screen.dart';
import '../photo_booth/screen.dart';
import '../camera/screen.dart';
import '../scanner/screen.dart';
import '../editing_panel/photo_editor.dart';

Widget _editScreenFor(EditFeature feature) {
  switch (feature) {
    case EditFeature.magicPortrait: return const MagicPortraitScreen();
    case EditFeature.removeBg: return const RemoveBgScreen();
    case EditFeature.autoCrop: return const AutoCropScreen();
    case EditFeature.compress: return const CompressScreen();
    case EditFeature.straighten: return const StraightenScreen();
    case EditFeature.autoLighting: return const AutoLightingScreen();
    case EditFeature.sharpen: return const SharpenScreen();
    case EditFeature.skinSmooth: return const SkinSmoothScreen();
    case EditFeature.redEyeFix: return const RedEyeFixScreen();
    case EditFeature.bgColor: return const BgColorScreen();
    case EditFeature.border: return const BorderScreen();
    case EditFeature.resize: return const ResizeScreen();
    case EditFeature.convertFormat: return const ConvertFormatScreen();
    case EditFeature.printTemplate: return const PrintTemplateEditScreen();
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late AnimationController _gradientCtrl;
  late Animation<double> _gradientAnim;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _gradientCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 8));
    _gradientAnim = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
      parent: _gradientCtrl, curve: Curves.linear,
    ));
    _gradientCtrl.repeat();
  }

  @override
  void dispose() {
    _gradientCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _gradientAnim,
        builder: (ctx, _) => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(AppTheme.background, AppTheme.surface, _gradientAnim.value)!,
                Color.lerp(AppTheme.surface, AppTheme.background, _gradientAnim.value)!,
              ],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [AppTheme.primary, AppTheme.primaryLight],
                      ),
                      boxShadow: [BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.3),
                        blurRadius: 20,
                        spreadRadius: 4,
                      )],
                    ),
                    child: const Icon(Icons.auto_awesome, color: Colors.white, size: 26),
                  ),
                  const SizedBox(height: 12),
                  const Text('Fautomatik', style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w300, letterSpacing: 2.5, color: AppTheme.textPrimary,
                  )),
                  const SizedBox(height: 4),
                  const Text('Photo Booth & Scanner', style: TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary, letterSpacing: 1,
                  )),
                  const SizedBox(height: 24),

                  _ModeCard(
                    icon: Icons.face_retouching_natural,
                    title: 'Photo Booth',
                    subtitle: 'Guided selfie with face & body detection',
                    color: AppTheme.primary,
                    onTap: () => _navigate(context, const GuidedCameraScreen()),
                  ),
                  const SizedBox(height: 8),
                  _ModeCard(
                    icon: Icons.camera_alt,
                    title: 'Camera',
                    subtitle: 'Standard point-and-shoot',
                    color: AppTheme.secondary,
                    onTap: () => _navigate(context, const PhotoCameraScreen()),
                  ),
                  const SizedBox(height: 8),
                  _ModeCard(
                    icon: Icons.document_scanner,
                    title: 'Scan Photo',
                    subtitle: 'Scan printed photos with auto-crop',
                    color: AppTheme.accent,
                    onTap: () => _navigate(context, const ScanCameraScreen()),
                  ),

                  const SizedBox(height: 8),
                  _ModeCard(
                    icon: Icons.tune,
                    title: 'Photo Editor',
                    subtitle: 'Full editing panel — exposure, color, detail & more',
                    color: AppTheme.success,
                    onTap: () => _navigate(context, const PhotoEditorPage()),
                  ),

                  const SizedBox(height: 24),
                  Row(children: [
                    Container(width: 20, height: 2, decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(1), color: AppTheme.primary.withValues(alpha: 0.4),
                    )),
                    const SizedBox(width: 10),
                    const Text('EDIT TOOLS', style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.5, color: AppTheme.textSecondary,
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: Container(height: 1, color: AppTheme.surfaceBorder.withValues(alpha: 0.3))),
                  ]),
                  const SizedBox(height: 16),

                  ..._buildFeatureGrid(context),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFeatureGrid(BuildContext context) {
    final features = FeatureConfig.all;
    final rows = <Widget>[];
    for (var i = 0; i < features.length; i += 2) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(child: _FeatureCard(config: features[i], onTap: () => _navigate(context, _editScreenFor(features[i].feature)))),
            const SizedBox(width: 8),
            if (i + 1 < features.length)
              Expanded(child: _FeatureCard(config: features[i + 1], onTap: () => _navigate(context, _editScreenFor(features[i + 1].feature))))
            else
              const Expanded(child: SizedBox()),
          ],
        ),
      ));
    }
    return rows;
  }

  void _navigate(BuildContext context, Widget screen) {
    if (_navigating) return;
    _navigating = true;
    HapticFeedback.lightImpact();
    Navigator.push(context, PageRouteBuilder(
      pageBuilder: (_, _, _) => screen,
      transitionsBuilder: (_, anim, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
          CurvedAnimation(parent: anim, curve: Curves.easeOut),
        ),
        child: FadeTransition(opacity: anim, child: child),
      ),
      transitionDuration: const Duration(milliseconds: 300),
    )).then((_) => _navigating = false);
  }
}

class _ModeCard extends StatefulWidget {
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ModeCard({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard> with SingleTickerProviderStateMixin {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.97),
      onTapUp: (_) { setState(() => _scale = 1); widget.onTap(); },
      onTapCancel: () => setState(() => _scale = 1),
      child: AnimatedScale(scale: _scale, duration: const Duration(milliseconds: 100),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.surfaceBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title, style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15, color: AppTheme.textPrimary,
                      )),
                      const SizedBox(height: 2),
                      Text(widget.subtitle, style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary,
                      )),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey[700], size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatefulWidget {
  final FeatureConfig config;
  final VoidCallback onTap;

  const _FeatureCard({required this.config, required this.onTap});

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> with SingleTickerProviderStateMixin {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.95),
      onTapUp: (_) { setState(() => _scale = 1); widget.onTap(); },
      onTapCancel: () => setState(() => _scale = 1),
      child: AnimatedScale(scale: _scale, duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.surfaceBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: widget.config.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.config.icon, color: widget.config.color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(widget.config.title, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                maxLines: 2, overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(widget.config.subtitle, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
