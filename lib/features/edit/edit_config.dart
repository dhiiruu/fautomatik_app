import 'dart:typed_data';

class StraightenConfig {
  const StraightenConfig();
}

class CropConfig {
  final int outputWidth;
  final int outputHeight;

  const CropConfig({required this.outputWidth, required this.outputHeight});
}

class ResizeConfig {
  final int? width;
  final int? height;
  final bool maintainAspect;

  const ResizeConfig({this.width, this.height, this.maintainAspect = false});
}

class BackgroundConfig {
  final int color;
  final Uint8List? imageBytes;
  final double maskThreshold;
  final int featherRadius;

  const BackgroundConfig({
    this.color = 0xFF000000,
    this.imageBytes,
    this.maskThreshold = 0.5,
    this.featherRadius = 3,
  });
}

class LightingConfig {
  final double brightness;
  final double contrast;
  final bool autoLevels;

  const LightingConfig({
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.autoLevels = false,
  });
}

class SharpenConfig {
  final double amount;

  const SharpenConfig({this.amount = 0.5});
}

class SkinSmoothConfig {
  final double amount;
  final int radius;

  const SkinSmoothConfig({this.amount = 0.3, this.radius = 2});
}

class RedEyeConfig {
  const RedEyeConfig();
}

class BorderConfig {
  final int color;
  final int width;

  const BorderConfig({this.color = 0xFFFFFFFF, this.width = 10});
}

class OutputConfig {
  final String format;
  final int quality;
  final int? maxSizeKB;
  final double dpi;

  const OutputConfig({
    this.format = 'png',
    this.quality = 95,
    this.maxSizeKB,
    this.dpi = 300,
  });
}

class EditConfig {
  final StraightenConfig? straighten;
  final CropConfig? crop;
  final ResizeConfig? resize;
  final BackgroundConfig? background;
  final LightingConfig? lighting;
  final SharpenConfig? sharpen;
  final SkinSmoothConfig? skinSmooth;
  final RedEyeConfig? redEye;
  final BorderConfig? border;
  final OutputConfig? output;

  const EditConfig({
    this.straighten,
    this.crop,
    this.resize,
    this.background,
    this.lighting,
    this.sharpen,
    this.skinSmooth,
    this.redEye,
    this.border,
    this.output,
  });
}
