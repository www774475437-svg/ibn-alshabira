import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

class BooksTab extends StatelessWidget {
  const BooksTab({super.key});

  @override
  Widget build(BuildContext context) {
    final books = Repository.instance.books;
    return Scaffold(
      appBar: AppBar(title: const Text('كتب الشيخ')),
      body: books.isEmpty
          ? const EmptyState(
              icon: Icons.menu_book_outlined,
              text: 'ستُضاف كتب الشيخ ورسائله هنا قريباً بإذن الله.')
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: books.length,
              itemBuilder: (context, i) {
                final b = books[i];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  child: ListTile(
                    leading: const Icon(Icons.menu_book, color: kGold, size: 34),
                    title: Text(b.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: b.description.isEmpty ? null : Text(b.description),
                    trailing: b.url.isEmpty ? null : const Icon(Icons.download_outlined),
                    onTap: b.url.isEmpty ? null : () => openUrl(context, b.url),
                  ),
                );
              },
            ),
    );
  }
}
