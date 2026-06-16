import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

class _ResizeRequest {
  final Uint8List bytes;
  final int srcW;
  final int srcH;
  final int dstW;
  final int dstH;
  final int numChannels;
  final SendPort replyPort;
  _ResizeRequest({
    required this.bytes,
    required this.srcW,
    required this.srcH,
    required this.dstW,
    required this.dstH,
    required this.numChannels,
    required this.replyPort,
  });
}

class _ResizeResult {
  final Uint8List? bytes;
  final String? error;
  _ResizeResult({this.bytes, this.error});
}

void _entry(Map<String, dynamic> params) {
  final rx = ReceivePort();
  (params['sendPort'] as SendPort).send(rx.sendPort);
  rx.listen((m) async {
    if (m is _ResizeRequest) {
      _ResizeResult r;
      try {
        final src = img.Image.fromBytes(
          width: m.srcW, height: m.srcH,
          bytes: m.bytes.buffer, numChannels: m.numChannels,
        );
        final dst = img.copyResize(
          src, width: m.dstW, height: m.dstH,
          interpolation: img.Interpolation.linear,
        );
        r = _ResizeResult(bytes: dst.getBytes());
      } catch (e) {
        r = _ResizeResult(error: e.toString());
      }
      m.replyPort.send(r);
    }
  });
}

/// Runs [img.copyResize] in a background isolate.
///
/// Accepts raw pixel [bytes] (RGBA by default) and returns resized RGBA bytes.
/// Use this from any feature to keep the main thread free during interpolation.
Future<Uint8List> resizeImageInIsolate({
  required Uint8List bytes,
  required int srcW,
  required int srcH,
  required int dstW,
  required int dstH,
  int numChannels = 4,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final setupPort = ReceivePort();
  final isolate = await Isolate.spawn(_entry, {
    'sendPort': setupPort.sendPort,
  }, errorsAreFatal: false);

  final sendPort = await setupPort.first as SendPort;
  final replyPort = ReceivePort();

  // Normalize to a compact, owned list so bytes.buffer starts at offset 0
  sendPort.send(_ResizeRequest(
    bytes: Uint8List.sublistView(bytes),
    srcW: srcW, srcH: srcH,
    dstW: dstW, dstH: dstH,
    numChannels: numChannels,
    replyPort: replyPort.sendPort,
  ));

  final result = await Future.any([
    replyPort.first,
    Future.delayed(timeout, () => _ResizeResult(error: 'Timeout after $timeout')),
  ]);

  replyPort.close();
  setupPort.close();
  isolate.kill();

  if (result is _ResizeResult && result.bytes != null) return result.bytes!;
  throw StateError('Isolate resize failed: ${result is _ResizeResult ? result.error : "unknown"}');
}
