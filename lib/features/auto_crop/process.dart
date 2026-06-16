import 'package:image/image.dart' as img;
import '../../shared/processing/image_resize_isolate.dart';
import '../edit/edit_config.dart';
import '../../core/types.dart';

Future<img.Image> autoCrop(img.Image src, FaceData face, CropConfig config) async {
  final bb = face.boundingBox;
  final outRatio = config.outputWidth / config.outputHeight;

  // Face should occupy ~65% of the output frame (passport/ID standard)
  const idealFaceRatio = 0.65;
  // Eye line positioned at ~45% from top of frame (headroom above)
  const eyeLineFromTop = 0.45;

  // Estimate face height from bounding box and determine ideal crop
  var cropH = bb.height / idealFaceRatio;
  var cropW = cropH * outRatio;

  // If face width is the tighter constraint, recalculate
  if (cropW < bb.width) {
    cropW = bb.width / 0.8; // face occupies 80% of crop width
    cropH = cropW / outRatio;
  }

  // Clamp crop to source, maintaining aspect ratio
  if (cropW > src.width) {
    cropW = src.width.toDouble();
    cropH = cropW / outRatio;
  }
  if (cropH > src.height) {
    cropH = src.height.toDouble();
    cropW = cropH * outRatio;
  }

  // Eye Y: roughly 35% from top of face bounding box
  final eyeY = bb.top + bb.height * 0.35;

  // Position the crop so the eye line lands at eyeLineFromTop
  var cropTop = eyeY - cropH * eyeLineFromTop;
  var cropLeft = bb.center.dx - cropW / 2;

  // Clamp to image edges — if there isn't enough room the composition
  // degrades gracefully (less headroom or less shoulder) rather than
  // producing an invalid crop.
  cropLeft = cropLeft.clamp(0.0, (src.width - cropW).toDouble());
  cropTop = cropTop.clamp(0.0, (src.height - cropH).toDouble());

  // Crop on main thread (cheap byte copy), then resize in isolate
  final cropped = img.copyCrop(
    src,
    x: cropLeft.round(),
    y: cropTop.round(),
    width: cropW.round(),
    height: cropH.round(),
  );

  final resizedBytes = await resizeImageInIsolate(
    bytes: cropped.getBytes(),
    srcW: cropped.width,
    srcH: cropped.height,
    dstW: config.outputWidth,
    dstH: config.outputHeight,
  );

  return img.Image.fromBytes(
    width: config.outputWidth,
    height: config.outputHeight,
    bytes: resizedBytes.buffer,
    numChannels: 4,
  );
}
