import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud.dart';
import 'quiz.dart';

/// Everything a phone has to tell the server in a day, kept on the phone and
/// sent as ONE small document (`searches/d-<day>-<device>`), when the app goes
/// to the background and at most every 10 minutes while something is new.
/// Four times a day the server adds all phones up into files on the site.
///
/// Holds: answers viewed (v), quiz answers (a), «هل أفادك» votes (hv), app
/// shares (sh), the hours the app was open (hr), and minutes on screen (min).
class DayLog with WidgetsBindingObserver {
  DayLog._();
  static final instance = DayLog._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  SharedPreferences? _p;
  String _dev = '';
  String _day = '';
  Map<String, dynamic> _pending = {};
  int _minutes = 0, _sentMin = 0;
  Set<String> _hours = {};
  bool _dirty = false;
  bool _sending = false;
  Timer? _tick, _send;

  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String get today => dayKey(DateTime.now().toUtc());

  /// The device's own number (random, made by the app; not the phone number).
  String get device => _dev;

  Future<void> start() async {
    _p = await SharedPreferences.getInstance();
    final p = _p!;
    _dev = p.getString('dayLogDev') ?? '';
    if (_dev.isEmpty) {
      _dev = '${10000 + DateTime.now().microsecondsSinceEpoch % 90000}';
      await p.setString('dayLogDev', _dev);
    }
    _day = p.getString('dayLogDay') ?? today;
    _minutes = p.getInt('dayLogMin') ?? 0;
    _sentMin = p.getInt('dayLogSentMin') ?? 0;
    _hours = (p.getStringList('dayLogHours') ?? const []).toSet();
    try {
      _pending = Map<String, dynamic>.from(jsonDecode(p.getString('dayLogPending') ?? '{}') as Map);
    } catch (_) {
      _pending = {};
    }
    _dirty = _pending.isNotEmpty;
    WidgetsBinding.instance.addObserver(this);
    _hour();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      final st = WidgetsBinding.instance.lifecycleState;
      if (st != null && st != AppLifecycleState.resumed) return;
      _roll();
      _minutes++;
      p.setInt('dayLogMin', _minutes);
      _hour();
    });
    _send = Timer.periodic(const Duration(minutes: 10), (_) => flush());
    unawaited(flush());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      flush(closing: true);
    }
    if (state == AppLifecycleState.resumed) _hour();
  }

  void dispose() {
    _tick?.cancel();
    _send?.cancel();
  }

  /// A new day: whatever is still waiting belongs to the old day's document.
  void _roll() {
    final t = today;
    if (t == _day) return;
    final old = _day, left = _pending, mins = _minutes;
    _day = t;
    _pending = {};
    _minutes = 0;
    _sentMin = 0;
    _hours = {};
    _p?.setString('dayLogDay', t);
    _p?.setInt('dayLogMin', 0);
    _p?.setInt('dayLogSentMin', 0);
    _p?.setStringList('dayLogHours', const []);
    _save();
    if (left.isNotEmpty || mins > 0) unawaited(_write(old, left, mins));
  }

  void _put(String group, String key, Object value) {
    _roll();
    final m = Map<String, dynamic>.from((_pending[group] as Map?) ?? {});
    m[key] = value;
    _pending[group] = m;
    _dirty = true;
    _save();
  }

  void _save() => _p?.setString('dayLogPending', jsonEncode(_pending));

  /// Each hour the app is open is told once.
  void _hour() {
    _roll();
    final h = '${DateTime.now().toUtc().hour}';
    if (!_hours.add(h)) return;
    _p?.setStringList('dayLogHours', _hours.toList());
    _put('hr', h, 1);
  }

  void view(String answerId) => _put('v', answerId, 1);
  void answer(String qid, int choice, bool ok) => _put('a', qid, [choice, ok]);
  void vote(String answerId, bool helpful) => _put('hv', answerId, helpful);
  void share() {
    _roll();
    _pending['sh'] = ((_pending['sh'] as num?)?.toInt() ?? 0) + 1;
    _dirty = true;
    _save();
  }

  /// Sends what is waiting, in one write. Signed-in readers also send their
  /// quiz record (one more write), only when it changed.
  /// Minutes on screen go only with something else, or when the app closes.
  Future<void> flush({bool closing = false}) async {
    _roll();
    if (_sending || !Cloud.instance.ready) return;
    if (!_dirty && !(closing && _minutes != _sentMin)) return;
    _sending = true;
    final sent = _pending;
    _pending = {};
    _dirty = false;
    _save();
    final ok = await _write(_day, sent, _minutes);
    if (ok) {
      _sentMin = _minutes;
      _p?.setInt('dayLogSentMin', _minutes);
    } else {
      // Keep it for the next try.
      for (final e in sent.entries) {
        if (e.value is Map) {
          _pending[e.key] = {...(e.value as Map), ...((_pending[e.key] as Map?) ?? {})};
        } else if (e.key == 'sh') {
          _pending['sh'] = ((_pending['sh'] as num?)?.toInt() ?? 0) + ((e.value as num?)?.toInt() ?? 0);
        }
      }
      _dirty = true;
      _save();
    }
    await Quiz.instance.flushProfile();
    _sending = false;
  }

  Future<bool> _write(String day, Map<String, dynamic> data, int minutes) async {
    try {
      final u = Cloud.instance.user;
      final q = Quiz.instance;
      await _db.doc('searches/d-$day-$_dev').set({
        ...data,
        'day': day,
        'min': minutes,
        'u': u == null ? 'g$_dev' : '${askerNo(u.uid)}',
        if (u != null) 'name': q.nick.trim().isEmpty ? 'طالب علم' : q.nick.trim(),
        if (kIsWeb) 'web': true,
      }, SetOptions(merge: true));
      return true;
    } catch (_) {
      return false;
    }
  }
}
