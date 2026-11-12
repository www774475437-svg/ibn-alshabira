import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../widgets/common.dart';

class FavoritesTab extends StatelessWidget {
  const FavoritesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('المحفوظات')),
      body: ListenableBuilder(
        listenable: repo,
        builder: (context, _) {
          final items = repo.favoriteFatwas;
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.bookmark_border,
              text: 'لم تحفظ شيئاً بعد.\nاضغط علامة الحفظ في أي فتوى لتجدها هنا.',
            );
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) => FatwaTile(fatwa: items[i]),
          );
        },
      ),
    );
  }
}
