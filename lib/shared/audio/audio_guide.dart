import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/foundation.dart';

class AudioGuide {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  String _lastSpoken = '';
  bool _speaking = false;

  Future<void> init() async {
    if (_initialized) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    _tts.setCompletionHandler(() {
      _speaking = false;
    });

    _initialized = true;
  }

  Future<void> speak(String text) async {
    if (!_initialized) await init();
    if (text == _lastSpoken && _speaking) return;
    if (text.isEmpty) return;

    _lastSpoken = text;
    _speaking = true;
    try {
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS error: $e');
      _speaking = false;
    }
  }

  Future<void> stop() async {
    _speaking = false;
    await _tts.stop();
  }

  bool get isSpeaking => _speaking;

  void dispose() {
    _tts.stop();
    _tts.setCompletionHandler(() {});
  }
}
