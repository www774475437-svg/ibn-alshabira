import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../data/models.dart';
import '../data/repository.dart';

/// Downloads and keeps the sheikh's books inside the app.
class BooksStore {
  static const _folderId = '19p5At8pu_DEPA6M50PF6N4j3HpoNUbD_';

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/books');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<File> _fileFor(Book b) async => File('${(await _dir()).path}/${b.id}.pdf');

  static Future<File?> cachedFile(Book b) async {
    final f = await _fileFor(b);
    return await f.exists() && await f.length() > 0 ? f : null;
  }

  /// Downloads the book (reporting progress 0..1, or -1 if size unknown).
  static Future<File> download(Book b, void Function(double) onProgress) async {
    final f = await _fileFor(b);
    final tmp = File('${f.path}.part');
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(b.downloadUrl)));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final total = res.contentLength ?? 0;
      var got = 0;
      final sink = tmp.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        onProgress(total > 0 ? got / total : -1);
      }
      await sink.close();
      // Must be a real PDF (not an error page)
      final head = await tmp.openRead(0, 4).first;
      if (String.fromCharCodes(head) != '%PDF') {
        await tmp.delete();
        throw Exception('not a pdf');
      }
      await tmp.rename(f.path);
      return f;
    } finally {
      client.close();
    }
  }

  static Future<void> delete(Book b) async {
    final f = await _fileFor(b);
    if (await f.exists()) await f.delete();
  }

  /// Re-reads the Drive folder so new books appear without an app update.
  static Future<void> refreshFromDrive() async {
    if (kIsWeb) return;
    try {
      final res = await http
          .get(Uri.parse('https://drive.google.com/embeddedfolderview?id=$_folderId'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return;
      final page = res.body;
      final books = <Book>[];
      for (final chunk in page.split('class="flip-entry"').skip(1)) {
        final id = RegExp(r'id="entry-([\w-]+)"').firstMatch(chunk)?.group(1);
        final name = RegExp(r'class="flip-entry-title">(.*?)</div>', dotAll: true).firstMatch(chunk)?.group(1);
        final href = RegExp(r'href="([^"]+)"').firstMatch(chunk)?.group(1) ?? '';
        if (id == null || name == null || href.contains('/folders/')) continue;
        books.add(Book(id: id, title: cleanBookTitle(_unescape(name)), folder: ''));
      }
      if (books.isNotEmpty) Repository.instance.setBooks(books);
    } catch (e) {
      debugPrint('Drive refresh failed: $e');
    }
  }

  static String _unescape(String s) => s
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();
}

/// Same cleaning as tool/fetch_drive_books.py.
String cleanBookTitle(String name) {
  var t = name.replaceAll(RegExp(r'\.(pdf|docx?|epub)$', caseSensitive: false), '').replaceAll('_', ' ');
  for (final p in [r'-\s*تنسيق[^-]*-?', r'طبعة\s+جديدة', r'(ال)?معتمدة?', r'(^|\s)جديد(?=\s|$)', r'(\s\d+)+$']) {
    t = t.replaceAll(RegExp(p), ' ');
  }
  return t.replaceAll(RegExp(r'\s+'), ' ').trim().replaceAll(RegExp(r'^[\s-]+|[\s-]+$'), '');
}
