import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/hijri.dart';
import '../services/cloud.dart';
import '../services/members.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'admin_extra.dart' show AskerChatScreen, askerLabel;

String _date(DateTime? d) {
  if (d == null) return '—';
  final h = Hijri.from(d);
  return '${h.day} ${Hijri.months[(h.month - 1).clamp(0, 11)]} ${h.year}هـ · ${d.day}/${d.month}/${d.year}';
}

String _ago(DateTime? d) {
  if (d == null) return '—';
  final m = DateTime.now().difference(d).inMinutes;
  if (m < 60) return 'قبل ${m < 1 ? 1 : m} دقيقة';
  if (m < 60 * 24) return 'قبل ${m ~/ 60} ساعة';
  return 'قبل ${m ~/ (60 * 24)} يوم';
}

/// «المسجّلون»: everyone who registered, numbered from the first (1),
/// with how many joined today, a search by number or name, and each one's
/// page. Read at most once in six hours; kept on the phone between.
class MembersTab extends StatefulWidget {
  const MembersTab({super.key});

  @override
  State<MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<MembersTab> {
  final _q = TextEditingController();
  bool _newest = false;

  @override
  void initState() {
    super.initState();
    Members.instance.load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Members.instance,
        builder: (context, _) {
          final ms = Members.instance;
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final q = _q.text.trim();
          var l = ms.list.where((m) {
            if (q.isEmpty) return true;
            final n = int.tryParse(q.replaceAll(RegExp(r'[^0-9٠-٩]'), '').split('').map((c) {
              final i = '٠١٢٣٤٥٦٧٨٩'.indexOf(c);
              return i >= 0 ? '$i' : c;
            }).join());
            if (n != null) return m.seq == n || m.n('no') == n;
            return m.name.contains(q);
          }).toList();
          if (_newest) l = l.reversed.toList();
          final activeToday = ms.list.where((m) => m.seen != null && !m.seen!.isBefore(today)).length;
          return RefreshIndicator(
            onRefresh: () => ms.load(force: true),
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 40),
              itemCount: l.length + 1,
              itemBuilder: (context, i) {
                if (i > 0) return _MemberTile(m: l[i - 1]);
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Row(children: [
                      _Stat('المسجّلون', '${ms.list.length}', Icons.groups, const Color(0xFF0E3B44)),
                      const SizedBox(width: 8),
                      _Stat('جدد اليوم', '${ms.joinedSince(today)}', Icons.person_add, const Color(0xFF2E7D32)),
                      const SizedBox(width: 8),
                      _Stat('هذا الأسبوع', '${ms.joinedSince(today.subtract(const Duration(days: 6)))}', Icons.date_range,
                          const Color(0xFF8E6B1E)),
                      const SizedBox(width: 8),
                      _Stat('نشطون اليوم', '$activeToday', Icons.bolt, const Color(0xFF7A1F1F)),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: TextField(
                      controller: _q,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'ابحث برقم التسجيل أو رقم السائل أو الاسم',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                    child: Row(children: [
                      ChoiceChip(label: const Text('من الأول'), selected: !_newest, onSelected: (_) => setState(() => _newest = false)),
                      const SizedBox(width: 6),
                      ChoiceChip(label: const Text('الأحدث'), selected: _newest, onSelected: (_) => setState(() => _newest = true)),
                      const Spacer(),
                      if (ms.loading)
                        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        IconButton(
                          tooltip: 'تحديث الآن',
                          icon: const Icon(Icons.refresh),
                          onPressed: () => ms.load(force: true),
                        ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      ms.error ??
                          (ms.at == null
                              ? 'جارٍ جلب القائمة…'
                              : 'آخر تحديث ${_ago(ms.at)} — يجهّزها الخادم كل 6 ساعات، وفتحها قراءة أو قراءتان فقط.'),
                      style: TextStyle(color: ms.error != null ? Colors.red : Colors.grey, fontSize: 12),
                    ),
                  ),
                  if (ms.list.isEmpty && !ms.loading)
                    const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('لا أحد بعد'))),
                  const Divider(),
                ]);
              },
            ),
          );
        },
      );
}

class _Stat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _Stat(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            Icon(icon, color: kGold, size: 20),
            Text(value,
                style: const TextStyle(fontFamily: 'Tajawal', color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ]),
        ),
      );
}

class _MemberTile extends StatelessWidget {
  final Member m;
  const _MemberTile({required this.m});

  @override
  Widget build(BuildContext context) {
    final bits = [
      if (m.n('days') > 0) '🔥 ${m.n('days')} يوم',
      if (m.n('reads') > 0) '📖 ${m.n('reads')}',
      if (m.n('chWins') > 0) '🏆 ${m.n('chWins')}',
      if (m.badges.isNotEmpty) '🎖 ${m.badges.length}',
    ];
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: m.seq <= 3 ? kGold : const Color(0xFF0E3B44),
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Text('${m.seq}', style: TextStyle(color: m.seq <= 3 ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
      title: Text(m.name.isEmpty ? 'بلا اسم' : m.name,
          style: TextStyle(fontWeight: FontWeight.bold, color: m.name.isEmpty ? Colors.grey : null)),
      subtitle: Text(
        [
          if (m.joined != null) 'سجّل ${_ago(m.joined)}',
          if (bits.isNotEmpty) bits.join('  '),
          if (!m.hasCard) 'لم يفتح التطبيق بعد التحديث',
        ].join('\n'),
        style: const TextStyle(fontSize: 12, height: 1.5),
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'راسله',
          icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF2E7D32)),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AskerChatScreen(uid: m.uid, label: askerLabel({'uid': m.uid, 'name': m.name})))),
        ),
        const Icon(Icons.chevron_left),
      ]),
      onTap: () => openMember(context, m.uid),
    );
  }
}

void openMember(BuildContext context, String uid) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MemberScreen(uid: uid)));

/// One registered reader's page: number, dates and everything he did.
class MemberScreen extends StatefulWidget {
  final String uid;
  const MemberScreen({super.key, required this.uid});

  @override
  State<MemberScreen> createState() => _MemberScreenState();
}

class _MemberScreenState extends State<MemberScreen> {
  Member? _m;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _get();
  }

  Future<void> _get() async {
    await Members.instance.load();
    var m = Members.instance.byUid(widget.uid);
    if (m == null || !m.hasCard) {
      // Not in the kept list yet (joined since): one read for him alone.
      try {
        final d = await FirebaseFirestore.instance.doc('users/${widget.uid}').get();
        final card = Map<String, dynamic>.from(d.data()?['card'] as Map? ?? const {});
        final j = card['joined'] is num ? DateTime.fromMillisecondsSinceEpoch((card['joined'] as num).toInt()) : null;
        final s = card['seen'] is num ? DateTime.fromMillisecondsSinceEpoch((card['seen'] as num).toInt()) : null;
        m = Member(widget.uid, m?.seq ?? 0, j ?? m?.joined, s, card);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _m = m;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    return Scaffold(
      appBar: AppBar(title: const Text('ملف المشارك')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : m == null
              ? const EmptyState(icon: Icons.person_off_outlined, text: 'لم يُعثر على هذا الشخص')
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                          begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF0E3B44), Color(0xFF1F5E3B)]),
                    ),
                    child: Column(children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: kGold,
                        child: Text(m.seq > 0 ? '${m.seq}' : '؟',
                            style: const TextStyle(fontFamily: 'Tajawal', fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black)),
                      ),
                      const SizedBox(height: 8),
                      Text(m.name.isEmpty ? 'بلا اسم' : m.name,
                          style: const TextStyle(fontFamily: 'Tajawal', color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      Text(m.seq > 0 ? 'المسجّل رقم ${m.seq}' : 'سجّل حديثاً', style: const TextStyle(color: kGold)),
                      if (m.n('no') > 0)
                        Text('رقمه عند الشيخ: ${m.n('no')}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 6),
                      Text('سجّل: ${_date(m.joined)}', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                      Text('آخر ظهور: ${_ago(m.seen)}${m.card['web'] == true ? ' · من الموقع' : m.hasCard ? ' · من التطبيق' : ''}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                    ]),
                  ),
                  if (!m.hasCard)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('لم تصل بياناته بعد: تصل حين يفتح النسخة الجديدة من التطبيق أو الموقع.',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                    )
                  else ...[
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.15,
                      children: [
                        _Box('أيام متتالية', m.n('days'), Icons.local_fire_department, const Color(0xFFB0602A)),
                        _Box('أجوبة قرأها', m.n('reads'), Icons.menu_book, const Color(0xFF0E3B44)),
                        _Box('قرأ هذا الشهر', m.n('month'), Icons.calendar_month, const Color(0xFF2E6B73)),
                        _Box('أسئلة صحيحة', m.n('right'), Icons.check_circle, const Color(0xFF2E7D32)),
                        _Box('أسئلة خاطئة', m.n('wrong'), Icons.cancel, const Color(0xFFC62828)),
                        _Box('نقاطه', m.n('pts'), Icons.stars, const Color(0xFF8E6B1E)),
                        _Box('تحديات لعبها', m.n('chPlayed'), Icons.bolt, const Color(0xFF7A1F1F)),
                        _Box('فاز فيها', m.n('chWins'), Icons.emoji_events, const Color(0xFF9C7A1E)),
                        _Box('تسجيلات سمعها', m.n('listens'), Icons.headphones, const Color(0xFF3B4A8C)),
                        _Box('صفحات حفظها', m.n('hifz'), Icons.auto_stories, const Color(0xFF145A32)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text('الأوسمة (${m.badges.length})',
                        style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 17)),
                    const SizedBox(height: 6),
                    if (m.badges.isEmpty)
                      const Text('لا أوسمة بعد', style: TextStyle(color: Colors.grey))
                    else
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final b in m.badges)
                          Chip(avatar: const Icon(Icons.military_tech, color: kGold, size: 18), label: Text(b)),
                      ]),
                    const SizedBox(height: 10),
                    const Text('تصل بياناته من جهازه مرة كل 6 ساعات.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ]),
    );
  }
}

class _Box extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  const _Box(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            color: color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: .4))),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 22),
          Text('$value', style: TextStyle(fontFamily: 'Tajawal', fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5)),
        ]),
      );
}

/// Keeps Cloud imported for the staff check used by callers.
bool get canSeeMembers => Cloud.instance.isAdmin;
