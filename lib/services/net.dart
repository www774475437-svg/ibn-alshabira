import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'site_files.dart';

/// Is the internet there? A tiny file is asked for now and then; after two
/// misses in a row the app says «أنت بلا إنترنت», and hides it once a request
/// works again.
class Net extends ChangeNotifier {
  Net._();
  static final Net instance = Net._();

  bool offline = false;
  int _misses = 0;
  Timer? _t;

  void start() {
    // On the site the browser itself shows when the internet is off.
    if (kIsWeb || _t != null) return;
    check();
    _t = Timer.periodic(const Duration(seconds: 45), (_) => check());
  }

  Future<void> check() async {
    var ok = false;
    // Two different places, so one blocked site never looks like «no internet».
    for (final u in [
      'https://www.gstatic.com/generate_204',
      '${SiteFiles.base}friday.json?n=${DateTime.now().millisecondsSinceEpoch ~/ 30000}',
    ]) {
      try {
        final r = await http.get(Uri.parse(u)).timeout(const Duration(seconds: 8));
        if (r.statusCode < 500) {
          ok = true;
          break;
        }
      } catch (_) {}
    }
    _misses = ok ? 0 : _misses + 1;
    final now = _misses >= 2;
    if (now != offline) {
      offline = now;
      notifyListeners();
    }
  }
}
