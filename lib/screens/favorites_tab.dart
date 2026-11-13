import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../widgets/common.dart';

/// Two lists: saved answers and «اقرأ لاحقاً».
class FavoritesTab extends StatelessWidget {
  const FavoritesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المحفوظات'),
          bottom: const TabBar(
            labelColor: Color(0xFFC9A54C),
            unselectedLabelColor: Colors.white70,
            indicatorColor: Color(0xFFC9A54C),
            tabs: [
              Tab(icon: Icon(Icons.bookmark), text: 'المحفوظات'),
              Tab(icon: Icon(Icons.watch_later), text: 'اقرأ لاحقاً'),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: repo,
          builder: (context, _) => TabBarView(
            children: [
              _List(
                items: repo.favoriteFatwas,
                empty: const EmptyState(
                  icon: Icons.bookmark_border,
                  text: 'لم تحفظ شيئاً بعد.\nاضغط علامة الحفظ في أي جواب لتجده هنا.',
                ),
              ),
              _List(
                items: repo.readLaterFatwas,
                empty: const EmptyState(
                  icon: Icons.watch_later_outlined,
                  text: 'القائمة فارغة.\nاضغط علامة الساعة في أي جواب لتقرأه لاحقاً.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  final List<Fatwa> items;
  final Widget empty;
  const _List({required this.items, required this.empty});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return empty;
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) => FatwaTile(fatwa: items[i]),
    );
  }
}
