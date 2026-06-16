export 'edit_config.dart';
export 'pipeline.dart' show runPipeline;

import 'dart:typed_data';
import '../../core/types.dart';
import 'edit_config.dart';
import 'pipeline.dart';

class PhotoEditor {
  Future<Uint8List> edit({
    required Uint8List sourceBytes,
    required int sourceWidth,
    required int sourceHeight,
    Uint8List? maskBytes,
    int? maskWidth,
    int? maskHeight,
    FaceData? faceData,
    required EditConfig config,
  }) async {
    return runPipeline(
      sourceBytes: sourceBytes,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      maskBytes: maskBytes,
      maskWidth: maskWidth,
      maskHeight: maskHeight,
      faceData: faceData,
      config: config,
    );
  }
}
