import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'progress.dart';

/// One thing to listen to: a recording of the channel, or a lesson.
class AudioItem {
  final String title, url, by, telegram;
  const AudioItem(this.title, this.url, {this.by = '', this.telegram = ''});
  String get key => '${url.hashCode}';
}

/// The one player of the whole app. It keeps playing when the reader goes to
/// another page, leaves the app or locks the phone (controls on the lock
/// screen and in the notifications), keeps each recording's place, the
/// chosen speed, and plays the next one by itself.
class AudioCenter extends ChangeNotifier {
  AudioCenter._();
  static final AudioCenter instance = AudioCenter._();

  /// Called once before the app starts (background playback on Android/iOS).
  static Future<void> init() async {
    try {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.ibnalshabira.audio',
        androidNotificationChannelName: 'تسجيلات الشيخ',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      );
    } catch (_) {}
  }

  AudioPlayer? _p;
  AudioPlayer get player => _p ??= _make();

  AudioPlayer _make() {
    final p = AudioPlayer();
    p.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        _savePos(zero: true);
        _next();
      }
      notifyListeners();
    });
    return p;
  }

  List<AudioItem> queue = [];
  int index = -1;
  String? error;
  bool loading = false;
  double speed = 1.0;
  Timer? _saver;

  AudioItem? get current => index >= 0 && index < queue.length ? queue[index] : null;
  bool get playing => _p?.playing ?? false;
  bool get hasNext => index + 1 < queue.length;

  /// Asks Telegram for the playable link of a voice note (set by the recordings page).
  static Future<String?> Function(int id)? voiceLink;

  /// Starts [items] at [start]; the next ones follow by themselves.
  Future<void> playQueue(List<AudioItem> items, int start) async {
    queue = List.of(items);
    index = start;
    await _load();
  }

  Future<void> play(AudioItem item) => playQueue([item], 0);

  Future<void> _load() async {
    final it = current;
    if (it == null) return;
    error = null;
    loading = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      speed = prefs.getDouble('audio_speed') ?? 1.0;
      final local = await _localFile(it);
      final tag = MediaItem(
          id: it.url, title: it.title, artist: it.by.isEmpty ? 'الشيخ قايد بن غانم الشابرة' : it.by, album: 'ابن الشابرة');
      if (local != null) {
        await player.setAudioSource(AudioSource.file(local, tag: tag));
      } else {
        var url = it.url;
        if (url.startsWith('tg:')) {
          final link = await voiceLink?.call(int.parse(url.substring(3)));
          if (link == null) throw Exception('no link');
          url = link;
        }
        await player.setAudioSource(AudioSource.uri(Uri.parse(url), tag: tag));
      }
      final pos = prefs.getInt('audio_pos_${it.key}') ?? 0;
      if (pos > 3) await player.seek(Duration(seconds: pos - 2));
      await player.setSpeed(speed);
      loading = false;
      notifyListeners();
      unawaited(player.play());
      Progress.listened();
      _saver?.cancel();
      _saver = Timer.periodic(const Duration(seconds: 10), (_) {
        _savePos();
        if (playing) Progress.addListen(10);
      });
    } catch (_) {
      loading = false;
      error = 'تعذّر تشغيل التسجيل، تأكد من الاتصال بالإنترنت';
      notifyListeners();
    }
  }

  Future<void> toggle() async {
    if (current == null) return;
    if (playing) {
      await player.pause();
      await _savePos();
    } else {
      unawaited(player.play());
    }
    notifyListeners();
  }

  // ---- Sleep timer (only when the listener chooses it)
  Timer? _sleep;
  DateTime? sleepAt;

  /// Stops playing after [minutes]; 0 cancels the timer.
  void setSleep(int minutes) {
    _sleep?.cancel();
    sleepAt = null;
    if (minutes > 0) {
      sleepAt = DateTime.now().add(Duration(minutes: minutes));
      _sleep = Timer(Duration(minutes: minutes), () async {
        sleepAt = null;
        if (playing) {
          await player.pause();
          await _savePos();
        }
        notifyListeners();
      });
    }
    notifyListeners();
  }

  /// Plays [item] from second [sec] (an audio bookmark).
  Future<void> playAt(AudioItem item, int sec) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('audio_pos_${item.key}', sec + 2);
    if (current?.url == item.url) {
      await player.seek(Duration(seconds: sec));
      if (!playing) unawaited(player.play());
      notifyListeners();
      return;
    }
    await play(item);
  }

  Future<void> seekBy(int seconds) async {
    final p = player.position + Duration(seconds: seconds);
    await player.seek(p.isNegative ? Duration.zero : p);
  }

  Future<void> nextSpeed() async {
    const speeds = [1.0, 1.25, 1.5, 2.0, 0.75];
    speed = speeds[(speeds.indexOf(speed) + 1) % speeds.length];
    await player.setSpeed(speed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('audio_speed', speed);
    notifyListeners();
  }

  Future<void> _next() async {
    if (!hasNext) {
      notifyListeners();
      return;
    }
    index++;
    await _load();
  }

  Future<void> next() => _next();

  Future<void> previous() async {
    if (index <= 0) return;
    await _savePos();
    index--;
    await _load();
  }

  /// Stops and hides the bar.
  Future<void> close() async {
    await _savePos();
    _saver?.cancel();
    try {
      await _p?.stop();
    } catch (_) {}
    queue = [];
    index = -1;
    notifyListeners();
  }

  Future<void> _savePos({bool zero = false}) async {
    final it = current;
    if (it == null || _p == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('audio_pos_${it.key}', zero ? 0 : _p!.position.inSeconds);
    } catch (_) {}
  }

  // ------------------------------------------------------------ offline
  static Future<String> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    return '${base.path}/recordings';
  }

  Future<String?> _localFile(AudioItem it) async {
    if (kIsWeb) return null;
    try {
      final f = File('${await _dir()}/${it.key}.audio');
      return await f.exists() && await f.length() > 1000 ? f.path : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> isDownloaded(AudioItem it) async => await _localFile(it) != null;

  final Set<String> downloading = {};

  /// Keeps a recording on the phone, to listen without internet.
  Future<String?> download(AudioItem it) async {
    if (kIsWeb) return 'التنزيل في التطبيق فقط';
    if (downloading.contains(it.key)) return null;
    downloading.add(it.key);
    notifyListeners();
    try {
      var url = it.url;
      if (url.startsWith('tg:')) {
        url = await voiceLink?.call(int.parse(url.substring(3))) ?? '';
        if (url.isEmpty) throw Exception('no link');
      }
      final res = await http.get(Uri.parse(url)).timeout(const Duration(minutes: 5));
      if (res.statusCode != 200 || res.bodyBytes.length < 1000) throw Exception('bad');
      final dir = Directory(await _dir());
      if (!await dir.exists()) await dir.create(recursive: true);
      await File('${dir.path}/${it.key}.audio').writeAsBytes(res.bodyBytes);
      return null;
    } catch (_) {
      return 'تعذّر التنزيل، تأكد من الاتصال';
    } finally {
      downloading.remove(it.key);
      notifyListeners();
    }
  }

  Future<void> removeDownload(AudioItem it) async {
    try {
      final f = File('${await _dir()}/${it.key}.audio');
      if (await f.exists()) await f.delete();
    } catch (_) {}
    notifyListeners();
  }
}
