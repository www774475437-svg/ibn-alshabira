import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Files the server makes four times a day (quiz, counts, usage). Reading them
/// costs nothing in Firestore. The last copy is kept on the phone, so they
/// work offline too.
class SiteFiles {
  static const base = 'https://raw.githubusercontent.com/${AppConfig.owner}/${AppConfig.repo}/media/';
  static final Map<String, Map<String, dynamic>> _mem = {};

  /// [fresh]: always ask the site (otherwise once per app session).
  static Future<Map<String, dynamic>?> get(String name, {bool fresh = false}) async {
    if (!fresh && _mem[name] != null) return _mem[name];
    final p = await SharedPreferences.getInstance();
    try {
      final r = await http
          .get(Uri.parse('$base$name?t=${DateTime.now().millisecondsSinceEpoch ~/ 600000}'))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 200) {
        final m = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        _mem[name] = m;
        await p.setString('site_$name', utf8.decode(r.bodyBytes));
        return m;
      }
    } catch (_) {}
    try {
      final s = p.getString('site_$name');
      if (s != null) return _mem[name] = jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }
}
