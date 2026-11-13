import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// «اقرأ لي»: reads a text aloud with the phone's Arabic voice.
class Reader extends ChangeNotifier {
  Reader._();
  static final Reader instance = Reader._();

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  int _run = 0;

  /// Id of what is being read now ('' = silent).
  String playing = '';

  Future<void> toggle(String id, String text) async {
    if (playing == id) {
      await stop();
      return;
    }
    await stop();
    final run = ++_run;
    playing = id;
    notifyListeners();
    try {
      if (!_ready) {
        await _tts.setLanguage('ar');
        await _tts.setSpeechRate(0.45);
        await _tts.awaitSpeakCompletion(true);
        _ready = true;
      }
      // The phone's voice takes limited text at once: read by paragraphs.
      final parts = <String>[];
      for (final p in text.split('\n')) {
        var t = p.trim();
        while (t.length > 900) {
          var cut = t.lastIndexOf(' ', 900);
          if (cut < 300) cut = 900;
          parts.add(t.substring(0, cut));
          t = t.substring(cut).trim();
        }
        if (t.isNotEmpty) parts.add(t);
      }
      for (final p in parts) {
        if (run != _run) return;
        await _tts.speak(p);
      }
    } catch (_) {}
    if (run == _run) {
      playing = '';
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _run++;
    try {
      await _tts.stop();
    } catch (_) {}
    if (playing.isNotEmpty) {
      playing = '';
      notifyListeners();
    }
  }
}

/// Voice search: listens once and returns what was said in Arabic.
class Listener1 {
  static final SpeechToText _stt = SpeechToText();
  static bool _ok = false;

  /// Starts listening; [onText] gets the words as they are recognised and
  /// [onDone] is called when listening ends. Returns false when the phone
  /// has no speech service or the microphone was refused.
  static Future<bool> start({required void Function(String) onText, required VoidCallback onDone}) async {
    try {
      _ok = _ok ||
          await _stt.initialize(
            onStatus: (s) {
              if (s == 'done' || s == 'notListening') onDone();
            },
            onError: (_) => onDone(),
          );
      if (!_ok) return false;
      await _stt.listen(
        localeId: 'ar-SA',
        onResult: (r) => onText(r.recognizedWords),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }
}
