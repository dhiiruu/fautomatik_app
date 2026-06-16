import 'dart:typed_data';
import '../../core/types.dart';

abstract class FacePipeline {
  Future<void> load();
  Future<List<FaceData>> process(Uint8List imageBytes, int width, int height);
  void dispose();
}
