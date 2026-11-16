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

  static Future<dynamic> _json(String prompt, {double temperature = 0, int seconds = 45}) async {
    if (!supported) return null;
    await _prepare();
    for (final name in _models) {
      try {
        final model = FirebaseAI.googleAI(appCheck: FirebaseAppCheck.instance).generativeModel(
          model: name,
          generationConfig: GenerationConfig(temperature: temperature, responseMimeType: 'application/json'),
        );
        final res = await model.generateContent([Content.text(prompt)]).timeout(Duration(seconds: seconds));
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

  /// Quiz questions for the sheikh to review (never published by themselves),
  /// from what Ibn Uthaymeen wrote. [cats]: the category names to choose from.
  /// Returns maps: text, choices, correct, explain, src, cat, level.
  static Future<List<Map<String, dynamic>>> quizQuestions({
    required int count,
    required List<String> cats,
    int level = 0,
    List<String> avoid = const [],
  }) async {
    final j = await _json('''
أنت تساعد شيخاً سلفياً في إعداد أسئلة اختيار من متعدد لطلاب العلم، يراجعها الشيخ قبل نشرها.
اكتب $count سؤالاً جديداً من مسائل العلم التي قرّرها الشيخ محمد بن صالح العثيمين رَحِمَهُ الله في كتبه وشروحه المشهورة
(مثل: شرح الأصول الثلاثة، القواعد المثلى، شرح العقيدة الواسطية، الشرح الممتع، شرح رياض الصالحين، مجموع فتاوى ورسائل العثيمين، فتاوى نور على الدرب).
الشروط:
- لا تكتب إلا مسألة واضحة مشهورة عنه أنت متأكد منها، واترك ما تشك فيه. لا تنسب إليه قولاً لم يقله.
- أربعة اختيارات، واحد صحيح فقط، والاختيارات الخاطئة معقولة غير سخيفة.
- شرح قصير من سطرين إلى أربعة يبيّن الصواب ودليله إن وُجد، بلغة الشيخ وأسلوبه.
- المصدر: اسم الكتاب فقط، ولا تكتب رقم صفحة أو جزء.
- الباب واحد من هذه فقط: ${cats.join('، ')}
- ${level == 0 ? 'نوّع الصعوبة' : 'الصعوبة كلها: ${level == 1 ? 'مبتدئ' : level == 2 ? 'متوسط' : 'متقدم'}'}، والصعوبة رقم: 1 مبتدئ، 2 متوسط، 3 متقدم.
- لا تكرر سؤالاً من هذه الأسئلة الموجودة ولا معناه:
${avoid.take(250).map((t) => '• $t').join('\n')}
أعد JSON فقط: [{"text": "...", "choices": ["...","...","...","..."], "correct": 0, "explain": "...", "src": "...", "cat": "...", "level": 1}]''', temperature: 0.7, seconds: 150);
    if (j is! List) return const [];
    return [
      for (final e in j)
        if (e is Map &&
            '${e['text'] ?? ''}'.trim().isNotEmpty &&
            e['choices'] is List &&
            (e['choices'] as List).length >= 2)
          {
            'text': '${e['text']}'.trim(),
            'choices': [for (final c in e['choices'] as List) '$c'.trim()],
            'correct': ((e['correct'] as num?)?.toInt() ?? 0).clamp(0, (e['choices'] as List).length - 1),
            'explain': '${e['explain'] ?? ''}'.trim(),
            'src': '${e['src'] ?? ''}'.trim(),
            'cat': '${e['cat'] ?? ''}'.trim(),
            'level': ((e['level'] as num?)?.toInt() ?? 1).clamp(1, 3),
          }
    ];
  }

  /// Puts channel posts in their chapters. [posts]: (id, text). [chapters]:
  /// (id, name). Returns id -> chapter id; posts it is not sure of get
  /// «mutafarriq». Nothing is deleted or rewritten.
  static Future<Map<String, String>> sortPosts(List<(String, String)> posts, List<(String, String)> chapters) async {
    final ids = {for (final c in chapters) c.$1};
    final j = await _json('''
أنت ترتّب منشورات شيخ في أبواب تطبيق. اقرأ كل منشور واختر بابه الصحيح من هذه الأبواب فقط:
${chapters.map((c) => '${c.$1}: ${c.$2}').join('\n')}
- اختر الباب بحسب موضوع المنشور الحقيقي، لا بحسب كلمة عابرة فيه.
- إن لم تكن متأكداً، أو كان المنشور في غير المسائل الشرعية (خبر، تهنئة، كلام عن بلد أو شخص)، فاختر mutafarriq.
أعد JSON فقط: {"رقم المنشور": "رقم الباب"}
المنشورات:
${posts.map((p) => '[${p.$1}] ${p.$2}').join('\n\n')}''', seconds: 120);
    if (j is! Map) return const {};
    return {
      for (final e in j.entries)
        if (ids.contains('${e.value}')) '${e.key}': '${e.value}',
    };
  }

  /// One line that sums up a long answer, from the sheikh's own words only.
  static Future<String?> summaryLine(String question, String answer) async {
    final j = await _json('''
اكتب خلاصة جواب الشيخ في سطر واحد قصير (لا يزيد على عشرين كلمة)، من كلامه هو فقط، دون زيادة حكم أو دليل من عندك.
إن لم يكن في الجواب حكم واضح يُلخَّص، فأعد {"line": ""}.
أعد JSON فقط: {"line": "..."}
السؤال: $question
الجواب: ${answer.length > 6000 ? answer.substring(0, 6000) : answer}''');
    if (j is! Map) return null;
    final l = '${j['line'] ?? ''}'.trim();
    return l.isEmpty ? null : l;
  }

  /// Splits a message into its questions. Does not answer anything.
  /// When the message cannot be understood at all, a short question back.
  static String? lastClarify;

  static Future<List<AiIssue>?> split(String question, {String previous = ''}) async {
    lastClarify = null;
    final context = previous.trim().isEmpty
        ? ''
        : '''
هذه رسالة متابعة في محادثة. السؤال السابق كان:
$previous
فاجعل كل مسألة كاملة مفهومة بنفسها (اذكر موضوع السؤال السابق فيها إن احتاجت إليه)، فإن سأل «ما الدليل؟» فالمسألة: «دليل» ثم موضوع السؤال السابق.
''';
    final j = await _json('''
أنت تقسّم رسالة المستفتي إلى مسائلها الشرعية فقط، ولا تجيب عن شيء ولا تذكر أي حكم.
$context
إن كانت الرسالة ناقصة لا يُفهم منها أي مسألة أبداً، فأعد فقط: {"clarify": "سؤال قصير مهذب تستوضح به من المستفتي"}
وإلا أعد JSON فقط بهذا الشكل: [{"title": "عنوان المسألة بكلمات قليلة", "queries": ["عبارة بحث", "عبارة بحث أخرى"]}]
- المسائل أربع على الأكثر، بترتيب ورودها في الرسالة.
- كل عبارة بحث من كلمتين إلى أربع كلمات، بألفاظ الفقهاء التي ترد في كتب الفتاوى، مثل: «قتل النمل»، «رفع الصوت على الوالدين»، «شروط التوبة».
- لكل مسألة عبارتان أو ثلاث مختلفة الألفاظ.
الرسالة:
$question''');
    if (j is Map && '${j['clarify'] ?? ''}'.trim().isNotEmpty) {
      lastClarify = '${j['clarify']}'.trim();
      return null;
    }
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

  /// Given texts of several scholars, picks the ONE scholar whose words are
  /// closest to the question and writes the short ruling from his texts alone.
  /// [groups] holds (scholar name, his texts). Returns the index of the group
  /// and, in [AiSummary.used], which of that scholar's texts were relied on.
  static Future<(int, AiSummary)?> choose(String issue, List<(String, List<String>)> groups) async {
    final body = StringBuffer();
    final where = <(int, int)>[]; // text number -> (group, index inside it)
    for (var g = 0; g < groups.length; g++) {
      for (var i = 0; i < groups[g].$2.length; i++) {
        final t = groups[g].$2[i];
        where.add((g, i));
        body.writeln('[${where.length}] (الشيخ ${groups[g].$1}) ${t.length > 1300 ? t.substring(0, 1300) : t}');
      }
    }
    final names = [for (var g = 0; g < groups.length; g++) '${g + 1}: ${groups[g].$1}'].join('، ');
    final j = await _json('''
بين يديك نصوص منقولة حرفياً من كتب عدد من المشايخ، ومسألة يسأل عنها مستفتٍ.
اختر شيخاً واحداً فقط: الذي كلامه أقرب إلى المسألة نفسها وأوضح في جوابها.
ثم اكتب جواباً مختصراً (من سطرين إلى أربعة) يلخّص ما قاله هذا الشيخ وحده، من نصوصه وحدها.
قواعد لا تُخالَف:
- لا تذكر أي حكم أو دليل أو معلومة ليست في نصوص الشيخ المختار، ولا تخلط كلامه بكلام غيره، ولا تجتهد من عندك.
- انسب الكلام للشيخ بصيغة مثل: «ذكر الشيخ أن…».
- إن لم يتناول أي نص المسألة نفسها فاجعل found يساوي false.
أرقام المشايخ: $names
أعد JSON فقط: {"found": true, "scholar": رقم الشيخ المختار, "summary": "…", "used": [أرقام النصوص التي اعتمدت عليها من نصوصه]}
المسألة: $issue
النصوص:
$body''');
    if (j is! Map) return null;
    final g = j['scholar'] is num ? (j['scholar'] as num).toInt() - 1 : -1;
    final found = j['found'] == true && g >= 0 && g < groups.length && '${j['summary'] ?? ''}'.trim().isNotEmpty;
    if (!found) return (-1, AiSummary(false, '', const []));
    final used = <int>[
      for (final u in (j['used'] is List ? j['used'] as List : const []))
        if (u is num && u >= 1 && u <= where.length && where[u.toInt() - 1].$1 == g) where[u.toInt() - 1].$2,
    ];
    return (g, AiSummary(true, '${j['summary']}'.trim(), used));
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
