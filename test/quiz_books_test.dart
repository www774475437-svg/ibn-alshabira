import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibn_alshabira/services/quiz.dart';

void main() {
  test('book questions read and are live', () {
    final m = jsonDecode(File('assets/data/quiz_books.json').readAsStringSync()) as Map<String, dynamic>;
    final qs = [
      for (final q in (m['qs'] as List))
        QuizQ.fromMap('${(q as Map)['id']}', {...Map<String, dynamic>.from(q), 'cat': 'x'})
    ];
    final live = qs.where((q) => q.isLive).length;
    final forChallenge = qs.where((q) => q.isLive && q.type != QuizType.order && !q.multi).length;
    // ignore: avoid_print
    print('total ${qs.length} live $live challenge $forChallenge');
    expect(qs.length, 700);
    expect(live, greaterThan(600));
  });
}
