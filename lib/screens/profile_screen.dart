import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../data/repository.dart';
import '../services/challenge.dart';
import '../services/cloud.dart';
import '../services/progress.dart';
import '../services/quiz.dart';
import '../services/site_files.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'quiz_screens.dart';

Future<void> openDashboard(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DashboardScreen()));

/// «لوحتي»: everything about the reader on one page — his number, points,
/// reading, questions, challenges, listening, memorizing and badges.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _search = TextEditingController();
  int _invited = 0;

  @override
  void initState() {
    super.initState();
    Quiz.instance.load();
    Challenges.instance.load();
    Progress.load().then((_) => mounted ? setState(() {}) : null);
    _loadInvites();
  }

  Future<void> _loadInvites() async {
    final u = Cloud.instance.user;
    if (u == null) return;
    final m = await SiteFiles.get('leaders.json');
    final n = ((m?['invites'] ?? {}) as Map)['${askerNo(u.uid)}'];
    if (mounted) setState(() => _invited = (n as num?)?.toInt() ?? 0);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([Quiz.instance, Challenges.instance, Cloud.instance, Repository.instance]),
        builder: (context, _) {
          final u = Cloud.instance.user;
          final quiz = Quiz.instance, ch = Challenges.instance;
          final no = u == null ? null : askerNo(u.uid);
          final badges = Progress.badges;
          final earned = badges.where((b) => b.$4).toList();
          return Scaffold(
            appBar: AppBar(title: const Text('لوحتي')),
            body: ListView(padding: const EdgeInsets.all(12), children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(colors: [Color(0xFF0E3B44), Color(0xFF1F5E3B)]),
                  border: Border.all(color: kGold),
                ),
                child: Column(children: [
                  Text(
                      u == null
                          ? 'زائر'
                          : quiz.showName && quiz.nick.trim().isNotEmpty
                              ? quiz.nick.trim()
                              : 'رقم $no',
                      style: const TextStyle(fontFamily: 'Tajawal', color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  if (no != null) Text('رقمك: $no', style: const TextStyle(color: kGold)),
                  const SizedBox(height: 10),
                  Text('${Progress.points}',
                      style: const TextStyle(fontFamily: 'Tajawal', color: kGold, fontSize: 42, fontWeight: FontWeight.bold)),
                  const Text('نقطة', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 6),
                  Text('${quiz.levelTitle} · ${earned.length} أوسمة', style: const TextStyle(color: Colors.white)),
                ]),
              ),
              const SizedBox(height: 10),
              if (u == null)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('سجّل الدخول من «المزيد» ليكون لك رقم وملف يراه أصحابك، وتُحفظ نقاطك في حسابك.',
                        style: TextStyle(height: 1.7)),
                  ),
                )
              else
                Card(
                  child: SwitchListTile(
                    title: const Text('أضف اسمي'),
                    subtitle: const Text('يظهر اسمك للناس في ملفك والمتصدّرين؛ وإن أطفأته يظهر رقمك فقط'),
                    value: quiz.showName,
                    onChanged: (v) => quiz.setProfile(showName: v),
                  ),
                ),
              const _Head('تفصيل نقاطي'),
              Card(
                child: Column(children: [
                  for (final p in Progress.parts)
                    ListTile(
                      dense: true,
                      title: Text(p.$1),
                      subtitle: Text('${p.$2}'),
                      trailing: Text('+${p.$3}', style: const TextStyle(fontWeight: FontWeight.bold, color: kGoldChip)),
                    ),
                ]),
              ),
              const _Head('الأسئلة والتحديات'),
              Card(
                child: Column(children: [
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.quiz_outlined),
                    title: Text('أصبت ${quiz.right} · أخطأت ${quiz.wrong}'),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuizProfileScreen())),
                  ),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.bolt),
                    title: Text('فزت في ${ch.wins} تحدّياً (${ch.winsDuel} فردي، ${ch.winsGroup} جماعي) من ${ch.played}'),
                  ),
                ]),
              ),
              const _Head('أوسمتي'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final b in badges)
                  Opacity(
                    opacity: b.$4 ? 1 : .35,
                    child: Chip(
                      avatar: Icon(b.$3, color: b.$4 ? kGold : Colors.grey, size: 20),
                      label: Text(b.$2, style: const TextStyle(fontSize: 12.5)),
                    ),
                  ),
              ]),
              if (u != null) ...[
                const _Head('دعوة الأصحاب'),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.group_add_outlined, color: kGold),
                    title: Text('دعوتُ $_invited'),
                    subtitle: const Text('أرسل رابطك الخاص، فيُحسب لك كل من فتح التطبيق منه'),
                    trailing: IconButton(
                      icon: const Icon(Icons.share),
                      onPressed: () => Share.share('تطبيق «ابن الشابرة»: أجوبة الشيخ قايد بن غانم الشابرة وكتبه، والمصحف والأذكار 🌿\n'
                          '${AppConfig.siteUrl}#/i/$no'),
                    ),
                  ),
                ),
              ],
              const _Head('ملف متابع آخر'),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    keyboardType: TextInputType.number,
                    maxLength: 5,
                    decoration: const InputDecoration(
                        counterText: '', hintText: 'رقمه (5 أرقام)', border: OutlineInputBorder(), isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final n = int.tryParse(_search.text.trim());
                    if (n == null) return;
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PublicProfileScreen(no: n)));
                  },
                  child: const Text('افتح'),
                ),
              ]),
              const SizedBox(height: 8),
              const Text('يتحدّث ملفك للناس مرة في اليوم.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
          );
        },
      );
}

class _Head extends StatelessWidget {
  final String t;
  const _Head(this.t);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Text(t, style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 16)),
      );
}

/// Another follower's public page, found by his number (one read).
class PublicProfileScreen extends StatelessWidget {
  final int no;
  const PublicProfileScreen({super.key, required this.no});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('رقم $no')),
        body: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance.collection('quizUsers').where('no', isEqualTo: no).limit(1).get(),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            final docs = snap.data?.docs ?? const [];
            if (docs.isEmpty) return const EmptyState(icon: Icons.person_search, text: 'لا يوجد متابع بهذا الرقم.');
            final m = docs.first.data();
            int n(String k) => (m[k] as num?)?.toInt() ?? 0;
            final name = m['showName'] == true && '${m['nick'] ?? ''}'.trim().isNotEmpty ? '${m['nick']}'.trim() : 'رقم $no';
            final badges = [for (final b in (m['badges'] as List? ?? const [])) '$b'];
            return ListView(padding: const EdgeInsets.all(14), children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(colors: [Color(0xFF0E3B44), Color(0xFF1F5E3B)]),
                  border: Border.all(color: kGold),
                ),
                child: Column(children: [
                  Text(name, style: const TextStyle(fontFamily: 'Tajawal', color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  Text('${n('pts')}', style: const TextStyle(fontFamily: 'Tajawal', color: kGold, fontSize: 38, fontWeight: FontWeight.bold)),
                  const Text('نقطة', style: TextStyle(color: Colors.white70)),
                ]),
              ),
              const SizedBox(height: 10),
              Card(
                child: Column(children: [
                  ListTile(dense: true, leading: const Icon(Icons.menu_book), title: Text('قرأ ${n('reads')} جواباً')),
                  ListTile(dense: true, leading: const Icon(Icons.local_fire_department), title: Text('${n('days')} أيام متتالية')),
                  ListTile(dense: true, leading: const Icon(Icons.quiz), title: Text('أصاب ${n('score')} سؤالاً')),
                  ListTile(
                      dense: true,
                      leading: const Icon(Icons.emoji_events),
                      title: Text('فاز في ${n('chWins')} تحدّياً (${n('chWinsDuel')} فردي، ${n('chWinsGroup')} جماعي)')),
                  ListTile(dense: true, leading: const Icon(Icons.headphones), title: Text('سمع ${n('listens')} تسجيلاً')),
                  if (n('hifz') > 0) ListTile(dense: true, leading: const Icon(Icons.psychology), title: Text('حفظ ${n('hifz')} صفحة')),
                ]),
              ),
              if (badges.isNotEmpty) ...[
                const _Head('أوسمته'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final b in badges) Chip(avatar: const Icon(Icons.verified, color: kGold, size: 18), label: Text(b)),
                ]),
              ],
            ]);
          },
        ),
      );
}

/// The top three of the quiz on the home page (from the site file).
class LeadersHomeCard extends StatelessWidget {
  const LeadersHomeCard({super.key});

  @override
  Widget build(BuildContext context) => FutureBuilder<List<LeaderRow>>(
        future: Quiz.instance.leaders('month').then((l) async => l.isNotEmpty ? l : await Quiz.instance.leaders('all')),
        builder: (context, snap) {
          final l = (snap.data ?? const <LeaderRow>[]).take(3).toList();
          if (l.isEmpty) return const SizedBox.shrink();
          const medals = ['🥇', '🥈', '🥉'];
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Material(
              borderRadius: BorderRadius.circular(18),
              color: kGold.withValues(alpha: .12),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeaderboardScreen())),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: kGold)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('المتصدّرون في الأسئلة',
                        style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 6),
                    Row(children: [
                      for (var i = 0; i < l.length; i++)
                        Expanded(
                          child: Column(children: [
                            Text(medals[i], style: const TextStyle(fontSize: 26)),
                            Text(l[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text('${l[i].score}', style: const TextStyle(color: kGoldChip)),
                          ]),
                        ),
                    ]),
                  ]),
                ),
              ),
            ),
          );
        },
      );
}
