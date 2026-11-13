import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../data/repository.dart';
import 'notifications.dart';

/// Online features (app and website): Google sign-in, admins, views,
/// «هل أفادك الجواب؟», error reports, published answers and title edits.
/// The website works without it.
class Cloud extends ChangeNotifier {
  Cloud._();
  static final Cloud instance = Cloud._();

  /// The developer is always an admin.
  static const developerEmail = 'www774475437@gmail.com';

  bool ready = false;
  User? user;
  /// Any staff member (editor or full admin).
  bool isAdmin = false;

  /// Full admin: can also manage admins, chapters, announcement, settings.
  bool isFullAdmin = false;

  bool get isDeveloper => isFullAdmin && email == developerEmail;

  int newQuestions = 0; // for staff
  int unseenReplies = 0; // for the asker
  int _answeredCount = 0;
  StreamSubscription? _newQSub;
  StreamSubscription? _myQSub;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<void> init() async {
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'AIzaSyCOpkQxy5gP2-PuFAphg_tlJBv2gI8RkVI',
          appId: '1:402664894391:android:b09cad286f2dd5a1604232',
          messagingSenderId: '402664894391',
          projectId: 'ibn-alshabira',
          authDomain: 'ibn-alshabira.firebaseapp.com',
          storageBucket: 'ibn-alshabira.firebasestorage.app',
        ),
      );
      ready = true;
      FirebaseAuth.instance.authStateChanges().listen((u) async {
        user = u;
        await _checkAdmin();
        _watchQuestions();
        if (u != null) await _syncUserData();
        notifyListeners();
      });
      await loadRemoteAnswers();
      loadConfig();
      loadSeries();
    } catch (e) {
      debugPrint('Cloud init failed: $e');
      ready = false;
    }
    notifyListeners();
  }

  String? get email => user?.email?.toLowerCase();

  Future<void> _checkAdmin() async {
    isAdmin = false;
    isFullAdmin = false;
    final e = email;
    // Staff rights need a verified email (Google accounts always are).
    if (e == null || user?.emailVerified != true) return;
    if (e == developerEmail) {
      isAdmin = true;
      isFullAdmin = true;
      return;
    }
    try {
      final d = await _db.doc('admins/$e').get();
      if (d.exists) {
        isAdmin = true;
        isFullAdmin = (d.data()?['role'] ?? 'admin') == 'admin';
      }
    } catch (_) {}
  }

  /// Staff: count of new questions. Asker: count of replies not seen yet.
  void _watchQuestions() {
    _newQSub?.cancel();
    _myQSub?.cancel();
    newQuestions = 0;
    unseenReplies = 0;
    final u = user;
    if (!ready || u == null) return;
    if (isAdmin) {
      var first = true;
      _newQSub = _db.collection('questions').where('status', isEqualTo: 'new').snapshots().listen((q) {
        if (!first && q.size > newQuestions) {
          AppAlerts.show('سؤال جديد', 'وصل سؤال جديد إلى «اسأل الشيخ»');
        }
        first = false;
        newQuestions = q.size;
        notifyListeners();
      }, onError: (_) {});
    }
    _myQSub = _db.collection('questions').where('uid', isEqualTo: u.uid).snapshots().listen((q) async {
      _answeredCount = q.docs.where((d) => '${d.data()['reply'] ?? ''}'.isNotEmpty).length;
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getInt('seenReplies_${u.uid}') ?? 0;
      final before = unseenReplies;
      unseenReplies = _answeredCount > seen ? _answeredCount - seen : 0;
      if (unseenReplies > before) {
        AppAlerts.show('وصل جواب سؤالك', 'افتح «اسأل الشيخ» لقراءة الجواب');
      }
      notifyListeners();
    }, onError: (_) {});
  }

  Future<void> markRepliesSeen() async {
    final u = user;
    if (u == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('seenReplies_${u.uid}', _answeredCount);
    if (unseenReplies != 0) {
      unseenReplies = 0;
      notifyListeners();
    }
  }

  Future<void> _log(String action, [String target = '']) async {
    try {
      await _db.collection('log').add({
        'by': email ?? '',
        'action': action,
        'target': target.length > 120 ? target.substring(0, 120) : target,
        'at': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> logStream() =>
      _db.collection('log').orderBy('at', descending: true).limit(200).snapshots();

  // ---------------------------------------------------------------- Auth
  static const _webClientId =
      '402664894391-nlspbi9qo7lc65qkcngbufdh15n255jb.apps.googleusercontent.com';
  bool _googleReady = false;
  bool _signingIn = false;

  Future<void> _ensureGoogle() async {
    if (_googleReady) return;
    await GoogleSignIn.instance.initialize(serverClientId: _webClientId);
    _googleReady = true;
  }

  /// Native Google account picker (no browser).
  Future<String?> signIn() async {
    if (!ready) return 'الخدمة غير متاحة الآن، تأكد من الاتصال بالإنترنت';
    if (_signingIn) return null;
    _signingIn = true;
    try {
      if (kIsWeb) {
        await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
        return null;
      }
      await _ensureGoogle();
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) return 'تعذّر تسجيل الدخول (no-token)';
      await FirebaseAuth.instance
          .signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
      return null;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return 'أُلغي تسجيل الدخول';
      return 'تعذّر تسجيل الدخول (${e.code.name})';
    } on FirebaseAuthException catch (e) {
      return 'تعذّر تسجيل الدخول (${e.code})';
    } catch (e) {
      return 'تعذّر تسجيل الدخول';
    } finally {
      _signingIn = false;
    }
  }

  // ------------------------------------------ Ordinary email + password
  String _authError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'هذا البريد مسجّل من قبل، اضغط «دخول»';
      case 'invalid-email':
        return 'البريد غير صحيح';
      case 'weak-password':
        return 'كلمة السر ضعيفة، اجعلها 6 أحرف أو أكثر';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'البريد أو كلمة السر غير صحيحة';
      case 'operation-not-allowed':
        return 'التسجيل بالبريد غير مفعّل بعد';
      case 'network-request-failed':
        return 'تأكد من الاتصال بالإنترنت';
      default:
        return 'تعذّرت العملية (${e.code})';
    }
  }

  Future<String?> registerEmail(String name, String email, String password) async {
    if (!ready) return 'الخدمة غير متاحة الآن، تأكد من الاتصال بالإنترنت';
    try {
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email.trim(), password: password);
      if (name.trim().isNotEmpty) {
        await cred.user?.updateDisplayName(name.trim());
        await cred.user?.reload();
        user = FirebaseAuth.instance.currentUser;
        notifyListeners();
      }
      return null;
    } on FirebaseAuthException catch (e) {
      return _authError(e);
    } catch (_) {
      return 'تعذّر إنشاء الحساب';
    }
  }

  Future<String?> signInEmail(String email, String password) async {
    if (!ready) return 'الخدمة غير متاحة الآن، تأكد من الاتصال بالإنترنت';
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email.trim(), password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      return _authError(e);
    } catch (_) {
      return 'تعذّر تسجيل الدخول';
    }
  }

  Future<String?> resetPassword(String email) async {
    if (!ready) return 'الخدمة غير متاحة الآن';
    if (!email.contains('@')) return 'اكتب بريدك أولاً';
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      return _authError(e);
    } catch (_) {
      return 'تعذّر الإرسال';
    }
  }

  Future<void> signOut() async {
    if (!ready) return;
    if (!kIsWeb) {
      try {
        await _ensureGoogle();
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    await FirebaseAuth.instance.signOut();
  }

  // ---------------------------------------------- Saved items sync (per user)
  Future<void> _syncUserData() async {
    final u = user;
    if (u == null) return;
    final repo = Repository.instance;
    try {
      final doc = _db.doc('users/${u.uid}');
      final snap = await doc.get();
      final data = snap.data() ?? {};
      final favs = {...repo.favorites, ...((data['favorites'] ?? []) as List).map((e) => '$e')};
      final later = {...repo.readLater, ...((data['readLater'] ?? []) as List).map((e) => '$e')};
      repo.replaceSavedLists(favs, later);
      await doc.set({'favorites': favs.toList(), 'readLater': later.toList()});
    } catch (e) {
      debugPrint('sync failed: $e');
    }
  }

  /// Called by the repository when saved lists change.
  Future<void> pushUserData() async {
    final u = user;
    if (!ready || u == null) return;
    final repo = Repository.instance;
    try {
      await _db.doc('users/${u.uid}').set({
        'favorites': repo.favorites.toList(),
        'readLater': repo.readLater.toList(),
      });
    } catch (_) {}
  }

  // ---------------------------------------------------------------- Views
  final Set<String> _countedThisSession = {};

  Future<void> addView(String id) async {
    if (!ready || !_countedThisSession.add(id)) return;
    try {
      // One view per answer per device, so the numbers are real readers.
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getStringList('viewedAnswers') ?? <String>[];
      if (seen.contains(id)) return;
      await prefs.setStringList('viewedAnswers', [...seen, id]);
      await _db.doc('views/$id').set({'count': FieldValue.increment(1)}, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<Map<String, int>> stats(String id) async {
    if (!ready) return {};
    try {
      final d = (await _db.doc('views/$id').get()).data() ?? {};
      return {
        'count': (d['count'] ?? 0) as int,
        'helpful': (d['helpful'] ?? 0) as int,
        'notHelpful': (d['notHelpful'] ?? 0) as int,
      };
    } catch (_) {
      return {};
    }
  }

  Future<bool> vote(String id, bool helpful) async {
    if (!ready) return false;
    try {
      await _db.doc('views/$id').set(
          {helpful ? 'helpful' : 'notHelpful': FieldValue.increment(1)}, SetOptions(merge: true));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Most-read answers: [(id, count)].
  Future<List<(String, int)>> mostRead({int limit = 40}) async {
    if (!ready) return [];
    try {
      final q = await _db.collection('views').orderBy('count', descending: true).limit(limit).get();
      return [
        for (final d in q.docs)
          if (!d.id.startsWith('_')) (d.id, (d.data()['count'] ?? 0) as int),
      ];
    } catch (_) {
      return [];
    }
  }

  // -------------------------------------------------------------- Reports
  Future<bool> report(Fatwa f, String note) async {
    if (!ready) return false;
    try {
      await _db.collection('reports').add({
        'answerId': f.id,
        'title': f.title,
        'note': note,
        'by': email ?? '',
        'at': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> reportsStream() =>
      _db.collection('reports').orderBy('at', descending: true).limit(100).snapshots();

  Future<void> deleteReport(String id) => _db.doc('reports/$id').delete();

  // --------------------------------------------------------------- Admins
  Stream<QuerySnapshot<Map<String, dynamic>>> adminsStream() => _db.collection('admins').snapshots();

  Future<String?> addAdmin(String email, {String role = 'admin'}) async {
    final e = email.trim().toLowerCase();
    if (!e.contains('@') || !e.contains('.')) return 'اكتب بريداً صحيحاً';
    try {
      await _db.doc('admins/$e').set(
          {'addedBy': this.email, 'role': role, 'at': FieldValue.serverTimestamp()});
      _log(role == 'admin' ? 'إضافة مشرف كامل' : 'إضافة محرّر', e);
      return null;
    } catch (_) {
      return 'تعذّرت الإضافة';
    }
  }

  Future<void> removeAdmin(String email) async {
    try {
      await _db.doc('admins/$email').delete();
      _log('حذف مشرف', email);
    } catch (_) {}
  }

  // ----------------------------------- Published answers and title edits
  Future<void> loadRemoteAnswers() async {
    if (!ready) return;
    try {
      final answers = await _db.collection('answers').get();
      final now = DateTime.now();
      // Answers scheduled for later stay hidden until their time comes.
      bool isLater(Map<String, dynamic> m) {
        final t = m['publishAt'];
        return t is Timestamp && t.toDate().isAfter(now);
      }

      final visible = [for (final d in answers.docs) if (!isLater(d.data())) d];
      scheduled = [
        for (final d in answers.docs)
          if (isLater(d.data()))
            (d.id, '${d.data()['title'] ?? ''}', (d.data()['publishAt'] as Timestamp).toDate()),
      ]..sort((a, b) => a.$3.compareTo(b.$3));
      remoteIds = {for (final d in visible) d.id};
      final edits = await _db.collection('titleEdits').get();
      Repository.instance.applyRemote(
        [
          for (final d in visible)
            Fatwa.fromJson({
              for (final e in d.data().entries)
                if (e.key != 'publishAt') e.key: e.value,
              'id': d.id,
            }),
        ],
        {for (final d in edits.docs) d.id: '${d.data()['title'] ?? ''}'},
      );
    } catch (e) {
      debugPrint('remote answers failed: $e');
    }
  }

  Future<String?> publishAnswer({
    required String chapter,
    required String title,
    required String question,
    required String answer,
    List<String> tags = const [],
    DateTime? publishAt,
    String sub = '',
    String audio = '',
  }) async {
    try {
      final now = publishAt ?? DateTime.now();
      await _db.collection('answers').add({
        if (publishAt != null) 'publishAt': Timestamp.fromDate(publishAt),
        'chapter': chapter,
        'type': 'fatwa',
        'title': title.trim(),
        'question': question.trim(),
        'answer': answer.trim(),
        'tags': tags,
        'sub': sub.trim(),
        'audio': audio.trim(),
        'date': '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        'source': '',
        'by': email,
      });
      _log(publishAt == null ? 'نشر جواب' : 'جدولة جواب', title);
      await loadRemoteAnswers();
      return null;
    } catch (_) {
      return 'تعذّر النشر';
    }
  }

  Future<String?> editTitle(String id, String title) async {
    try {
      await _db.doc('titleEdits/$id').set({'title': title.trim(), 'by': email});
      _log('تعديل عنوان', title);
      await loadRemoteAnswers();
      return null;
    } catch (_) {
      return 'تعذّر الحفظ';
    }
  }

  // ---------------------------------------------------------- Admin stats
  Future<Map<String, int>> overview() async {
    if (!ready) return {};
    try {
      final views = await _db.collection('views').get();
      var total = 0, helpful = 0, notHelpful = 0, shares = 0, answersViewed = 0;
      for (final d in views.docs) {
        if (d.id.startsWith('_')) {
          if (d.id == '_appShare') shares = (d.data()['count'] ?? 0) as int;
          continue;
        }
        answersViewed++;
        total += (d.data()['count'] ?? 0) as int;
        helpful += (d.data()['helpful'] ?? 0) as int;
        notHelpful += (d.data()['notHelpful'] ?? 0) as int;
      }
      final reports = await _db.collection('reports').count().get();
      final published = await _db.collection('answers').count().get();
      return {
        'views': total,
        'answersViewed': answersViewed,
        'shares': shares,
        'helpful': helpful,
        'notHelpful': notHelpful,
        'reports': reports.count ?? 0,
        'published': published.count ?? 0,
      };
    } catch (_) {
      return {};
    }
  }

  // ------------------------------------------- Answers published in-app
  Set<String> remoteIds = {};

  bool isRemote(String id) => remoteIds.contains(id);

  Future<String?> updateAnswer(String id,
      {required String chapter,
      required String title,
      required String question,
      required String answer,
      List<String>? tags,
      String? sub,
      String? audio}) async {
    try {
      await _db.doc('answers/$id').update({
        if (tags != null) 'tags': tags,
        if (sub != null) 'sub': sub.trim(),
        if (audio != null) 'audio': audio.trim(),
        'chapter': chapter,
        'title': title.trim(),
        'question': question.trim(),
        'answer': answer.trim(),
      });
      _log('تعديل جواب', title);
      await loadRemoteAnswers();
      return null;
    } catch (_) {
      return 'تعذّر الحفظ';
    }
  }

  Future<String?> deleteAnswer(String id) async {
    try {
      // Keep a copy in the trash for 30 days.
      final doc = await _db.doc('answers/$id').get();
      final data = doc.data();
      if (data != null) {
        await _db.doc('drafts/trash_$id').set({
          ...data,
          'trash': true,
          'origId': id,
          'deletedBy': email,
          'deletedAt': FieldValue.serverTimestamp(),
        });
      }
      await _db.doc('answers/$id').delete();
      _log('حذف جواب', '${data?['title'] ?? id}');
      await loadRemoteAnswers();
      return null;
    } catch (_) {
      return 'تعذّر الحذف';
    }
  }

  /// Answers waiting for their publish time: (id, title, time).
  List<(String, String, DateTime)> scheduled = [];

  /// Publish a scheduled answer right now.
  Future<String?> publishNow(String id) async {
    try {
      await _db.doc('answers/$id').update({'publishAt': FieldValue.delete()});
      _log('نشر جواب مجدول');
      await loadRemoteAnswers();
      notifyListeners();
      return null;
    } catch (_) {
      return 'تعذّر النشر';
    }
  }

  /// Remove a scheduled answer for good (it was never public).
  Future<void> cancelScheduled(String id) async {
    try {
      await _db.doc('answers/$id').delete();
      await loadRemoteAnswers();
      notifyListeners();
    } catch (_) {}
  }

  /// Bring a deleted answer back from the trash.
  Future<String?> restoreAnswer(String trashId) async {
    try {
      final doc = await _db.doc('drafts/$trashId').get();
      final data = doc.data();
      if (data == null) return 'غير موجود';
      final orig = '${data['origId'] ?? ''}';
      final clean = {
        for (final e in data.entries)
          if (!const ['trash', 'origId', 'deletedBy', 'deletedAt'].contains(e.key)) e.key: e.value,
      };
      if (orig.isEmpty) {
        await _db.collection('answers').add(clean);
      } else {
        await _db.doc('answers/$orig').set(clean);
      }
      await _db.doc('drafts/$trashId').delete();
      _log('استرجاع جواب محذوف', '${data['title'] ?? ''}');
      await loadRemoteAnswers();
      return null;
    } catch (_) {
      return 'تعذّر الاسترجاع';
    }
  }

  /// Answers people found most / least helpful: (id, helpful, notHelpful).
  Future<List<(String, int, int)>> votes() async {
    if (!ready) return [];
    try {
      final q = await _db.collection('views').get();
      return [
        for (final d in q.docs)
          if (!d.id.startsWith('_'))
            (d.id, (d.data()['helpful'] ?? 0) as int, (d.data()['notHelpful'] ?? 0) as int),
      ];
    } catch (_) {
      return [];
    }
  }

  // --------------------------------------------------------- Announcement
  String announcement = '';

  bool askOpen = true;
  String aboutText = '';
  List<String> pinned = [];

  /// Loads every settings document at once.
  Future<void> loadConfig() async {
    if (!ready) return;
    try {
      final q = await _db.collection('config').get();
      final c = {for (final d in q.docs) d.id: d.data()};
      final an = c['announcement'];
      announcement = an != null && an['active'] == true ? '${an['text'] ?? ''}' : '';
      askOpen = c['ask']?['open'] != false;
      subs = {
        for (final e in ((c['subs']?['map'] ?? {}) as Map).entries)
          '${e.key}': ((e.value ?? []) as List).map((x) => '$x').toList(),
      };
      Repository.instance.extraSynonyms = {
        for (final e in ((c['synonyms']?['map'] ?? {}) as Map).entries)
          '${e.key}': ((e.value ?? []) as List).map((x) => '$x').toList(),
      };
      lessons = [
        for (final m in ((c['lessons']?['items'] ?? []) as List))
          if (m is Map) Lesson('${m['title'] ?? ''}', '${m['url'] ?? ''}', '${m['group'] ?? ''}'),
      ];
      final mb = c['app']?['minBuild'];
      minBuild = mb is int ? mb : 0;
      aboutText = '${c['about']?['text'] ?? ''}';
      pinned = ((c['pinned']?['ids'] ?? []) as List).map((e) => '$e').toList();
      final ch = c['chapters'];
      Repository.instance.applyChapterConfig(
        [
          for (final e in ((ch?['extra'] ?? []) as List))
            Chapter(id: '${e['id']}', name: '${e['name']}', icon: 'mutafarriq'),
        ],
        {
          for (final e in ((ch?['names'] ?? {}) as Map).entries) '${e.key}': '${e.value}',
        },
      );
      final links = ((c['links']?['items'] ?? []) as List)
          .map((e) => SocialLink.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (links.isNotEmpty) Repository.instance.setSheikhLinks(links);
      notifyListeners();
    } catch (e) {
      debugPrint('config failed: $e');
    }
  }

  /// Audio library of the sheikh's lessons (kept in config/lessons).
  List<Lesson> lessons = [];

  Future<String?> setLessons(List<Lesson> list, String logText) async {
    final err = await setConfig(
        'lessons', {'items': [for (final l in list) {'title': l.title, 'url': l.url, 'group': l.group}]}, logText);
    if (err == null) {
      lessons = list;
      notifyListeners();
    }
    return err;
  }

  /// Search words the staff linked to other words (e.g. الحواجب → النمص).
  Future<String?> addSynonym(String word, String target) async {
    final w = word.trim(), t = target.trim();
    if (w.isEmpty || t.isEmpty) return 'اكتب الكلمتين';
    final map = {
      for (final e in Repository.instance.extraSynonyms.entries) e.key: [...e.value],
    };
    map.putIfAbsent(w, () => []);
    if (!map[w]!.contains(t)) map[w]!.add(t);
    final err = await setConfig('synonyms', {'map': map}, 'ربط كلمة بحث', );
    if (err == null) Repository.instance.extraSynonyms = map;
    return err;
  }

  /// Sub-chapters: chapter id → names.
  Map<String, List<String>> subs = {};

  Future<String?> setSubs(String chapterId, List<String> names) {
    final map = {for (final e in subs.entries) e.key: e.value};
    if (names.isEmpty) {
      map.remove(chapterId);
    } else {
      map[chapterId] = names;
    }
    return setConfig('subs', {'map': map}, 'تعديل الأبواب الفرعية');
  }

  /// Counts one press of «انشر التطبيق».
  Future<void> countAppShare() async {
    if (!ready) return;
    try {
      await _db.doc('views/_appShare').set({'count': FieldValue.increment(1)}, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Builds older than this must update (0 = no forced update).
  int minBuild = 0;

  Future<String?> setConfig(String id, Map<String, dynamic> data, String logText) async {
    try {
      await _db.doc('config/$id').set(data);
      _log(logText);
      await loadConfig();
      return null;
    } catch (_) {
      return 'تعذّر الحفظ';
    }
  }

  Future<String?> togglePin(String answerId) {
    final ids = [...pinned];
    if (!ids.remove(answerId)) ids.insert(0, answerId);
    return setConfig('pinned', {'ids': ids}, 'تعديل الأجوبة المثبّتة');
  }

  Future<String?> setAnnouncement(String text) async {
    try {
      final t = text.trim();
      await _db.doc('config/announcement').set({'text': t, 'active': t.isNotEmpty, 'by': email});
      _log(t.isEmpty ? 'إزالة الإعلان' : 'نشر إعلان', t);
      announcement = t;
      notifyListeners();
      return null;
    } catch (_) {
      return 'تعذّر الحفظ';
    }
  }

  // --------------------------------------------------------------- Series
  List<Series> series = [];

  Future<void> loadSeries() async {
    if (!ready) return;
    try {
      final q = await _db.collection('series').get();
      series = [
        for (final d in q.docs)
          Series(d.id, '${d.data()['title'] ?? ''}',
              ((d.data()['ids'] ?? []) as List).map((e) => '$e').toList(),
              track: d.data()['track'] == true),
      ];
      notifyListeners();
    } catch (_) {}
  }

  List<Series> get plainSeries => series.where((s) => !s.track).toList();
  List<Series> get tracks => series.where((s) => s.track).toList();

  Future<String?> createSeries(String title, String answerId, {bool track = false}) async {
    if (title.trim().isEmpty) return 'اكتب العنوان';
    try {
      await _db.collection('series').add({'title': title.trim(), 'ids': [answerId], 'track': track});
      await loadSeries();
      return null;
    } catch (_) {
      return 'تعذّر الحفظ';
    }
  }

  Future<String?> addToSeries(String seriesId, String answerId) async {
    try {
      await _db.doc('series/$seriesId').update({'ids': FieldValue.arrayUnion([answerId])});
      await loadSeries();
      return null;
    } catch (_) {
      return 'تعذّر الحفظ';
    }
  }

  Future<void> removeFromSeries(String seriesId, String answerId) async {
    try {
      await _db.doc('series/$seriesId').update({'ids': FieldValue.arrayRemove([answerId])});
      await loadSeries();
    } catch (_) {}
  }

  Future<void> deleteSeries(String seriesId) async {
    try {
      await _db.doc('series/$seriesId').delete();
      await loadSeries();
    } catch (_) {}
  }

  // ------------------------------------------------------ Ask the sheikh
  Future<String?> ask(String text, {String chapter = ''}) async {
    final u = user;
    if (!ready || u == null) return 'سجّل الدخول أولاً';
    if (!askOpen) return 'استقبال الأسئلة متوقف مؤقتاً';
    final t = text.trim();
    if (t.length < 5) return 'اكتب سؤالك';
    try {
      await _db.collection('questions').add({
        'uid': u.uid,
        'text': t,
        'chapter': chapter,
        'at': FieldValue.serverTimestamp(),
        'status': 'new',
        'reply': '',
        'published': false,
      });
      return null;
    } catch (_) {
      return 'تعذّر إرسال السؤال';
    }
  }

  // Blocked askers
  Future<void> blockUser(String uid, String sample) async {
    try {
      await _db.doc('blocked/$uid').set({
        'sample': sample.length > 200 ? sample.substring(0, 200) : sample,
        'by': email,
        'at': FieldValue.serverTimestamp(),
      });
      _log('حظر سائل', sample);
    } catch (_) {}
  }

  Future<void> unblockUser(String uid) async {
    try {
      await _db.doc('blocked/$uid').delete();
      _log('رفع الحظر عن سائل');
    } catch (_) {}
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> blockedStream() => _db.collection('blocked').snapshots();

  // Drafts (staff only)
  Stream<QuerySnapshot<Map<String, dynamic>>> draftsStream() => _db.collection('drafts').snapshots();

  Future<String?> saveDraft(String? id,
      {required String chapter, required String title, required String question, required String answer}) async {
    final data = {
      'chapter': chapter,
      'title': title.trim(),
      'question': question.trim(),
      'answer': answer.trim(),
      'by': email,
      'at': FieldValue.serverTimestamp(),
    };
    try {
      if (id == null) {
        await _db.collection('drafts').add(data);
      } else {
        await _db.doc('drafts/$id').set(data);
      }
      return null;
    } catch (_) {
      return 'تعذّر حفظ المسودة';
    }
  }

  Future<void> deleteDraft(String id) async {
    try {
      await _db.doc('drafts/$id').delete();
    } catch (_) {}
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> myQuestions() =>
      _db.collection('questions').where('uid', isEqualTo: user?.uid ?? '-').snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> allQuestions() =>
      _db.collection('questions').orderBy('at', descending: true).limit(200).snapshots();

  /// Reply privately, or reply and publish (without the asker's name).
  Future<String?> replyQuestion(String id,
      {required String questionText,
      required String reply,
      required bool publish,
      String chapter = 'mutafarriq',
      String title = '',
      String refId = ''}) async {
    if (reply.trim().isEmpty) return 'اكتب الجواب';
    try {
      if (publish) {
        final err = await publishAnswer(
          chapter: chapter,
          title: title.trim().isEmpty ? questionText.split('\n').first : title,
          question: questionText,
          answer: reply,
        );
        if (err != null) return err;
      }
      await _db.doc('questions/$id').update({
        'reply': reply.trim(),
        'status': 'answered',
        'published': publish,
        'refId': refId,
        'replyAt': FieldValue.serverTimestamp(),
      });
      _log(publish ? 'رد على سؤال مع النشر' : 'رد خاص على سؤال', questionText);
      return null;
    } catch (_) {
      return 'تعذّر الحفظ';
    }
  }

  Future<void> setQuestionStatus(String id, String status) async {
    try {
      await _db.doc('questions/$id').update({'status': status});
    } catch (_) {}
  }

  Future<void> deleteQuestion(String id) async {
    try {
      await _db.doc('questions/$id').delete();
    } catch (_) {}
  }

  // -------------------------------------------- Searches with no results
  Future<void> logMiss(String term) async {
    if (!ready) return;
    final id = normalizeArabic(term).replaceAll('/', ' ').trim();
    if (id.length < 2 || id.length > 40) return;
    try {
      await _db.doc('searchMisses/$id').set({'count': FieldValue.increment(1)}, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<List<(String, int)>> topMisses() async {
    if (!ready) return [];
    try {
      final q = await _db.collection('searchMisses').orderBy('count', descending: true).limit(60).get();
      return [for (final d in q.docs) (d.id, (d.data()['count'] ?? 0) as int)];
    } catch (_) {
      return [];
    }
  }

  Future<void> clearMiss(String id) async {
    try {
      await _db.doc('searchMisses/$id').delete();
    } catch (_) {}
  }

  // ------------------------------------ «المشايخ الثقات المعتمدون»
  Stream<QuerySnapshot<Map<String, dynamic>>> scholarsStream() =>
      _db.collection('scholars').orderBy('at').snapshots();

  Future<String?> addScholar(String name, String note, String url) async {
    if (name.trim().isEmpty) return 'اكتب اسم الشيخ';
    try {
      await _db.collection('scholars').add({
        'name': name.trim(),
        'note': note.trim(),
        'url': url.trim(),
        'at': FieldValue.serverTimestamp(),
      });
      return null;
    } catch (_) {
      return 'تعذّرت الإضافة';
    }
  }

  Future<void> deleteScholar(String id) async {
    try {
      await _db.doc('scholars/$id').delete();
    } catch (_) {}
  }
}

class Lesson {
  final String title;
  final String url;
  final String group;
  Lesson(this.title, this.url, this.group);
}

class Series {
  final String id;
  final String title;
  final List<String> ids;

  /// A learning track: ordered steps the reader ticks off.
  final bool track;
  Series(this.id, this.title, this.ids, {this.track = false});
}
