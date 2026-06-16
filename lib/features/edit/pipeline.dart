import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../../core/types.dart';
import '../auto_crop/process.dart' show autoCrop;
import '../straighten/process.dart' show rotateStraight;
import '../auto_lighting/process.dart' show applyLighting;
import '../sharpen/process.dart' show sharpenImage;
import '../skin_smooth/process.dart' show skinSmooth;
import '../red_eye_fix/process.dart' show fixRedEye;
import '../resize/process.dart' show resizeImage;
import '../remove_bg/process.dart' show replaceBackground;
import '../border/process.dart' show addBorder;
import 'edit_config.dart';
import '../../shared/encoding/image_encoder.dart';

Future<Uint8List> runPipeline({
  required Uint8List sourceBytes,
  required int sourceWidth,
  required int sourceHeight,
  Uint8List? maskBytes,
  int? maskWidth,
  int? maskHeight,
  FaceData? faceData,
  required EditConfig config,
}) async {
  var image = img.decodeImage(sourceBytes);
  if (image == null) return sourceBytes;

  final hasMask = maskBytes != null && maskWidth != null && maskHeight != null;

  if (faceData != null && config.straighten != null) {
    image = rotateStraight(image, 0.0);
  }

  if (faceData != null && config.crop != null) {
    image = await autoCrop(image, faceData, config.crop!);
  }

  if (config.resize != null) {
    image = resizeImage(image, config.resize!);
  }

  if (hasMask) {
    image = replaceBackground(image, maskBytes, maskWidth, maskHeight, config.background);
  } else if (config.background != null) {
    final result = img.Image.fromBytes(
      width: image.width, height: image.height,
      bytes: Uint8List(image.width * image.height * 4).buffer, numChannels: 4,
    );
    final raw = result.getBytes();
    final r = (config.background!.color >> 16) & 0xFF;
    final g = (config.background!.color >> 8) & 0xFF;
    final b = config.background!.color & 0xFF;
    for (int i = 0; i < raw.length; i += 4) {
      raw[i] = r;
      raw[i + 1] = g;
      raw[i + 2] = b;
      raw[i + 3] = 255;
    }
    image = result;
  }

  if (config.lighting != null) {
    image = applyLighting(image, config.lighting!);
  }

  if (config.sharpen != null) {
    image = sharpenImage(image, config.sharpen!);
  }

  if (config.skinSmooth != null) {
    image = skinSmooth(image, config.skinSmooth!);
  }

  if (faceData != null && config.redEye != null) {
    image = fixRedEye(image, faceData);
  }

  if (config.border != null) {
    image = addBorder(image, config.border!);
  }

  return encodeOutput(image, config.output);
}
