import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../theme.dart';

/// A recording made in the app: its bytes and its file type (ogg or m4a).
class Recorded {
  final Uint8List bytes;
  final String ext;
  final int seconds;
  const Recorded(this.bytes, this.ext, this.seconds);
}

/// Hold-free voice recording like WhatsApp: tap to start, tap to stop.
/// Android only (the website cannot record here).
class VoiceRecorder extends StatefulWidget {
  final ValueChanged<Recorded?> onDone;
  const VoiceRecorder({super.key, required this.onDone});

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  State<VoiceRecorder> createState() => _VoiceRecorderState();
}

class _VoiceRecorderState extends State<VoiceRecorder> {
  final _rec = AudioRecorder();
  bool _on = false;
  int _secs = 0;
  Timer? _t;
  String _ext = 'ogg';
  Recorded? _last;

  @override
  void dispose() {
    _t?.cancel();
    _rec.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _rec.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اسمح للتطبيق باستعمال الميكروفون')));
      }
      return;
    }
    final opus = await _rec.isEncoderSupported(AudioEncoder.opus);
    _ext = opus ? 'ogg' : 'm4a';
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.$_ext';
    await _rec.start(RecordConfig(encoder: opus ? AudioEncoder.opus : AudioEncoder.aacLc, bitRate: 48000, sampleRate: 48000),
        path: path);
    setState(() {
      _on = true;
      _secs = 0;
      _last = null;
    });
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _secs++);
      if (_secs >= 600) _stop(); // ten minutes at most
    });
  }

  Future<void> _stop() async {
    _t?.cancel();
    final path = await _rec.stop();
    setState(() => _on = false);
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    _last = Recorded(bytes, _ext, _secs);
    widget.onDone(_last);
    if (mounted) setState(() {});
  }

  String get _time => '${_secs ~/ 60}:${(_secs % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (!VoiceRecorder.supported) {
      return const Text('التسجيل الصوتي من تطبيق الأندرويد.', style: TextStyle(color: Colors.grey));
    }
    return Row(children: [
      FloatingActionButton.small(
        heroTag: null,
        backgroundColor: _on ? Colors.red : kGold,
        onPressed: _on ? _stop : _start,
        child: Icon(_on ? Icons.stop : Icons.mic, color: Colors.white),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
            _on
                ? 'يسجّل… $_time (اضغط للإيقاف)'
                : _last != null
                    ? 'تسجيل جاهز (${_last!.seconds ~/ 60}:${(_last!.seconds % 60).toString().padLeft(2, '0')}) ✓'
                    : 'اضغط الميكروفون لتسجّل بصوتك',
            style: TextStyle(color: _on ? Colors.red : null, fontWeight: _on ? FontWeight.bold : null)),
      ),
      if (_last != null && !_on)
        IconButton(
          tooltip: 'حذف التسجيل',
          icon: const Icon(Icons.delete_outline),
          onPressed: () {
            setState(() => _last = null);
            widget.onDone(null);
          },
        ),
    ]);
  }
}
