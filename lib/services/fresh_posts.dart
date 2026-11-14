import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../data/models.dart';
import '../data/repository.dart';

/// The site is rebuilt every day with the sheikh's newest channel posts.
/// The Android app picks those up here, so readers see them without
/// waiting for a new version of the app.
Future<void> loadFreshPosts() async {
  if (kIsWeb) return; // the site already carries the newest data
  final prefs = await SharedPreferences.getInstance();
  void apply(String body) {
    final list = jsonDecode(body) as List;
    Repository.instance.addFresh([for (final e in list) Fatwa.fromJson(e as Map<String, dynamic>)]);
  }

  // Show what was saved last time straight away, then refresh.
  final saved = prefs.getString('freshPosts');
  if (saved != null) {
    try {
      apply(saved);
    } catch (_) {}
  }
  try {
    final res = await http
        .get(Uri.parse('${AppConfig.siteUrl}assets/assets/data/latest.json'))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return;
    final body = utf8.decode(res.bodyBytes);
    apply(body);
    await prefs.setString('freshPosts', body);
  } catch (_) {}
  // The newest list of videos, so the section never goes empty.
  try {
    final res = await http
        .get(Uri.parse('${AppConfig.siteUrl}assets/assets/data/videos.json'))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode == 200) {
      final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
      Repository.instance
          .setFetchedVideos([for (final e in list) Video.fromJson(e as Map<String, dynamic>)]);
    }
  } catch (_) {}
}
