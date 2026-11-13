/// Approximate Hijri date (arithmetic calendar). It can differ by a day
/// from the moon-sighting calendar, so it is shown as a guide only.
class Hijri {
  final int year, month, day;
  const Hijri(this.year, this.month, this.day);

  static const months = [
    'محرم', 'صفر', 'ربيع الأول', 'ربيع الآخر', 'جمادى الأولى', 'جمادى الآخرة',
    'رجب', 'شعبان', 'رمضان', 'شوال', 'ذو القعدة', 'ذو الحجة',
  ];

  factory Hijri.from(DateTime d) {
    final a = (14 - d.month) ~/ 12;
    final y = d.year + 4800 - a;
    final m = d.month + 12 * a - 3;
    final jd = d.day + (153 * m + 2) ~/ 5 + 365 * y + y ~/ 4 - y ~/ 100 + y ~/ 400 - 32045;
    var l = jd - 1948440 + 10632;
    final n = (l - 1) ~/ 10631;
    l = l - 10631 * n + 354;
    final j = ((10985 - l) ~/ 5316) * ((50 * l) ~/ 17719) + (l ~/ 5670) * ((43 * l) ~/ 15238);
    l = l - ((30 - j) ~/ 15) * ((17719 * j) ~/ 50) - (j ~/ 16) * ((15238 * j) ~/ 43) + 29;
    final hm = (24 * l) ~/ 709;
    final hd = l - (709 * hm) ~/ 24;
    final hy = 30 * n + j - 30;
    return Hijri(hy, hm, hd);
  }

  /// From 'yyyy-mm-dd'; null when the text is not a date.
  static Hijri? parse(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? null : Hijri.from(d);
  }

  @override
  String toString() => '$day ${months[(month - 1).clamp(0, 11)]} $year هـ';

  /// A greeting on the first days of Ramadan and on the two Eids.
  String? get greeting {
    if (month == 9 && day <= 2) return 'بلّغنا الله وإياكم رمضان، وتقبّل منا ومنكم الصيام والقيام.';
    if (month == 10 && day <= 3) return 'تقبّل الله منا ومنكم، وكل عام وأنتم بخير. عيد فطر مبارك.';
    if (month == 12 && day >= 10 && day <= 13) return 'تقبّل الله منا ومنكم، وكل عام وأنتم بخير. عيد أضحى مبارك.';
    return null;
  }
}
