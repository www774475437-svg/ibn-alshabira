class Chapter {
  final String id;
  final String name;
  final String icon;

  Chapter({required this.id, required this.name, required this.icon});

  factory Chapter.fromJson(Map<String, dynamic> j) => Chapter(
        id: j['id'] as String,
        name: j['name'] as String,
        icon: (j['icon'] ?? '') as String,
      );
}

/// A fatwa, article or دعوية letter.
class Fatwa {
  final String id;
  final String chapter;
  final String type; // fatwa | article | letter
  final String title;
  final String question;
  final String answer;
  final List<String> tags;
  final String date;
  final String source;

  /// Pre-computed normalized text for fast search.
  late final String searchText;

  Fatwa({
    required this.id,
    required this.chapter,
    required this.type,
    required this.title,
    required this.question,
    required this.answer,
    required this.tags,
    required this.date,
    required this.source,
  });

  factory Fatwa.fromJson(Map<String, dynamic> j) => Fatwa(
        id: '${j['id']}',
        chapter: (j['chapter'] ?? 'mutafarriq') as String,
        type: (j['type'] ?? 'fatwa') as String,
        title: (j['title'] ?? '') as String,
        question: (j['question'] ?? '') as String,
        answer: (j['answer'] ?? '') as String,
        tags: ((j['tags'] ?? []) as List).map((e) => '$e').toList(),
        date: (j['date'] ?? '') as String,
        source: (j['source'] ?? '') as String,
      );

  String get typeLabel {
    switch (type) {
      case 'article':
        return 'مقال';
      case 'letter':
        return 'رسالة دعوية';
      default:
        return 'فتوى';
    }
  }

  String get shareText {
    final b = StringBuffer('📜 $title\n\n');
    if (question.isNotEmpty) b.write('❓ السؤال:\n$question\n\n');
    b.write(question.isNotEmpty ? '✅ الجواب:\n$answer\n\n' : '$answer\n\n');
    b.write('— الشيخ قائد بن غانم الشابرة حفظه الله\n');
    b.write('من تطبيق «ابن الشابرة»');
    return b.toString();
  }
}

class Book {
  final String id;
  final String title;
  final String description;
  final String url;

  Book({required this.id, required this.title, required this.description, required this.url});

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        id: '${j['id']}',
        title: (j['title'] ?? '') as String,
        description: (j['description'] ?? '') as String,
        url: (j['url'] ?? '') as String,
      );
}

class SocialLink {
  final String platform;
  final String name;
  final String url;

  SocialLink({required this.platform, required this.name, required this.url});

  factory SocialLink.fromJson(Map<String, dynamic> j) => SocialLink(
        platform: (j['platform'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        url: (j['url'] ?? '') as String,
      );
}
