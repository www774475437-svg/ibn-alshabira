import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// The questions a long message holds, each with short phrases to search for.
class AiIssue {
  final String title;
  final List<String> queries;
  AiIssue(this.title, this.queries);
}

/// A short ruling written only from the scholar's quoted texts.
class AiSummary {
  final bool found;
  final String text;
  final List<int> used; // which of the given texts it relied on (from 0)
  AiSummary(this.found, this.text, this.used);
}

/// Gemini through Firebase AI Logic. No key is kept in the app: Firebase
/// checks that the request comes from this app (App Check) and adds the key.
class Ai {
  // Tried in order, so the feature keeps working when a model is retired.
  static const _models = ['gemini-3.5-flash', 'gemini-2.5-flash'];
  static bool _prepared = false;

  /// App Check is registered for the Android app only.
  static bool get supported => !kIsWeb;

  static Future<void> _prepare() async {
    if (_prepared) return;
    _prepared = true;
    try {
      await FirebaseAppCheck.instance.activate();
    } catch (_) {}
  }

  static Future<dynamic> _json(String prompt) async {
    if (!supported) return null;
    await _prepare();
    for (final name in _models) {
      try {
        final model = FirebaseAI.googleAI(appCheck: FirebaseAppCheck.instance).generativeModel(
          model: name,
          generationConfig: GenerationConfig(temperature: 0, responseMimeType: 'application/json'),
        );
        final res = await model.generateContent([Content.text(prompt)]).timeout(const Duration(seconds: 45));
        final t = (res.text ?? '').trim();
        if (t.isEmpty) continue;
        // The answer is JSON; cut away anything around it just in case.
        final a = t.indexOf(RegExp(r'[\[{]'));
        final b = t.lastIndexOf(RegExp(r'[\]}]'));
        if (a < 0 || b <= a) continue;
        return jsonDecode(t.substring(a, b + 1));
      } catch (_) {}
    }
    return null;
  }

  /// Splits a message into its questions. Does not answer anything.
  static Future<List<AiIssue>?> split(String question) async {
    final j = await _json('''
أنت تقسّم رسالة المستفتي إلى مسائلها الشرعية فقط، ولا تجيب عن شيء ولا تذكر أي حكم.
أعد JSON فقط بهذا الشكل: [{"title": "عنوان المسألة بكلمات قليلة", "queries": ["عبارة بحث", "عبارة بحث أخرى"]}]
- المسائل أربع على الأكثر، بترتيب ورودها في الرسالة.
- كل عبارة بحث من كلمتين إلى أربع كلمات، بألفاظ الفقهاء التي ترد في كتب الفتاوى، مثل: «قتل النمل»، «رفع الصوت على الوالدين»، «شروط التوبة».
- لكل مسألة عبارتان أو ثلاث مختلفة الألفاظ.
الرسالة:
$question''');
    if (j is! List) return null;
    final out = <AiIssue>[];
    for (final e in j) {
      if (e is! Map) continue;
      final title = '${e['title'] ?? ''}'.trim();
      final qs = [
        for (final q in (e['queries'] is List ? e['queries'] as List : const []))
          if ('$q'.trim().length > 2) '$q'.trim(),
      ];
      if (title.isNotEmpty && qs.isNotEmpty) out.add(AiIssue(title, qs.take(3).toList()));
    }
    return out.isEmpty ? null : out.take(4).toList();
  }

  /// A short ruling built only from [texts] (the scholar's own words).
  static Future<AiSummary?> summarize(String scholar, String issue, List<String> texts) async {
    final body = StringBuffer();
    for (var i = 0; i < texts.length; i++) {
      final t = texts[i].length > 1800 ? texts[i].substring(0, 1800) : texts[i];
      body.writeln('[${i + 1}] $t');
    }
    final j = await _json('''
بين يديك نصوص منقولة حرفياً من كتب الشيخ $scholar، ومسألة يسأل عنها مستفتٍ.
اكتب جواباً مختصراً (من سطرين إلى أربعة) يلخّص ما قاله الشيخ في هذه المسألة، معتمداً على هذه النصوص وحدها.
قواعد لا تُخالَف:
- لا تذكر أي حكم أو دليل أو معلومة ليست في النصوص، ولا تجتهد من عندك.
- انسب الكلام للشيخ بصيغة مثل: «ذكر الشيخ أن…».
- إن كانت النصوص لا تتناول المسألة نفسها، أو كانت عن موضوع آخر، فاجعل found يساوي false واترك summary فارغاً.
أعد JSON فقط: {"found": true, "summary": "…", "used": [أرقام النصوص التي اعتمدت عليها]}
المسألة: $issue
النصوص:
$body''');
    if (j is! Map) return null;
    final found = j['found'] == true && '${j['summary'] ?? ''}'.trim().isNotEmpty;
    final used = <int>[
      for (final u in (j['used'] is List ? j['used'] as List : const []))
        if (u is num && u >= 1 && u <= texts.length) u.toInt() - 1,
    ];
    return AiSummary(found, '${j['summary'] ?? ''}'.trim(), used);
  }
}
