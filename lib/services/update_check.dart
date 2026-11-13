import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../config.dart';

/// Returns true when GitHub has a newer APK build than this one.
Future<bool> isUpdateAvailable() async {
  if (kIsWeb || AppConfig.buildNumber == 0) return false;
  try {
    final res = await http
        .get(Uri.parse(AppConfig.latestReleaseApi))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return false;
    final tag = (jsonDecode(res.body) as Map<String, dynamic>)['tag_name'] as String? ?? '';
    final latest = int.tryParse(tag.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    return latest > AppConfig.buildNumber;
  } catch (_) {
    return false;
  }
}

/// When the newer build was published (null when there is no update).
Future<DateTime?> updatePublishedAt() async {
  if (kIsWeb || AppConfig.buildNumber == 0) return null;
  try {
    final res = await http
        .get(Uri.parse(AppConfig.latestReleaseApi))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = j['tag_name'] as String? ?? '';
    final latest = int.tryParse(tag.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (latest <= AppConfig.buildNumber) return null;
    return DateTime.tryParse('${j['published_at'] ?? ''}')?.toLocal() ?? DateTime.now();
  } catch (_) {
    return null;
  }
}

/// «قبل ساعتين · 13/11/2026 الساعة 3:40 ص»
String updateTimeText(DateTime t) {
  final d = DateTime.now().difference(t);
  String ago;
  String n(int v, String one, String two, String few, String many) =>
      v == 1 ? one : v == 2 ? two : (v <= 10 ? '$v $few' : '$v $many');
  if (d.inMinutes < 2) {
    ago = 'الآن';
  } else if (d.inMinutes < 60) {
    ago = 'قبل ${n(d.inMinutes, 'دقيقة', 'دقيقتين', 'دقائق', 'دقيقة')}';
  } else if (d.inHours < 24) {
    ago = 'قبل ${n(d.inHours, 'ساعة', 'ساعتين', 'ساعات', 'ساعة')}';
  } else {
    ago = 'قبل ${n(d.inDays, 'يوم', 'يومين', 'أيام', 'يوماً')}';
  }
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$ago · ${t.day}/${t.month}/${t.year} الساعة $h:$m ${t.hour < 12 ? 'ص' : 'م'}';
}
