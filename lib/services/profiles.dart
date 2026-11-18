import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud.dart';
import 'notifications.dart';
import 'quiz.dart';
import 'site_files.dart';

/// Readers' public pages, following, and quotes.
///
/// The pages come from one file the server makes four times a day
/// (profiles.json), so opening a page, searching a number or seeing the
/// people one follows costs no Firestore read. What the reader changes
/// (whom he follows, his quotes) goes out with his own page, which is
/// sent at most once in six hours.
class Profiles extends ChangeNotifier {
  Profiles._();
  static final Profiles instance = Profiles._();

  static const searchesPerDay = 3;

  Map<String, Map<String, dynamic>> pages = {};
  DateTime? at;
  Set<String> following = {};
  List<Map<String, dynamic>> quotes = [];
  int newFollowers = 0;
  bool _loaded = false;

  String? get myNo {
    final u = Cloud.instance.user;
    return u == null ? null : '${askerNo(u.uid)}';
  }

  Map<String, dynamic>? page(String no) => pages[no];
  Map<String, dynamic>? get mine => myNo == null ? null : pages[myNo!];

  /// Whom the reader follows and his quotes, from the phone.
  Future<void> loadLocal() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();
    if (!_loaded) {
      following = (p.getStringList('following') ?? const []).toSet();
      try {
        quotes = [
          for (final q in (jsonDecode(p.getString('myQuotes') ?? '[]') as List)) Map<String, dynamic>.from(q as Map)
        ];
      } catch (_) {}
      _loaded = true;
    }
  }

  Future<void> load({bool fresh = false}) async {
    await loadLocal();
    final p = await SharedPreferences.getInstance();
    final m = await SiteFiles.get('profiles.json', fresh: fresh);
    if (m != null) {
      pages = {
        for (final e in ((m['p'] as Map?) ?? const {}).entries) '${e.key}': Map<String, dynamic>.from(e.value as Map)
      };
      final t = (m['at'] as num?)?.toInt();
      at = t == null ? null : DateTime.fromMillisecondsSinceEpoch(t);
      await _checkFollowers(p);
    }
    notifyListeners();
  }

  /// «حصلت على متابع جديد»: when the file shows more followers than before.
  Future<void> _checkFollowers(SharedPreferences p) async {
    final my = mine;
    if (my == null) return;
    final now = (my['fr'] as num?)?.toInt() ?? 0;
    final before = p.getInt('followersSeen');
    if (before == null) {
      await p.setInt('followersSeen', now);
      return;
    }
    if (now > before) {
      newFollowers = now - before;
      await p.setInt('followersSeen', now);
      await OnceNotifications.showNow(
          newFollowers == 1 ? 'حصلت على متابع جديد 🎉' : 'حصلت على $newFollowers متابعين جدد 🎉',
          'صار عدد متابعيك $now. افتح «لوحتي» لترى ملفك.');
    } else if (now < before) {
      await p.setInt('followersSeen', now);
    }
  }

  void seenNewFollowers() {
    newFollowers = 0;
    notifyListeners();
  }

  // ------------------------------------------------------------- following
  bool isFollowing(String no) => following.contains(no);

  Future<void> toggleFollow(String no) async {
    await loadLocal();
    if (no == myNo) return;
    following.contains(no) ? following.remove(no) : following.add(no);
    final p = await SharedPreferences.getInstance();
    await p.setStringList('following', following.toList());
    Quiz.instance.profileChanged();
    notifyListeners();
  }

  // ---------------------------------------------------------------- quotes
  Future<String?> addQuote(String text, String source) async {
    await loadLocal();
    final t = text.trim();
    if (t.isEmpty) return 'اكتب الاقتباس أولاً';
    if (quotes.length >= 30) return 'بلغت 30 اقتباساً، احذف واحداً لتضيف غيره';
    quotes.insert(0, {'t': t.length > 600 ? '${t.substring(0, 600)}…' : t, 's': source, 'at': DateTime.now().millisecondsSinceEpoch});
    await _saveQuotes();
    return null;
  }

  Future<void> removeQuote(int i) async {
    if (i < 0 || i >= quotes.length) return;
    quotes.removeAt(i);
    await _saveQuotes();
  }

  Future<void> _saveQuotes() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('myQuotes', jsonEncode(quotes));
    Quiz.instance.profileChanged();
    notifyListeners();
  }

  // ---------------------------------------------------------------- search
  /// Searches left today (the staff have no limit).
  Future<int> searchesLeft() async {
    if (Cloud.instance.isAdmin) return 999;
    final p = await SharedPreferences.getInstance();
    final d = DateTime.now();
    final today = '${d.year}-${d.month}-${d.day}';
    if (p.getString('searchDay') != today) return searchesPerDay;
    return (searchesPerDay - (p.getInt('searchCount') ?? 0)).clamp(0, searchesPerDay);
  }

  Future<void> useSearch() async {
    if (Cloud.instance.isAdmin) return;
    final p = await SharedPreferences.getInstance();
    final d = DateTime.now();
    final today = '${d.year}-${d.month}-${d.day}';
    if (p.getString('searchDay') != today) {
      await p.setString('searchDay', today);
      await p.setInt('searchCount', 0);
    }
    await p.setInt('searchCount', (p.getInt('searchCount') ?? 0) + 1);
  }
}
