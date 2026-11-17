import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../config.dart';
import 'cloud.dart';
import 'site_files.dart';

/// Publishing to the sheikh's Telegram channels from the app, safely: the app
/// never holds the bot's key. It leaves a request in Firestore (staff only);
/// the server, which holds the key hidden, posts it within minutes.
/// Text goes to the main channel, voice to the recordings channel. The bot
/// can post and edit only — never delete.
class TelegramOut {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static String linkOf(String answerId) => AppConfig.fatwaLink(answerId);

  /// [form]: 'qa' (question then answer) or 'article' (title then text).
  /// The form is for the sheikh only; nothing like «مقالة» is written.
  static String format({required String form, String title = '', String question = '', required String text, String link = ''}) {
    final b = StringBuffer();
    if (form == 'qa' && question.trim().isNotEmpty) {
      b.writeln('السؤال:');
      b.writeln(question.trim());
      b.writeln();
      b.writeln('الجواب:');
      b.writeln(text.trim());
    } else {
      if (title.trim().isNotEmpty) {
        b.writeln(title.trim());
        b.writeln();
      }
      b.writeln(text.trim());
    }
    if (link.isNotEmpty) {
      b.writeln();
      b.write('🔗 $link');
    }
    final s = b.toString().trim();
    return s.length > 4000 ? '${s.substring(0, 3990)}…' : s;
  }

  static Future<String?> queueText(String text, {String answerId = '', DateTime? at}) async {
    try {
      await _db.collection('tgQueue').add({
        'kind': 'text',
        'channel': 'main',
        'text': text,
        'answerId': answerId,
        'at': (at ?? DateTime.now()).millisecondsSinceEpoch,
        'by': Cloud.instance.email,
        'made': FieldValue.serverTimestamp(),
      });
      await _kick();
      return null;
    } catch (_) {
      return 'تعذّر إرسال طلب النشر';
    }
  }

  /// After an edit in the app, the same post in the channel is edited too.
  static Future<void> queueEdit(String answerId, String text) async {
    if (!(await posted()).containsKey(answerId)) return;
    try {
      await _db.collection('tgQueue').add({
        'kind': 'edit',
        'channel': 'main',
        'text': text,
        'answerId': answerId,
        'at': DateTime.now().millisecondsSinceEpoch,
        'by': Cloud.instance.email,
      });
      await _kick();
    } catch (_) {}
  }

  /// A voice recording, sent to the recordings channel. Firestore holds it in
  /// pieces until the server has posted it.
  static Future<String?> queueVoice(Uint8List bytes, String ext, {String caption = '', String answerId = '', DateTime? at}) async {
    try {
      final ref = _db.collection('tgQueue').doc();
      final b64 = base64Encode(bytes);
      const size = 700000;
      var n = 0;
      for (var i = 0; i < b64.length; i += size) {
        await _db.doc('tgVoice/${ref.id}_$n').set({
          'q': ref.id,
          'n': n,
          'data': b64.substring(i, i + size > b64.length ? b64.length : i + size),
        });
        n++;
      }
      await ref.set({
        'kind': 'voice',
        'channel': 'audio',
        'text': caption,
        'ext': ext,
        'parts': n,
        'answerId': answerId,
        'at': (at ?? DateTime.now()).millisecondsSinceEpoch,
        'by': Cloud.instance.email,
        'made': FieldValue.serverTimestamp(),
      });
      await _kick();
      return null;
    } catch (_) {
      return 'تعذّر رفع التسجيل';
    }
  }

  /// Answers already in the channel: answer id -> message number.
  static Future<Map<String, int>> posted() async {
    final m = await SiteFiles.get('posted.json', fresh: true);
    return {
      for (final e in ((m?['answers'] ?? {}) as Map).entries) '${e.key}': (e.value as num).toInt(),
    };
  }

  /// Voice answers: answer id -> message number in the recordings channel.
  static Future<Map<String, int>> voices() async {
    final m = await SiteFiles.get('posted.json');
    return {
      for (final e in ((m?['voices'] ?? {}) as Map).entries) '${e.key}': (e.value as num).toInt(),
    };
  }

  /// Channel posts the app itself made (so they are not pulled back in twice).
  static Future<Set<int>> postedIds() async {
    final m = await SiteFiles.get('posted.json');
    return {for (final x in (m?['ids'] as List? ?? const [])) (x as num).toInt()};
  }

  /// Asks the server to look now (a small flag; the server checks it).
  static Future<void> _kick() async {
    try {
      await _db.doc('answers/_tgNow').set({'at': FieldValue.serverTimestamp()});
    } catch (_) {}
  }
}
