import 'package:flutter/material.dart';

enum EditFeature {
  magicPortrait,
  removeBg,
  autoCrop,
  compress,
  straighten,
  autoLighting,
  sharpen,
  skinSmooth,
  redEyeFix,
  bgColor,
  border,
  resize,
  convertFormat,
  printTemplate,
}

class FeatureConfig {
  final EditFeature feature;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String description;

  const FeatureConfig({
    required this.feature,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.description,
  });

  static const List<FeatureConfig> all = [
    FeatureConfig(
      feature: EditFeature.magicPortrait,
      title: 'Magic Portrait',
      subtitle: 'One-tap AI enhancement',
      icon: Icons.auto_fix_high,
      color: Color(0xFF7C4DFF),
      description: 'Automatically enhances your portrait with all tools at once — straighten, crop, lighting, sharpen, skin smooth, and more.',
    ),
    FeatureConfig(
      feature: EditFeature.removeBg,
      title: 'Remove BG',
      subtitle: 'Remove background',
      icon: Icons.cut,
      color: Color(0xFF00E676),
      description: 'Remove the background from your photo using AI.',
    ),
    FeatureConfig(
      feature: EditFeature.autoCrop,
      title: 'Auto Crop',
      subtitle: 'Smart face-based crop',
      icon: Icons.crop,
      color: Color(0xFF00BFA5),
      description: 'Automatically crop your photo to a target size using face detection.',
    ),
    FeatureConfig(
      feature: EditFeature.compress,
      title: 'Compress',
      subtitle: 'Reduce file size',
      icon: Icons.compress,
      color: Color(0xFFFFAB00),
      description: 'Compress your photo to a target file size (KB/MB).',
    ),
    FeatureConfig(
      feature: EditFeature.straighten,
      title: 'Straighten',
      subtitle: 'Auto head tilt correction',
      icon: Icons.straighten,
      color: Color(0xFFFF5252),
      description: 'Auto-detect and correct head tilt or horizon.',
    ),
    FeatureConfig(
      feature: EditFeature.autoLighting,
      title: 'Auto Lighting',
      subtitle: 'Balance brightness & contrast',
      icon: Icons.brightness_high,
      color: Color(0xFFFFD740),
      description: 'Auto balance brightness, contrast, and shadows.',
    ),
    FeatureConfig(
      feature: EditFeature.sharpen,
      title: 'Sharpen',
      subtitle: 'Smart sharpening',
      icon: Icons.blur_on,
      color: Color(0xFFB388FF),
      description: 'Apply smart sharpening to enhance details.',
    ),
    FeatureConfig(
      feature: EditFeature.skinSmooth,
      title: 'Skin Smooth',
      subtitle: 'Subtle skin smoothing',
      icon: Icons.face,
      color: Color(0xFFCE93D8),
      description: 'Subtle skin blemish and pore smoothing.',
    ),
    FeatureConfig(
      feature: EditFeature.redEyeFix,
      title: 'Red-Eye Fix',
      subtitle: 'Remove red eyes',
      icon: Icons.visibility,
      color: Color(0xFFEF5350),
      description: 'Auto detect and remove red-eye from flash photos.',
    ),
    FeatureConfig(
      feature: EditFeature.bgColor,
      title: 'BG Color',
      subtitle: 'Change background color',
      icon: Icons.color_lens,
      color: Color(0xFF42A5F5),
      description: 'Change the background to a solid color of your choice.',
    ),
    FeatureConfig(
      feature: EditFeature.border,
      title: 'Border',
      subtitle: 'Add photo border',
      icon: Icons.border_style,
      color: Color(0xFF66BB6A),
      description: 'Add a border to your photo with customizable color and width.',
    ),
    FeatureConfig(
      feature: EditFeature.resize,
      title: 'Resize',
      subtitle: 'Scale to dimensions',
      icon: Icons.photo_size_select_large,
      color: Color(0xFF26A69A),
      description: 'Scale your photo to specific width and height.',
    ),
    FeatureConfig(
      feature: EditFeature.convertFormat,
      title: 'Convert Format',
      subtitle: 'PNG / JPG / WEBP',
      icon: Icons.swap_horiz,
      color: Color(0xFF78909C),
      description: 'Convert your photo between PNG, JPG, and WEBP formats.',
    ),
    FeatureConfig(
      feature: EditFeature.printTemplate,
      title: 'Print Template',
      subtitle: 'Layout for printing',
      icon: Icons.dashboard,
      color: Color(0xFF7C4DFF),
      description: 'Layout your photo(s) onto a printable template with auto-arrangement.',
    ),
  ];
}
