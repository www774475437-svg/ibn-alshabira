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
