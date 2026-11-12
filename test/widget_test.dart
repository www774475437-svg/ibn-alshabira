import 'package:flutter_test/flutter_test.dart';
import 'package:ibn_alshabira/data/repository.dart';

void main() {
  test('Arabic normalization ignores tashkeel and hamza forms', () {
    expect(normalizeArabic('الصَّلاةُ'), normalizeArabic('الصلاه'));
    expect(normalizeArabic('إيمان'), normalizeArabic('ايمان'));
  });
}
