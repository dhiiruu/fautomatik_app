import 'dart:typed_data';
import 'types.dart';
import '../features/edit/bg_remover.dart';
import '../shared/face/face_pipeline_interface.dart';

class InferencePipeline {
  final BackgroundRemover? _bgRemover;
  final FacePipeline? _facePipeline;

  InferencePipeline({BackgroundRemover? bgRemover, FacePipeline? facePipeline})
      : _bgRemover = bgRemover,
        _facePipeline = facePipeline;

  Future<void> load() async {
    await Future.wait([
      if (_bgRemover != null) _bgRemover.load(),
      if (_facePipeline != null) _facePipeline.load(),
    ]);
  }

  Future<PipelineResult> process(Uint8List imageBytes, int width, int height) async {
    final stopwatch = Stopwatch()..start();

    final results = await Future.wait([
      if (_bgRemover != null)
        _bgRemover.process(imageBytes, width, height),
      if (_facePipeline != null)
        _facePipeline.process(imageBytes, width, height),
    ]);

    stopwatch.stop();

    MaskData? mask;
    List<FaceData>? faces;

    for (final r in results) {
      if (r is MaskData) mask = r;
      if (r is List<FaceData>) faces = r;
    }

    return PipelineResult(
      backgroundMask: mask,
      faces: faces,
      inferenceTime: stopwatch.elapsed,
    );
  }

  void dispose() {
    _bgRemover?.dispose();
    _facePipeline?.dispose();
  }
}
