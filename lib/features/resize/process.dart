import 'package:image/image.dart' as img;
import '../edit/edit_config.dart';

img.Image resizeImage(img.Image src, ResizeConfig config) {
  return img.copyResize(
    src,
    width: config.width,
    height: config.height,
    maintainAspect: config.maintainAspect,
    interpolation: img.Interpolation.linear,
  );
}
