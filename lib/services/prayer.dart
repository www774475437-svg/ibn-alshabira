import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/hijri.dart';

/// Prayer times and the qibla, worked out on the phone itself (no internet,
/// no Firestore). The place comes from the phone's location — asked only
/// when the reader opens the prayer page — or from a city he picks.
/// The place never leaves the phone.
class Prayer extends ChangeNotifier {
  Prayer._();
  static final instance = Prayer._();

  static const names = ['الفجر', 'الشروق', 'الظهر', 'العصر', 'المغرب', 'العشاء'];

  /// Calculation methods: (name, fajr angle, isha angle or minutes after maghrib).
  static const methods = <String, (String, double, double, bool)>{
    'mwl': ('رابطة العالم الإسلامي', 18, 17, false),
    'umm': ('أم القرى', 18.5, 90, true),
    'egypt': ('الهيئة المصرية', 19.5, 17.5, false),
    'isna': ('أمريكا الشمالية', 15, 15, false),
    'karachi': ('كراتشي', 18, 18, false),
  };

  /// A few cities to pick by hand: (name, lat, lng).
  static const cities = <(String, double, double)>[
    ('صنعاء', 15.3694, 44.1910),
    ('عدن', 12.7855, 45.0187),
    ('تعز', 13.5795, 44.0209),
    ('إب', 13.9667, 44.1833),
    ('الحديدة', 14.7978, 42.9545),
    ('المكلا', 14.5425, 49.1242),
    ('ذمار', 14.5427, 44.4051),
    ('مأرب', 15.4543, 45.3263),
    ('صعدة', 16.9402, 43.7639),
    ('مكة المكرمة', 21.4225, 39.8262),
    ('المدينة المنورة', 24.4672, 39.6111),
    ('الرياض', 24.7136, 46.6753),
    ('جدة', 21.5433, 39.1728),
    ('الدمام', 26.4207, 50.0888),
    ('أبها', 18.2164, 42.5053),
    ('جازان', 16.8892, 42.5511),
    ('مسقط', 23.5880, 58.3829),
    ('الدوحة', 25.2854, 51.5310),
    ('دبي', 25.2048, 55.2708),
    ('أبوظبي', 24.4539, 54.3773),
    ('الكويت', 29.3759, 47.9774),
    ('المنامة', 26.2285, 50.5860),
    ('عمّان', 31.9539, 35.9106),
    ('القاهرة', 30.0444, 31.2357),
    ('الإسكندرية', 31.2001, 29.9187),
    ('الخرطوم', 15.5007, 32.5599),
    ('بغداد', 33.3152, 44.3661),
    ('دمشق', 33.5138, 36.2765),
    ('بيروت', 33.8938, 35.5018),
    ('القدس', 31.7683, 35.2137),
    ('طرابلس', 32.8872, 13.1913),
    ('تونس', 36.8065, 10.1815),
    ('الجزائر', 36.7538, 3.0588),
    ('الرباط', 34.0209, -6.8416),
    ('نواكشوط', 18.0735, -15.9582),
    ('مقديشو', 2.0469, 45.3182),
    ('جيبوتي', 11.5721, 43.1456),
    ('إسطنبول', 41.0082, 28.9784),
    ('كوالالمبور', 3.1390, 101.6869),
    ('جاكرتا', -6.2088, 106.8456),
    ('لندن', 51.5074, -0.1278),
    ('برمنغهام', 52.4862, -1.8904),
    ('باريس', 48.8566, 2.3522),
    ('برلين', 52.5200, 13.4050),
    ('أمستردام', 52.3676, 4.9041),
    ('ستوكهولم', 59.3293, 18.0686),
    ('ديترويت', 42.3314, -83.0458),
    ('هامترامك', 42.3928, -83.0496),
    ('ديربورن', 42.3223, -83.1763),
    ('نيويورك', 40.7128, -74.0060),
    ('شيكاغو', 41.8781, -87.6298),
    ('لوس أنجلوس', 34.0522, -118.2437),
    ('هيوستن', 29.7604, -95.3698),
    ('تورونتو', 43.6532, -79.3832),
    ('سيدني', -33.8688, 151.2093),
  ];

  double? lat, lng;
  String place = '';
  String method = 'mwl';
  bool hanafi = false;
  bool loaded = false;

  /// The reader's own minutes added to (or taken from) each of the six times,
  /// for towns whose real times differ from the calculated calendar.
  List<int> offsets = List.filled(6, 0);
  bool get hasOffsets => offsets.any((m) => m != 0);

  bool get hasPlace => lat != null && lng != null;

  Future<void> load() async {
    if (loaded) return;
    final p = await SharedPreferences.getInstance();
    lat = p.getDouble('prLat');
    lng = p.getDouble('prLng');
    place = p.getString('prPlace') ?? '';
    method = p.getString('prMethod') ?? 'mwl';
    hanafi = p.getBool('prHanafi') ?? false;
    final o = (p.getString('prOffsets') ?? '').split(',').map((e) => int.tryParse(e) ?? 0).toList();
    offsets = [for (var i = 0; i < 6; i++) i < o.length ? o[i].clamp(-60, 60) : 0];
    loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    if (lat != null) await p.setDouble('prLat', lat!);
    if (lng != null) await p.setDouble('prLng', lng!);
    await p.setString('prPlace', place);
    await p.setString('prMethod', method);
    await p.setBool('prHanafi', hanafi);
    await p.setString('prOffsets', offsets.join(','));
    await pushWidget();
    notifyListeners();
  }

  Future<void> setCity((String, double, double) c) async {
    place = c.$1;
    lat = c.$2;
    lng = c.$3;
    final p = await SharedPreferences.getInstance();
    await p.setBool('prByGps', false);
    await _save();
  }

  /// Changes one prayer's minutes (index into [names]); [i] = -1 resets all.
  Future<void> setOffset(int i, int minutes) async {
    if (i < 0) {
      offsets = List.filled(6, 0);
    } else {
      offsets[i] = minutes.clamp(-60, 60);
    }
    await _save();
  }

  Future<void> setMethod(String m, {bool? asrHanafi}) async {
    method = m;
    if (asrHanafi != null) hanafi = asrHanafi;
    await _save();
  }

  /// Asks for the location (only from the prayer page). Returns a message
  /// when it could not: 'denied', 'blocked' (ask in phone settings), 'off'.
  Future<String?> locate({bool force = false}) async {
    try {
      final p = await SharedPreferences.getInstance();
      // Checked once a week; a move inside the same town changes nothing.
      final last = p.getInt('prGpsAt') ?? 0;
      if (!force && hasPlace && DateTime.now().millisecondsSinceEpoch - last < 7 * 86400000) return null;
      if (!await Geolocator.isLocationServiceEnabled()) return 'off';
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) return 'blocked';
      if (perm == LocationPermission.denied) return 'denied';
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 20)));
      await p.setInt('prGpsAt', DateTime.now().millisecondsSinceEpoch);
      await p.setBool('prByGps', true);
      final moved = !hasPlace || _km(lat!, lng!, pos.latitude, pos.longitude) > 30;
      if (moved) {
        lat = pos.latitude;
        lng = pos.longitude;
        place = _nearestName(lat!, lng!);
        await _save();
      }
      return null;
    } catch (_) {
      return 'denied';
    }
  }

  Future<void> openSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (_) {}
  }

  static double _km(double a1, double o1, double a2, double o2) {
    const r = 6371.0;
    final dLat = _rad(a2 - a1), dLng = _rad(o2 - o1);
    final h = math.pow(math.sin(dLat / 2), 2) + math.cos(_rad(a1)) * math.cos(_rad(a2)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  /// The nearest known city, if close; otherwise «موقعك الحالي».
  static String _nearestName(double la, double lo) {
    var best = '', d = 1e9;
    for (final c in cities) {
      final k = _km(la, lo, c.$2, c.$3);
      if (k < d) (best, d) = (c.$1, k);
    }
    return d < 60 ? best : 'موقعك الحالي';
  }

  // ------------------------------------------------------------ the times
  /// The six times of [day] (local), in the phone's own time.
  List<DateTime>? timesOf(DateTime day) {
    if (!hasPlace) return null;
    final m = methods[method] ?? methods['mwl']!;
    final l = compute(day, lat!, lng!, fajrAngle: m.$2, isha: m.$3, ishaMinutes: m.$4, asrFactor: hanafi ? 2 : 1);
    return [for (var i = 0; i < 6; i++) l[i].add(Duration(minutes: offsets[i]))];
  }

  /// The next prayer from now (index into [names], skipping the sunrise
  /// unless asked) and its time.
  (int, DateTime)? next({DateTime? now}) {
    final t = now ?? DateTime.now();
    for (var d = 0; d < 2; d++) {
      final day = DateTime(t.year, t.month, t.day).add(Duration(days: d));
      final l = timesOf(day);
      if (l == null) return null;
      for (var i = 0; i < 6; i++) {
        if (i == 1) continue;
        if (l[i].isAfter(t)) return (i, l[i]);
      }
    }
    return null;
  }

  static double _rad(double d) => d * math.pi / 180;
  static double _deg(double r) => r * 180 / math.pi;
  static double _sin(double d) => math.sin(_rad(d));
  static double _cos(double d) => math.cos(_rad(d));
  static double _tan(double d) => math.tan(_rad(d));
  static double _asin(double x) => _deg(math.asin(x.clamp(-1.0, 1.0)));
  static double _acos(double x) => _deg(math.acos(x.clamp(-1.0, 1.0)));
  static double _atan2(double y, double x) => _deg(math.atan2(y, x));
  static double _acot(double x) => _deg(math.atan(1 / x));
  static double _fix(double a, double b) {
    a = a - b * (a / b).floor();
    return a < 0 ? a + b : a;
  }

  static double _julian(int y, int m, int d) {
    if (m <= 2) {
      y -= 1;
      m += 12;
    }
    final a = (y / 100).floor();
    final b = 2 - a + (a / 4).floor();
    return (365.25 * (y + 4716)).floor() + (30.6001 * (m + 1)).floor() + d + b - 1524.5;
  }

  /// (declination, equation of time) for a julian day.
  static (double, double) _sun(double jd) {
    final dd = jd - 2451545.0;
    final g = _fix(357.529 + 0.98560028 * dd, 360);
    final q = _fix(280.459 + 0.98564736 * dd, 360);
    final l = _fix(q + 1.915 * _sin(g) + 0.020 * _sin(2 * g), 360);
    final e = 23.439 - 0.00000036 * dd;
    final ra = _fix(_atan2(_cos(e) * _sin(l), _cos(l)) / 15, 24);
    return (_asin(_sin(e) * _sin(l)), q / 15 - ra);
  }

  /// Times (well-known «PrayTimes» method), computed in UTC and returned in
  /// the phone's local time.
  static List<DateTime> compute(DateTime day, double lat, double lng,
      {double fajrAngle = 18, double isha = 17, bool ishaMinutes = false, int asrFactor = 1}) {
    final jd = _julian(day.year, day.month, day.day) - lng / (15 * 24);
    double noon(double t) => _fix(12 - _sun(jd + t / 24).$2, 24);
    double angleTime(double angle, double t, bool before) {
      final decl = _sun(jd + t / 24).$1;
      final n = noon(t);
      final x = _acos((-_sin(angle) - _sin(decl) * _sin(lat)) / (_cos(decl) * _cos(lat))) / 15;
      return n + (before ? -x : x);
    }

    double asr(double t) {
      final decl = _sun(jd + t / 24).$1;
      final angle = -_acot(asrFactor + _tan((lat - decl).abs()));
      return angleTime(angle, t, false);
    }

    // Two passes for accuracy.
    var t = [5.0, 6.0, 12.0, 13.0, 18.0, 18.0, 18.0];
    for (var pass = 0; pass < 2; pass++) {
      t = [
        angleTime(fajrAngle, t[0], true),
        angleTime(0.833, t[1], true),
        noon(t[2]),
        asr(t[3]),
        angleTime(0.833, t[4], false),
        ishaMinutes ? 0 : angleTime(isha, t[5], false),
        0,
      ];
    }
    if (ishaMinutes) t[5] = t[4] + isha / 60;
    final base = DateTime.utc(day.year, day.month, day.day);
    DateTime at(double h, [int addMin = 0]) {
      final utcHours = h - lng / 15;
      return base.add(Duration(seconds: (utcHours * 3600).round() + addMin * 60)).toLocal();
    }

    return [at(t[0]), at(t[1]), at(t[2], 1), at(t[3]), at(t[4], 1), at(t[5])];
  }

  /// The qibla's direction from north, in degrees.
  double? get qibla {
    if (!hasPlace) return null;
    const kLat = 21.4225, kLng = 39.8262;
    final dl = _rad(kLng - lng!);
    final y = math.sin(dl);
    final x = math.cos(_rad(lat!)) * math.tan(_rad(kLat)) - math.sin(_rad(lat!)) * math.cos(dl);
    return _fix(_deg(math.atan2(y, x)), 360);
  }

  // ------------------------------------------------- the home-screen widget
  static const _ch = MethodChannel('ibn_alshabira/icon');

  /// Gives the Android widget the next three days of times (it picks the next
  /// prayer by itself). Nothing happens on the website.
  Future<void> pushWidget() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android || !hasPlace) return;
    final now = DateTime.now();
    final all = <int>[];
    for (var d = 0; d < 3; d++) {
      final l = timesOf(DateTime(now.year, now.month, now.day).add(Duration(days: d)));
      if (l != null) all.addAll(l.map((e) => e.millisecondsSinceEpoch));
    }
    final h = Hijri.from(now);
    try {
      await _ch.invokeMethod('widget', {
        'times': all.join(','),
        'place': place,
        'hijri': '${h.day} ${Hijri.months[(h.month - 1).clamp(0, 11)]}',
      });
    } catch (_) {}
  }
}
