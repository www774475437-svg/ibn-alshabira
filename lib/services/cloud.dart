import 'dart:math' as math;
import 'dart:convert';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../data/repository.dart';
import 'ai.dart';
import 'day_log.dart';
import 'notifications.dart';
import 'site_files.dart';
import 'telegram_out.dart';

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

  /// The sheikh's own account: with the developer, the only ones who add or
  /// remove admins and editors.
  bool isOwner = false;
  bool get canManageStaff => isDeveloper || isOwner;

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
      await loadRemoteAnswers(startup: true);
      loadConfig();
      loadSeries(startup: true);
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
    isOwner = false;
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
        isOwner = isFullAdmin && d.data()?['owner'] == true;
        // Record each visit once per session, so the developer sees
        // when this staff member came in, and from where.
        if (_visitLogged != e) {
          _visitLogged = e;
          _log('دخول', kIsWeb ? 'الموقع' : 'التطبيق');
        }
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

  /// The staff log, for screens outside this file.
  Future<void> logAction(String action, [String target = '']) => _log(action, target);

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

  String? _visitLogged;

  /// Everything one staff member did (developer only), newest first.
  Future<List<Map<String, dynamic>>> activityOf(String who) async {
    final q = await _db.collection('log').where('by', isEqualTo: who.toLowerCase()).limit(1000).get();
    final list = [for (final d in q.docs) d.data()];
    int ms(Map<String, dynamic> m) => m['at'] is Timestamp ? (m['at'] as Timestamp).millisecondsSinceEpoch : 0;
    list.sort((a, b) => ms(b).compareTo(ms(a)));
    return list;
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
        try {
          await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
        } on FirebaseAuthException catch (e) {
          // Some phone browsers (e.g. Samsung Internet) block the popup:
          // sign in on the same page instead.
          if (e.code == 'popup-blocked' || e.code == 'operation-not-supported-in-this-environment') {
            await FirebaseAuth.instance.signInWithRedirect(GoogleAuthProvider());
          } else {
            rethrow;
          }
        }
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

  // ---------------------------------------------------- Deleting an account
  /// When the owner asked for his account to be deleted (null: not asked).
  DateTime? pendingDeleteAt;

  /// The owner asks to delete his account: it is kept 30 days, then deleted.
  Future<String?> requestDeletion() async {
    final u = user;
    if (!ready || u == null) return 'سجّل الدخول أولاً';
    try {
      final at = DateTime.now().add(const Duration(days: 30));
      await _db.doc('users/${u.uid}').set({'deleteAt': Timestamp.fromDate(at)}, SetOptions(merge: true));
      pendingDeleteAt = at;
      await signOut();
      return null;
    } catch (_) {
      return 'تعذّر الطلب، حاول مرة أخرى';
    }
  }

  /// The owner takes his deletion request back within the 30 days.
  Future<String?> cancelDeletion() async {
    final u = user;
    if (!ready || u == null) return 'سجّل الدخول أولاً';
    try {
      await _db.doc('users/${u.uid}').set({'deleteAt': FieldValue.delete()}, SetOptions(merge: true));
      pendingDeleteAt = null;
      notifyListeners();
      return null;
    } catch (_) {
      return 'تعذّر الاستعادة';
    }
  }

  /// Deletes the account now: his questions, his saved data, and the account.
  Future<String?> deleteNow() async {
    if (!ready || user == null) return 'سجّل الدخول أولاً';
    final err = await _deleteEverything();
    return err;
  }

  Future<String?> _deleteEverything() async {
    final u = user;
    if (u == null) return 'سجّل الدخول أولاً';
    try {
      final qs = await _db.collection('questions').where('uid', isEqualTo: u.uid).get();
      for (final d in qs.docs) {
        try {
          await d.reference.delete();
        } catch (_) {}
      }
      await _db.doc('users/${u.uid}').delete();
      pendingDeleteAt = null;
      try {
        await u.delete();
      } on FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login') {
          await signOut();
          return 'حُذفت بياناتك. سجّل الدخول مرة أخرى ثم احذف الحساب لإتمام حذفه';
        }
      }
      await signOut();
      return null;
    } catch (_) {
      return 'تعذّر الحذف، حاول مرة أخرى';
    }
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
      // A deletion the owner asked for: after 30 days it is carried out on
      // his next sign-in; before that he may take it back.
      final del = data['deleteAt'];
      pendingDeleteAt = del is Timestamp ? del.toDate() : null;
      if (pendingDeleteAt != null && DateTime.now().isAfter(pendingDeleteAt!)) {
        await _deleteEverything();
        return;
      }
      final favs = {...repo.favorites, ...((data['favorites'] ?? []) as List).map((e) => '$e')};
      final later = {...repo.readLater, ...((data['readLater'] ?? []) as List).map((e) => '$e')};
      repo.replaceSavedLists(favs, later);
      await doc.set({'favorites': favs.toList(), 'readLater': later.toList()}, SetOptions(merge: true));
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
      }, SetOptions(merge: true));
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
      DayLog.instance.view(id); // sent later, with everything else, in one write
    } catch (_) {}
  }

  Future<Map<String, int>> stats(String id) async {
    if (!ready) return {};
    try {
      // From the site file (four times a day): no Firestore reads.
      final v = (await _viewsFile())[id] ?? const [0, 0, 0];
      return {'count': v[0], 'helpful': v[1], 'notHelpful': v[2]};
    } catch (_) {
      return {};
    }
  }

  Future<bool> vote(String id, bool helpful) async {
    if (!ready) return false;
    try {
      DayLog.instance.vote(id, helpful);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The counts file the server makes four times a day: id -> [views, helpful, notHelpful].
  Future<Map<String, List<int>>> _viewsFile() async {
    final m = await SiteFiles.get('views.json');
    return {
      for (final e in ((m?['v'] ?? {}) as Map).entries)
        '${e.key}': [for (final x in e.value as List) (x as num).toInt()],
    };
  }

  /// Most-read answers: [(id, count)].
  Future<List<(String, int)>> mostRead({int limit = 40}) async {
    if (!ready) return [];
    try {
      final l = [for (final e in (await _viewsFile()).entries) (e.key, e.value[0])]
        ..sort((a, b) => b.$2.compareTo(a.$2));
      return l.take(limit).toList();
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

  /// Developer only: let this admin manage the staff (or stop them).
  Future<String?> setOwner(String email, bool v) async {
    try {
      await _db.doc('admins/$email').set({'owner': v}, SetOptions(merge: true));
      _log(v ? 'منح صلاحية إدارة المشرفين' : 'سحب صلاحية إدارة المشرفين', email);
      return null;
    } catch (_) {
      return 'تعذّر الحفظ';
    }
  }

  Future<void> removeAdmin(String email) async {
    try {
      await _db.doc('admins/$email').delete();
      _log('حذف مشرف', email);
    } catch (_) {}
  }

  // ----------------------------------- Published answers and title edits
  /// The sheikh's in-app answers, title edits and series are kept on the
  /// phone. On opening, the app reads ONE small document (`answers/_ver`) and
  /// downloads them again only if the staff changed something since.
  Future<void> bumpVersion() => _bump();

  Future<void> _bump() async {
    try {
      await _db.doc('answers/_ver').set({'at': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  String? _verNow;

  /// Whether the cached copy is still right (reads one document per session).
  Future<bool> _cacheGood(String what) async {
    try {
      _verNow ??= '${(await _db.doc('answers/_ver').get()).data()?['at']}';
      final p = await SharedPreferences.getInstance();
      return p.getString('${what}Ver') == _verNow && p.getString('${what}Cache') != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> _keep(String what, Object data) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('${what}Cache', jsonEncode(_plain(data)));
    if (_verNow != null) await p.setString('${what}Ver', _verNow!);
  }

  Future<dynamic> _cached(String what) async {
    final p = await SharedPreferences.getInstance();
    return _fromPlain(jsonDecode(p.getString('${what}Cache')!));
  }

  static Object? _plain(Object? v) => v is Timestamp
      ? {'\$ts': v.millisecondsSinceEpoch}
      : v is Map
          ? {for (final e in v.entries) '${e.key}': _plain(e.value)}
          : v is List
              ? [for (final x in v) _plain(x)]
              : v;

  static Object? _fromPlain(Object? v) => v is Map
      ? (v.length == 1 && v.containsKey('\$ts')
          ? Timestamp.fromMillisecondsSinceEpoch((v['\$ts'] as num).toInt())
          : <String, dynamic>{for (final e in v.entries) '${e.key}': _fromPlain(e.value)})
      : v is List
          ? [for (final x in v) _fromPlain(x)]
          : v;

  // ----------------------------------- Published answers and title edits
  /// [startup]: may use the copy on the phone. After a staff change it is
  /// always fetched again (and the others are told by `answers/_ver`).
  Future<void> loadRemoteAnswers({bool startup = false}) async {
    if (!ready) return;
    try {
      Map<String, Map<String, dynamic>> docs, edits;
      if (startup && await _cacheGood('answers')) {
        final c = await _cached('answers') as Map<String, dynamic>;
        docs = {for (final e in (c['a'] as Map).entries) '${e.key}': Map<String, dynamic>.from(e.value as Map)};
        edits = {for (final e in (c['e'] as Map).entries) '${e.key}': Map<String, dynamic>.from(e.value as Map)};
      } else {
        if (!startup) {
          await _bump();
          _verNow = null;
          await _cacheGood('answers');
        }
        final answers = await _db.collection('answers').get();
        final ed = await _db.collection('titleEdits').get();
        docs = {for (final d in answers.docs) if (!d.id.startsWith('_')) d.id: d.data()};
        edits = {for (final d in ed.docs) d.id: d.data()};
        await _keep('answers', {'a': docs, 'e': edits});
      }
      final now = DateTime.now();
      // Answers scheduled for later stay hidden until their time comes.
      bool isLater(Map<String, dynamic> m) {
        final t = m['publishAt'];
        return t is Timestamp && t.toDate().isAfter(now);
      }

      final visible = [for (final e in docs.entries) if (!isLater(e.value)) e];
      scheduled = [
        for (final e in docs.entries)
          if (isLater(e.value)) (e.key, '${e.value['title'] ?? ''}', (e.value['publishAt'] as Timestamp).toDate()),
      ]..sort((a, b) => a.$3.compareTo(b.$3));
      remoteIds = {for (final e in visible) e.key};
      editSigs = {
        for (final id in {...docs.keys, ...edits.keys})
          if (!id.startsWith('_')) id: _fnv(jsonEncode(_plain({'d': docs[id], 'e': {...?edits[id]}..removeWhere((k, _) => const {'summary', 'verified', 'by', 'at', 'verifiedBy'}.contains(k))}))),
      };
      unawaited(_baselineSaved());
      summaries = {
        for (final e in edits.entries)
          if ('${e.value['summary'] ?? ''}'.trim().isNotEmpty) e.key: '${e.value['summary']}'.trim(),
      };
      Repository.instance.applyRemote(
        [
          for (final e in visible)
            Fatwa.fromJson({
              for (final x in e.value.entries)
                if (x.key != 'publishAt') x.key: x.value,
              'id': e.key,
            }),
        ],
        edits,
      );
    } catch (e) {
      debugPrint('remote answers failed: $e');
    }
  }

  /// The id of the answer published last (to post it in the channel too).
  String lastPublishedId = '';

  Future<String?> publishAnswer({
    required String chapter,
    required String title,
    required String question,
    required String answer,
    List<String> tags = const [],
    DateTime? publishAt,
    String sub = '',
    String audio = '',
    String type = 'fatwa',
  }) async {
    try {
      final now = publishAt ?? DateTime.now();
      final ref = await _db.collection('answers').add({
        if (publishAt != null) 'publishAt': Timestamp.fromDate(publishAt),
        'chapter': chapter,
        'type': type,
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
      lastPublishedId = ref.id;
      _log(publishAt == null ? 'نشر جواب' : 'جدولة جواب', title);
      await loadRemoteAnswers();
      return null;
    } catch (_) {
      return 'تعذّر النشر';
    }
  }

  /// Title, chapter and sub-chapter of an answer that came with the app
  /// (e.g. from the sheikh's channel).
  Future<String?> editBundled(String id,
      {required String title, required String chapter, required String sub, String? question, String? answer}) async {
    try {
      await _db.doc('titleEdits/$id').set({
        'title': title.trim(),
        'chapter': chapter,
        'sub': sub.trim(),
        if (answer != null && answer.trim().isNotEmpty) ...{
          'question': (question ?? '').trim(),
          'answer': answer.trim(),
        },
        'verified': true,
        'by': email,
      }, SetOptions(merge: true));
      _log('تعديل جواب', title);
      await loadRemoteAnswers();
      return null;
    } catch (_) {
      return 'تعذّر الحفظ';
    }
  }

  /// Hide an answer from the app (or show it again). Nothing is deleted.
  Future<String?> setHidden(String id, bool hidden, [String title = '']) async {
    try {
      await _db.doc('titleEdits/$id').set({'hidden': hidden, 'by': email}, SetOptions(merge: true));
      _log(hidden ? 'إخفاء جواب' : 'إظهار جواب', title);
      await loadRemoteAnswers();
      return null;
    } catch (_) {
      return 'تعذّر الحفظ';
    }
  }

  /// A fingerprint of each answer the staff changed in the app, to tell a
  /// reader when the sheikh edits an answer he saved.
  Map<String, String> editSigs = {};
  Set<String> editedSaved = {};

  static String _fnv(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16);
  }

  /// Saved answers get their fingerprint remembered the first time; after
  /// that, a different fingerprint means the sheikh edited it.
  Future<void> _baselineSaved() async {
    final p = await SharedPreferences.getInstance();
    final out = <String>{};
    for (final id in Repository.instance.favorites) {
      final now = editSigs[id] ?? '';
      final seen = p.getString('editSeen_$id');
      if (seen == null) {
        await p.setString('editSeen_$id', now);
      } else if (seen != now) {
        out.add(id);
      }
    }
    editedSaved = out;
    notifyListeners();
  }

  /// Opening the answer clears its «عدّله الشيخ» mark.
  Future<void> markEditSeen(String id) async {
    if (!editedSaved.contains(id) && !Repository.instance.favorites.contains(id)) return;
    final p = await SharedPreferences.getInstance();
    await p.setString('editSeen_$id', editSigs[id] ?? '');
    if (editedSaved.remove(id)) notifyListeners();
  }

  /// One-line summaries the staff approved: answer id -> line.
  Map<String, String> summaries = {};

  /// Staff: approve (or remove, with an empty line) an answer's summary.
  Future<String?> setSummary(String id, String line, [String title = '']) async {
    try {
      await _db.doc('titleEdits/$id').set({'summary': line.trim(), 'by': email}, SetOptions(merge: true));
      _log(line.trim().isEmpty ? 'حذف ملخص جواب' : 'اعتماد ملخص جواب', title);
      await loadRemoteAnswers();
      return null;
    } catch (_) {
      return 'تعذّر الحفظ';
    }
  }

  // ------------------------------------------- «رتّب بالذكاء الاصطناعي»
  static String _cut(String t, int n) => t.length <= n ? t : t.substring(0, n);
  bool aiSorting = false;
  bool _stopSort = false;
  void stopAiSort() => _stopSort = true;

  /// Puts the channel posts that are not verified into their right chapters.
  /// Verified posts and posts the staff placed are never touched; nothing is
  /// deleted; unsure ones go to «متفرقات». All choices are kept in ONE
  /// document (titleEdits/_ai), written once per batch of posts.
  /// [onStep]: (done, total). Can be stopped and started again later.
  Future<String?> aiSort({void Function(int, int)? onStep}) async {
    if (aiSorting) return null;
    aiSorting = true;
    _stopSort = false;
    notifyListeners();
    try {
      final repo = Repository.instance;
      final done = Map<String, dynamic>.from(((await _db.doc('titleEdits/_ai').get()).data()?['m'] as Map?) ?? {});
      final todo = [
        for (final f in repo.fatwas)
          if (f.id.startsWith('tg-') &&
              !repo.verifiedIds.contains(f.id) &&
              !repo.sortedIds.contains(f.id) &&
              !done.containsKey(f.id))
            f
      ];
      final chapters = [for (final c in repo.chapters) (c.id, c.name)];
      final total = todo.length;
      var n = 0, fails = 0;
      onStep?.call(0, total);
      for (var i = 0; i < todo.length && !_stopSort; i += 30) {
        final part = todo.sublist(i, math.min(i + 30, todo.length));
        final res = await Ai.sortPosts([
          for (final f in part)
            (f.id, '${f.title}\n${_cut('${f.question} ${f.answer}'.trim().replaceAll(RegExp(r'\s+'), ' '), 350)}'),
        ], chapters);
        if (res.isEmpty) {
          if (++fails >= 3) break;
          i -= 30; // try this batch again
          continue;
        }
        fails = 0;
        await _db.doc('titleEdits/_ai').set({'m': res}, SetOptions(merge: true));
        n += part.length;
        onStep?.call(n, total);
      }
      if (n > 0) {
        _log('ترتيب المنشورات بالذكاء الاصطناعي', '$n منشوراً');
        await loadRemoteAnswers();
      }
      if (total == 0) return 'كل المنشورات مرتّبة';
      if (n == 0) return Ai.supported ? 'لم يرجع الذكاء الاصطناعي بجواب، حاول بعد قليل' : 'هذا يعمل من تطبيق الأندرويد';
      return null;
    } catch (e) {
      return 'تعذّر: $e';
    } finally {
      aiSorting = false;
      notifyListeners();
    }
  }

  /// Move an answer to a chapter with one tap (the review page).
  Future<String?> setChapter(String id, String chapter, [String title = '']) async {
    try {
      await _db.doc('titleEdits/$id').set({'chapter': chapter, 'verified': true, 'by': email}, SetOptions(merge: true));
      _bump();
      _log('نقل إلى باب', title);
      Repository.instance.verifiedIds.add(id);
      final f = Repository.instance.findById(id);
      if (f != null) f.chapter = chapter;
      Repository.instance.sortedIds.add(id);
      return null;
    } catch (_) {
      return 'تعذّر الحفظ';
    }
  }

  /// Mark an answer as checked by the sheikh / staff (or undo it).
  Future<String?> setVerified(String id, bool v, [String title = '']) async {
    try {
      await _db.doc('titleEdits/$id').set({'verified': v, 'by': email}, SetOptions(merge: true));
      _bump();
      _log(v ? 'تحقق من جواب' : 'إلغاء التحقق', title);
      if (v) {
        Repository.instance.verifiedIds.add(id);
      } else {
        Repository.instance.verifiedIds.remove(id);
      }
      notifyListeners();
      return null;
    } catch (_) {
      return 'تعذّر الحفظ';
    }
  }

  // ---- «اسأل الشيخ» settings: open/closed and how many questions a day
  int askLimit = 3;
  Map<String, int> askLimits = {}; // uid → that person's own daily limit

  int askLimitFor(String? uid) => askLimits[uid] ?? askLimit;

  Future<String?> saveAsk({bool? open, int? limit, String? uid, int? userLimit, String logText = 'تعديل إعدادات الأسئلة'}) {
    final per = {...askLimits};
    if (uid != null) {
      if (userLimit == null) {
        per.remove(uid);
      } else {
        per[uid] = userLimit;
      }
    }
    return setConfig('ask', {'open': open ?? askOpen, 'limit': limit ?? askLimit, 'limits': per}, logText);
  }

  static String _weekKey() {
    final now = DateTime.now().toUtc();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  }

  // --------------------------------------------------------------- Usage
  /// Developer: people per day and hour, and minutes per reader number, from
  /// the file the server makes four times a day (no Firestore reads). With
  /// [live], today is counted straight from the phones' day documents
  /// (one read per phone that came today).
  Future<List<UsageDay>> usage({bool live = false}) async {
    final m = await SiteFiles.get('usage.json', fresh: true);
    final out = <UsageDay>[];
    for (final e in ((m?['days'] ?? {}) as Map).entries) {
      final d = Map<String, dynamic>.from(e.value as Map);
      out.add(UsageDay(
        DateTime.parse('${e.key}T00:00:00Z'),
        (d['people'] as num?)?.toInt() ?? 0,
        (d['web'] as num?)?.toInt() ?? 0,
        [for (final x in (d['hours'] as List? ?? List.filled(24, 0))) (x as num).toInt()],
        {for (final x in ((d['minutes'] ?? {}) as Map).entries) '${x.key}': (x.value as num).toInt()},
      ));
    }
    out.sort((a, b) => b.day.compareTo(a.day));
    if (live) {
      try {
        final t = DayLog.today;
        final q = await _db.collection('searches').where('day', isEqualTo: t).get();
        final hours = List<int>.filled(24, 0);
        final mins = <String, int>{};
        var web = 0;
        for (final d in q.docs) {
          final x = d.data();
          for (final h in ((x['hr'] ?? {}) as Map).keys) {
            final i = int.tryParse('$h') ?? -1;
            if (i >= 0 && i < 24) hours[i]++;
          }
          if (x['web'] == true) web++;
          if (x['u'] != null) mins['${x['u']}'] = (x['min'] as num?)?.toInt() ?? 0;
        }
        out.removeWhere((u) => DayLog.dayKey(u.day) == t);
        out.insert(0, UsageDay(DateTime.parse('${t}T00:00:00Z'), q.docs.length, web, hours, mins));
      } catch (_) {}
    }
    return out;
  }

  /// Counts an answer opened from the search results this week. Only the
  /// sheikh's own answers can appear, never what people typed.
  Future<void> countSearchOpen(String answerId) async {
    if (!ready) return;
    try {
      await _db.doc('searches/${_weekKey()}').set({answerId: FieldValue.increment(1)}, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Answers people reached most through search this week (ids, best first).
  Future<List<String>> mostSearched({int limit = 10}) async {
    if (!ready) return [];
    try {
      final d = await _db.doc('searches/${_weekKey()}').get();
      final m = d.data() ?? {};
      final list = [
        for (final e in m.entries)
          if (e.value is int) (e.key, e.value as int),
      ]..sort((a, b) => b.$2.compareTo(a.$2));
      return [for (final e in list.take(limit)) e.$1];
    } catch (_) {
      return [];
    }
  }

  /// The sheikh's lessons timetable (free text; hidden while empty).
  String schedule = '';

  /// The announcement shows only between these times (ms; 0 = no limit).
  int annFrom = 0, annTo = 0;
  bool get announcementNow {
    final n = DateTime.now().millisecondsSinceEpoch;
    return announcement.isNotEmpty && (annFrom == 0 || n >= annFrom) && (annTo == 0 || n < annTo);
  }

  /// «جدول الدروس»: hidden from readers until the sheikh turns it on.
  bool timetableOn = false;
  List<Map<String, dynamic>> timetable = [];

  /// «تذكيرات السنن»: off until the sheikh turns them on; he edits the texts.
  bool sunanOn = false;
  Map<String, String> sunanTexts = {};

  /// «مجلس العلم»: the sheikh's live lesson.
  bool liveOn = false;
  String liveUrl = '', liveTitle = '', liveRoom = '';

  /// «حاسبة الزكاة»: shown to readers after the sheikh approves it.
  bool zakatOn = false;
  String zakatNote = '';

  /// Counts this device once a day, so the staff see how many *readers*
  /// came (not how many pages were opened).
  Future<void> countVisit() async {} // each phone's day document counts it now

  /// A reader's suggestion for the developer (arrives with the reports).
  Future<String?> suggest(String text) async {
    if (!ready) return 'يحتاج اتصالاً بالإنترنت';
    try {
      await _db.collection('reports').add({
        'answerId': 'suggestion',
        'title': 'اقتراح للمطوّر',
        'note': text.trim(),
        'by': email ?? '',
        'at': FieldValue.serverTimestamp(),
      });
      return null;
    } catch (_) {
      return 'تعذّر الإرسال';
    }
  }

  Future<String?> editTitle(String id, String title) async {
    try {
      await _db.doc('titleEdits/$id').set({'title': title.trim(), 'by': email}, SetOptions(merge: true));
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
      final m = await SiteFiles.get('views.json', fresh: true);
      var total = 0, helpful = 0, notHelpful = 0, answersViewed = 0;
      final shares = (m?['shares'] as num?)?.toInt() ?? 0;
      var readersToday = 0, readersWeek = 0;
      for (final e in ((m?['readers'] ?? {}) as Map).entries) {
        final day = DateTime.tryParse('${e.key}T00:00:00Z');
        final c = (e.value as num).toInt();
        if (day == null) continue;
        final age = DateTime.now().toUtc().difference(day).inDays;
        if (age == 0) readersToday = c;
        if (age >= 0 && age < 7) readersWeek += c;
      }
      for (final v in (await _viewsFile()).values) {
        answersViewed++;
        total += v[0];
        helpful += v[1];
        notHelpful += v[2];
      }
      final reports = await _db.collection('reports').count().get();
      final published = await _db.collection('answers').count().get();
      return {
        'views': total,
        'answersViewed': answersViewed,
        'shares': shares,
        'readersToday': readersToday,
        'readersWeek': readersWeek,
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
      // The same post in the channel is edited too (if the app posted it).
      unawaited(TelegramOut.queueEdit(
          id,
          TelegramOut.format(
              form: question.trim().isEmpty ? 'article' : 'qa', title: title, question: question, text: answer, link: TelegramOut.linkOf(id))));
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
      return [for (final e in (await _viewsFile()).entries) (e.key, e.value[1], e.value[2])];
    } catch (_) {
      return [];
    }
  }

  // --------------------------------------------------------- Announcement
  String announcement = '';
  String annColor = 'gold'; // gold | red | yellow | pink | green | blue
  String annPlace = 'middle'; // top | middle | bottom
  String annAction = ''; // '' | challenges | quiz
  String annButton = '';

  bool askOpen = true;
  String aboutText = '';
  List<String> pinned = [];

  /// Loads every settings document at once.
  Future<void> loadConfig({bool fresh = false}) async {
    if (!ready) return;
    try {
      // Kept on the phone too; fetched again only after a staff change.
      Map<String, dynamic> c;
      if (!fresh && await _cacheGood('config')) {
        c = await _cached('config') as Map<String, dynamic>;
      } else {
        final q = await _db.collection('config').get();
        c = {for (final d in q.docs) d.id: d.data()};
        await _keep('config', c);
      }
      final an = c['announcement'];
      announcement = an != null && an['active'] == true ? '${an['text'] ?? ''}' : '';
      annColor = '${an?['color'] ?? 'gold'}';
      annPlace = '${an?['place'] ?? 'middle'}';
      annAction = '${an?['action'] ?? ''}';
      annButton = '${an?['button'] ?? ''}';
      askOpen = c['ask']?['open'] != false;
      final lim = c['ask']?['limit'];
      askLimit = lim is int && lim > 0 ? lim : 3;
      askLimits = {
        for (final e in ((c['ask']?['limits'] ?? {}) as Map).entries)
          if (e.value is int) '${e.key}': e.value as int,
      };
      schedule = '${c['schedule']?['text'] ?? ''}';
      annFrom = (an?['from'] as num?)?.toInt() ?? 0;
      annTo = (an?['to'] as num?)?.toInt() ?? 0;
      timetableOn = c['timetable']?['on'] == true;
      timetable = [
        for (final m in ((c['timetable']?['items'] ?? []) as List))
          if (m is Map) Map<String, dynamic>.from(m),
      ];
      sunanOn = c['sunan']?['on'] == true;
      sunanTexts = {
        for (final e in ((c['sunan']?['texts'] ?? {}) as Map).entries) '${e.key}': '${e.value}',
      };
      liveOn = c['live']?['on'] == true;
      liveUrl = '${c['live']?['url'] ?? ''}';
      liveTitle = '${c['live']?['title'] ?? ''}';
      liveRoom = '${c['live']?['room'] ?? ''}';
      zakatOn = c['zakat']?['on'] == true;
      zakatNote = '${c['zakat']?['note'] ?? ''}';
      subs = {
        for (final e in ((c['subs']?['map'] ?? {}) as Map).entries)
          '${e.key}': ((e.value ?? []) as List).map((x) => '$x').toList(),
      };
      Repository.instance.extraSynonyms = {
        for (final e in ((c['synonyms']?['map'] ?? {}) as Map).entries)
          '${e.key}': ((e.value ?? []) as List).map((x) => '$x').toList(),
      };
      extraVideos = [
        for (final m in ((c['videos']?['items'] ?? []) as List))
          if (m is Map) Video(id: '${m['id'] ?? ''}', title: '${m['title'] ?? ''}', published: '${m['published'] ?? ''}'),
      ];
      Repository.instance.setExtraVideos(extraVideos);
      lessons = [
        for (final m in ((c['lessons']?['items'] ?? []) as List))
          if (m is Map) Lesson('${m['title'] ?? ''}', '${m['url'] ?? ''}', '${m['group'] ?? ''}'),
      ];
      final mb = c['app']?['minBuild'];
      minBuild = mb is int ? mb : 0;
      // Until the staff save their own list, the first entry the developer asked for is shown.
      if (c['accounts'] != null) {
        accounts = [
          for (final p in (c['accounts']?['people'] ?? []) as List) Map<String, dynamic>.from(p as Map),
        ];
      }
      aiEnabled = c['ai']?['enabled'] != false;
      aiSummary = c['ai']?['summary'] != false;
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
        {
          for (final e in ((ch?['icons'] ?? {}) as Map).entries) '${e.key}': '${e.value}',
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

  /// Videos the staff added by link (shown before the fetched ones).
  List<Video> extraVideos = [];

  Future<String?> setVideos(List<Video> list, String logText) async {
    final err = await setConfig(
        'videos',
        {'items': [for (final v in list) {'id': v.id, 'title': v.title, 'published': v.published}]},
        logText);
    if (err == null) {
      extraVideos = list;
      Repository.instance.setExtraVideos(list);
      notifyListeners();
    }
    return err;
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
      DayLog.instance.share();
    } catch (_) {}
  }

  /// Builds older than this must update (0 = no forced update).
  int minBuild = 0;

  /// Scholars and others added by the staff, each with his accounts.
  List<Map<String, dynamic>> accounts = [
    {
      'name': 'الشيخ سلمان صالح العماد',
      'title': '',
      'about': '',
      'links': [
        {'platform': 'telegram', 'name': 'قناة الشيخ على تيليجرام', 'url': 'https://t.me/salmansalehalemad', 'note': ''},
      ],
    },
  ];

  /// The staff can switch the AI help off, or only its written summary.
  bool aiEnabled = true;
  bool aiSummary = true;

  /// A reader reports a wrong AI summary; it reaches the staff's reports.
  Future<String?> reportAi(String question, String summary) async {
    if (!ready) return 'يحتاج اتصالاً بالإنترنت';
    try {
      final note = 'السؤال: $question\n\nالتلخيص: $summary';
      await _db.collection('reports').add({
        'answerId': 'ai',
        'title': 'خطأ في تلخيص الذكاء الاصطناعي',
        'note': note.length > 1900 ? note.substring(0, 1900) : note,
        'by': email ?? '',
        'at': FieldValue.serverTimestamp(),
      });
      return null;
    } catch (_) {
      return 'تعذّر الإرسال';
    }
  }

  Future<String?> setConfig(String id, Map<String, dynamic> data, String logText) async {
    try {
      await _db.doc('config/$id').set(data);
      _log(logText);
      await _bump();
      await loadConfig(fresh: true);
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

  Future<String?> setAnnouncement(String text,
      {String color = 'gold', String place = 'middle', String action = '', String button = '', int from = 0, int to = 0}) async {
    try {
      final t = text.trim();
      await _db.doc('config/announcement').set({
        'text': t,
        'active': t.isNotEmpty,
        'by': email,
        'color': color,
        'place': place,
        'action': action,
        'button': button.trim(),
        'from': from,
        'to': to,
      });
      annFrom = from;
      annTo = to;
      _log(t.isEmpty ? 'إزالة الإعلان' : 'نشر إعلان', t);
      await _bump();
      announcement = t;
      annColor = color;
      annPlace = place;
      annAction = action;
      annButton = button.trim();
      notifyListeners();
      return null;
    } catch (_) {
      return 'تعذّر الحفظ';
    }
  }

  // --------------------------------------------------------------- Series
  List<Series> series = [];

  Future<void> loadSeries({bool startup = false}) async {
    if (!ready) return;
    try {
      Map<String, dynamic> m;
      if (startup && await _cacheGood('series')) {
        m = await _cached('series') as Map<String, dynamic>;
      } else {
        if (!startup) {
          await _bump();
          _verNow = null;
          await _cacheGood('series');
        }
        final q = await _db.collection('series').get();
        m = {for (final d in q.docs) d.id: d.data()};
        await _keep('series', m);
      }
      series = [
        for (final e in m.entries)
          Series(e.key, '${(e.value as Map)['title'] ?? ''}',
              (((e.value as Map)['ids'] ?? []) as List).map((x) => '$x').toList(),
              track: (e.value as Map)['track'] == true),
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
  Future<String?> ask(String text, {String chapter = '', String name = '', String about = ''}) async {
    // [about] is not stored (the rules accept only the known fields); the
    // answer is found again from its title written in the text.
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
        if (name.trim().isNotEmpty) 'name': name.trim(),
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

  /// A star or a pin on a question, for the sheikh and the staff.
  Future<void> setQuestionFlag(String id, String field, bool value) async {
    try {
      await _db.doc('questions/$id').update({field: value});
    } catch (_) {}
  }

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

  /// A message the sheikh starts himself to one reader (no question before it).
  Future<String?> messageReader(String uid, String text) async {
    final t = text.trim();
    if (t.isEmpty) return 'اكتب الرسالة';
    try {
      await _db.collection('questions').add({
        'uid': uid,
        'text': '',
        'chapter': '',
        'at': FieldValue.serverTimestamp(),
        'status': 'answered',
        'reply': t,
        'published': false,
        'fromSheikh': true,
        'replyAt': FieldValue.serverTimestamp(),
      });
      _log('رسالة من الشيخ إلى السائل رقم ${askerNo(uid)}', t);
      return null;
    } catch (_) {
      return 'تعذّر الإرسال، تأكد من نشر القواعد الجديدة.';
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

/// A fixed four-digit number for an asker, made from his account id, so the
/// sheikh can tell askers apart without knowing who they are.
/// Each reader's public number: six digits, the same on every phone.
int askerNo(String uid) {
  var h = 7;
  for (final c in uid.codeUnits) {
    h = (h * 31 + c) % 900000;
  }
  return 100000 + h;
}


class UsageDay {
  final DateTime day; // UTC
  final int people, web;
  final List<int> hours; // people in each UTC hour
  final Map<String, int> minutes; // device number -> minutes that day
  const UsageDay(this.day, this.people, this.web, this.hours, this.minutes);
}
