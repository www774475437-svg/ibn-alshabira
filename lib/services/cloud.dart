import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../data/models.dart';
import '../data/repository.dart';

/// Online features (Android app only): Google sign-in, admins, views,
/// «هل أفادك الجواب؟», error reports, published answers and title edits.
/// The website works without it.
class Cloud extends ChangeNotifier {
  Cloud._();
  static final Cloud instance = Cloud._();

  /// The developer is always an admin.
  static const developerEmail = 'www774475437@gmail.com';

  bool ready = false;
  User? user;
  bool isAdmin = false;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<void> init() async {
    if (kIsWeb) return;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'AIzaSyCOpkQxy5gP2-PuFAphg_tlJBv2gI8RkVI',
          appId: '1:402664894391:android:b09cad286f2dd5a1604232',
          messagingSenderId: '402664894391',
          projectId: 'ibn-alshabira',
          storageBucket: 'ibn-alshabira.firebasestorage.app',
        ),
      );
      ready = true;
      FirebaseAuth.instance.authStateChanges().listen((u) async {
        user = u;
        await _checkAdmin();
        if (u != null) await _syncUserData();
        notifyListeners();
      });
      await loadRemoteAnswers();
    } catch (e) {
      debugPrint('Cloud init failed: $e');
      ready = false;
    }
    notifyListeners();
  }

  String? get email => user?.email?.toLowerCase();

  Future<void> _checkAdmin() async {
    final e = email;
    if (e == null) {
      isAdmin = false;
      return;
    }
    if (e == developerEmail) {
      isAdmin = true;
      return;
    }
    try {
      isAdmin = (await _db.doc('admins/$e').get()).exists;
    } catch (_) {
      isAdmin = false;
    }
  }

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

  Future<void> signOut() async {
    if (!ready) return;
    try {
      await _ensureGoogle();
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
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
      return [for (final d in q.docs) (d.id, (d.data()['count'] ?? 0) as int)];
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

  Future<String?> addAdmin(String email) async {
    final e = email.trim().toLowerCase();
    if (!e.contains('@') || !e.contains('.')) return 'اكتب بريداً صحيحاً';
    try {
      await _db.doc('admins/$e').set({'addedBy': this.email, 'at': FieldValue.serverTimestamp()});
      return null;
    } catch (_) {
      return 'تعذّرت الإضافة';
    }
  }

  Future<void> removeAdmin(String email) => _db.doc('admins/$email').delete();

  // ----------------------------------- Published answers and title edits
  Future<void> loadRemoteAnswers() async {
    if (!ready) return;
    try {
      final answers = await _db.collection('answers').get();
      final edits = await _db.collection('titleEdits').get();
      Repository.instance.applyRemote(
        [for (final d in answers.docs) Fatwa.fromJson({...d.data(), 'id': d.id})],
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
  }) async {
    try {
      final now = DateTime.now();
      await _db.collection('answers').add({
        'chapter': chapter,
        'type': 'fatwa',
        'title': title.trim(),
        'question': question.trim(),
        'answer': answer.trim(),
        'tags': <String>[],
        'date': '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        'source': '',
        'by': email,
      });
      await loadRemoteAnswers();
      return null;
    } catch (_) {
      return 'تعذّر النشر';
    }
  }

  Future<String?> editTitle(String id, String title) async {
    try {
      await _db.doc('titleEdits/$id').set({'title': title.trim(), 'by': email});
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
      var total = 0, helpful = 0, notHelpful = 0;
      for (final d in views.docs) {
        total += (d.data()['count'] ?? 0) as int;
        helpful += (d.data()['helpful'] ?? 0) as int;
        notHelpful += (d.data()['notHelpful'] ?? 0) as int;
      }
      final reports = await _db.collection('reports').count().get();
      final published = await _db.collection('answers').count().get();
      return {
        'views': total,
        'answersViewed': views.docs.length,
        'helpful': helpful,
        'notHelpful': notHelpful,
        'reports': reports.count ?? 0,
        'published': published.count ?? 0,
      };
    } catch (_) {
      return {};
    }
  }
}
