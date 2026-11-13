import '../config.dart';

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
  String title;
  final String question;
  final String answer;
  final List<String> tags;
  final String date;
  final String source;

  /// Sub-chapter name inside the chapter ('' = none).
  final String sub;

  /// Link to a voice recording of the answer ('' = none).
  final String audio;

  /// Pre-computed normalized text for fast search.
  late String searchText;

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
    this.sub = '',
    this.audio = '',
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
        sub: '${j['sub'] ?? ''}',
        audio: '${j['audio'] ?? ''}',
      );

  String get typeLabel {
    switch (type) {
      case 'article':
        return 'مقال';
      case 'letter':
        return 'رسالة دعوية';
      default:
        return 'جواب';
    }
  }

  String get shareText {
    final b = StringBuffer('📜 $title\n\n');
    if (question.isNotEmpty) b.write('❓ السؤال:\n$question\n\n');
    b.write(question.isNotEmpty ? '✅ الجواب:\n$answer\n\n' : '$answer\n\n');
    b.write('— الشيخ قائد بن غانم الشابرة حفظه الله\n\n');
    b.write('🔗 رابط الجواب:\n${AppConfig.fatwaLink(id)}');
    return b.toString();
  }
}

class Book {
  final String id; // Google Drive file id
  final String title;
  final String folder;

  Book({required this.id, required this.title, required this.folder});

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        id: '${j['id']}',
        title: (j['title'] ?? '') as String,
        folder: (j['folder'] ?? '') as String,
      );

  /// Direct download (used inside the app; the link is never shown).
  String get downloadUrl =>
      'https://drive.usercontent.google.com/download?id=$id&export=download&confirm=t';

  /// On the website, books open in Google's viewer.
  String get previewUrl => 'https://drive.google.com/file/d/$id/view';
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

class Video {
  final String id; // YouTube video id
  final String title;
  final String published;

  Video({required this.id, required this.title, required this.published});

  factory Video.fromJson(Map<String, dynamic> j) => Video(
        id: '${j['id']}',
        title: (j['title'] ?? '') as String,
        published: (j['published'] ?? '') as String,
      );

  String get url => 'https://www.youtube.com/watch?v=$id';
  String get thumbnail => 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
}
