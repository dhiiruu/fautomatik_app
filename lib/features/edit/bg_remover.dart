import 'dart:typed_data';
import '../../core/types.dart';

abstract class BackgroundRemover {
  Future<void> load();
  Future<MaskData> process(Uint8List imageBytes, int width, int height);
  void dispose();
}
