import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../widgets/common.dart';

class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = Repository.instance.search(_query);
    return Scaffold(
      appBar: AppBar(title: const Text('البحث')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'اكتب المسألة… مثل: النمص، الوضوء، الربا',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _controller.clear();
                          _query = '';
                        }),
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          if (_query.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('عدد النتائج: ${results.length}',
                    style: const TextStyle(color: Colors.grey)),
              ),
            ),
          Expanded(
            child: _query.trim().isEmpty
                ? const EmptyState(
                    icon: Icons.manage_search,
                    text: 'ابحث في جميع فتاوى الشيخ ومقالاته.\nالبحث لا يتأثر بالتشكيل ولا بالهمزات.')
                : results.isEmpty
                    ? const EmptyState(icon: Icons.search_off, text: 'لا توجد نتائج لهذه الكلمة')
                    : ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (context, i) => FatwaTile(fatwa: results[i]),
                      ),
          ),
        ],
      ),
    );
  }
}
