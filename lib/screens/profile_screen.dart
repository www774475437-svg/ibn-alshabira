import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../data/repository.dart';
import '../services/challenge.dart';
import '../services/cloud.dart';
import '../services/profiles.dart';
import '../services/progress.dart';
import '../services/quiz.dart';
import '../services/site_files.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'challenge_screens.dart';
import '../services/tour.dart';
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
  int _invited = 0;

  @override
  void initState() {
    super.initState();
    Quiz.instance.load();
    Challenges.instance.load();
    Progress.load().then((_) => mounted ? setState(() {}) : null);
    Profiles.instance.load();
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
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: kGold.withValues(alpha: .22), borderRadius: BorderRadius.circular(14)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.auto_stories, color: kGold, size: 18),
                      const SizedBox(width: 6),
                      Text('قرأتَ هذا الشهر: ${Repository.instance.readThisMonth}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ]),
                  ),
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
              if (u != null) ...[
                const _Head('ملفي والمتابعة'),
                ListenableBuilder(
                  listenable: Profiles.instance,
                  builder: (context, _) {
                    final pr = Profiles.instance;
                    final mine = pr.mine;
                    int n(String k) => (mine?[k] as num?)?.toInt() ?? 0;
                    return Card(
                      child: Column(children: [
                        ListTile(
                          leading: const Icon(Icons.badge_outlined, color: kGold),
                          title: Text('رقمي: $no', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(mine == null
                              ? 'يظهر ملفك للناس خلال 6 ساعات'
                              : 'متابِعوك ${n('fr')} · تتابع ${pr.following.length}${pr.newFollowers > 0 ? ' · جديد +${pr.newFollowers} 🎉' : ''}'),
                          trailing: const Icon(Icons.chevron_left),
                          onTap: () {
                            pr.seenNewFollowers();
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => PublicProfileScreen(no: no!)));
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.person_search),
                          title: const Text('ابحث عن شخص برقمه'),
                          trailing: const Icon(Icons.chevron_left),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FindProfileScreen())),
                        ),
                        ListTile(
                          leading: const Icon(Icons.group_outlined),
                          title: Text('من أتابعهم (${pr.following.length})'),
                          trailing: const Icon(Icons.chevron_left),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FollowingScreen())),
                        ),
                        ListTile(
                          leading: const Icon(Icons.format_quote),
                          title: Text('اقتباساتي (${pr.quotes.length})'),
                          trailing: const Icon(Icons.chevron_left),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyQuotesScreen())),
                        ),
                      ]),
                    );
                  },
                ),
              ],
              const SizedBox(height: 8),
              const Text('يتحدّث ملفك للناس كل 6 ساعات.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
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

String _hint(DateTime? at) {
  if (at == null) return 'تتحدّث الملفات كل 6 ساعات.';
  final h = DateTime.now().difference(at).inHours;
  return 'تتحدّث الملفات كل 6 ساعات · آخر تحديث ${h < 1 ? 'قبل أقل من ساعة' : 'قبل $h ساعة'}';
}

/// A reader's public page, found by his 6-digit number. It comes from the
/// file the server makes four times a day: no Firestore read.
class PublicProfileScreen extends StatefulWidget {
  final int no;
  const PublicProfileScreen({super.key, required this.no});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Profiles.instance.load().then((_) => mounted ? setState(() => _loading = false) : null);
  }

  Future<void> _challenge() async {
    final (code, err) = await Challenges.instance.create(mode: 'duel');
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    await Share.share('أتحدّاك في أسئلة تطبيق «ابن الشابرة» ⚡\nادخل التحدّي رقم $code:\n${AppConfig.siteUrl}#/c/$code');
    if (mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChallengeRoom(code: code!)));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Profiles.instance,
        builder: (context, _) {
          final pr = Profiles.instance;
          final no = '${widget.no}';
          final m = pr.page(no);
          final me = pr.myNo == no;
          return Scaffold(
            appBar: AppBar(title: Text('الملف $no')),
            body: _loading
                ? const Center(child: CircularProgressIndicator())
                : m == null
                    ? const EmptyState(
                        icon: Icons.person_search,
                        text: 'لا يوجد ملف بهذا الرقم بعد.\nتظهر الملفات بعد أن يفتح صاحبها النسخة الجديدة، وتتحدّث كل 6 ساعات.')
                    : ProfileView(no: no, m: m, me: me, onChallenge: me ? null : _challenge),
          );
        },
      );
}

/// The page itself (also shown in «لوحتي» for the reader's own page).
class ProfileView extends StatelessWidget {
  final String no;
  final Map<String, dynamic> m;
  final bool me;
  final VoidCallback? onChallenge;
  const ProfileView({super.key, required this.no, required this.m, this.me = false, this.onChallenge});

  @override
  Widget build(BuildContext context) {
    final pr = Profiles.instance;
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;
    final name = '${m['n'] ?? ''}'.trim();
    final badges = [for (final b in (m['b'] as List? ?? const [])) '$b'];
    final quotes = [for (final q in (m['q'] as List? ?? const [])) Map<String, dynamic>.from(q as Map)];
    final following = pr.isFollowing(no);
    Widget box(String label, int v, IconData icon, Color c) => Container(
          decoration: BoxDecoration(
              color: c.withValues(alpha: .1), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withValues(alpha: .4))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: c, size: 22),
            Text('$v', style: TextStyle(fontFamily: 'Tajawal', fontSize: 20, fontWeight: FontWeight.bold, color: c)),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5)),
          ]),
        );
    return ListView(padding: const EdgeInsets.all(12), children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(colors: [Color(0xFF0E3B44), Color(0xFF1F5E3B)]),
          border: Border.all(color: kGold),
        ),
        child: Column(children: [
          Text(name.isEmpty ? 'رقم $no' : name,
              style: const TextStyle(fontFamily: 'Tajawal', color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          if (name.isNotEmpty) Text('رقم $no', style: const TextStyle(color: kGold)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Column(children: [
              Text('${n('fr')}', style: const TextStyle(fontFamily: 'Tajawal', color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const Text('متابِعون', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
            const SizedBox(width: 30),
            Column(children: [
              Text('${n('p')}', style: const TextStyle(fontFamily: 'Tajawal', color: kGold, fontSize: 26, fontWeight: FontWeight.bold)),
              Text('نقطة · ${Progress.rankOf(n('p'))}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
            const SizedBox(width: 30),
            Column(children: [
              Text('${n('fg')}', style: const TextStyle(fontFamily: 'Tajawal', color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const Text('يتابِع', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ]),
          if (!me) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: following ? Colors.white24 : kGold, foregroundColor: following ? Colors.white : Colors.black),
                  icon: Icon(following ? Icons.check : Icons.person_add_alt_1),
                  label: Text(following ? 'تتابعه' : 'تابِع'),
                  onPressed: Cloud.instance.user == null ? null : () => pr.toggleFollow(no),
                ),
              ),
              if (onChallenge != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                    icon: const Icon(Icons.bolt),
                    label: const Text('تحدَّه'),
                    onPressed: Cloud.instance.user == null ? null : onChallenge,
                  ),
                ),
              ],
            ]),
          ],
        ]),
      ),
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.15,
        children: [
          box('أيام متتالية', n('d'), Icons.local_fire_department, const Color(0xFFB0602A)),
          box('أجوبة قرأها', n('rd'), Icons.menu_book, const Color(0xFF0E3B44)),
          box('أسئلة أصابها', n('r'), Icons.check_circle, const Color(0xFF2E7D32)),
          box('تحديات لعبها', n('cp'), Icons.bolt, const Color(0xFF7A1F1F)),
          box('فاز فيها', n('cw'), Icons.emoji_events, const Color(0xFF9C7A1E)),
          box('تسجيلات سمعها', n('ls'), Icons.headphones, const Color(0xFF3B4A8C)),
        ],
      ),
      if (Tour.instance.winsOf(int.tryParse('$no') ?? 0) > 0)
        Card(
          color: kGold.withValues(alpha: .15),
          margin: const EdgeInsets.only(top: 10),
          child: ListTile(
            leading: const Icon(Icons.emoji_events, color: kGold, size: 34),
            title: const Text('بطل الجمعة', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 18)),
            subtitle: Text('فاز ببطولة الجمعة ${Tour.instance.winsOf(int.tryParse('$no') ?? 0)} مرة'),
          ),
        ),
      if (badges.isNotEmpty) ...[
        const _Head('الأوسمة'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final b in badges) Chip(avatar: const Icon(Icons.verified, color: kGold, size: 18), label: Text(b)),
        ]),
      ],
      _Head('الاقتباسات (${quotes.length})'),
      if (quotes.isEmpty)
        Text(me ? 'لم تضف اقتباسات بعد. أضفها من صفحة أي جواب أو من داخل الكتب.' : 'لا اقتباسات بعد',
            style: const TextStyle(color: Colors.grey))
      else
        for (final q in quotes) QuoteCard(text: '${q['t']}', source: '${q['s']}'),
      const SizedBox(height: 12),
      Text(_hint(pr.at), textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 12)),
    ]);
  }
}

class QuoteCard extends StatelessWidget {
  final String text, source;
  final VoidCallback? onDelete;
  const QuoteCard({super.key, required this.text, required this.source, this.onDelete});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.format_quote, color: kGold),
            const SizedBox(width: 6),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('«$text»', style: const TextStyle(height: 1.8, fontSize: 15.5)),
                if (source.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(source, style: const TextStyle(color: kGoldChip, fontSize: 12.5)),
                  ),
              ]),
            ),
            if (onDelete != null) IconButton(icon: const Icon(Icons.delete_outline, size: 20), onPressed: onDelete),
          ]),
        ),
      );
}

/// Find a reader by his 6-digit number (three searches a day).
class FindProfileScreen extends StatefulWidget {
  const FindProfileScreen({super.key});

  @override
  State<FindProfileScreen> createState() => _FindProfileScreenState();
}

class _FindProfileScreenState extends State<FindProfileScreen> {
  final _c = TextEditingController();
  int _left = Profiles.searchesPerDay;

  @override
  void initState() {
    super.initState();
    Profiles.instance.searchesLeft().then((v) => mounted ? setState(() => _left = v) : null);
  }

  Future<void> _go() async {
    final t = _c.text.trim().split('').map((c) {
      final i = '٠١٢٣٤٥٦٧٨٩'.indexOf(c);
      return i >= 0 ? '$i' : c;
    }).join();
    final n = int.tryParse(t);
    if (n == null || t.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب الرقم كاملاً: 6 أرقام')));
      return;
    }
    if (_left <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('انتهت بحوثك اليوم، عُد غداً إن شاء الله')));
      return;
    }
    await Profiles.instance.useSearch();
    final left = await Profiles.instance.searchesLeft();
    if (!mounted) return;
    setState(() => _left = left);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PublicProfileScreen(no: n)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ابحث عن شخص')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('اكتب رقمه (6 أرقام)، وهو الرقم الظاهر في «لوحتي» وفي «اسأل الشيخ».', style: TextStyle(height: 1.7)),
          const SizedBox(height: 12),
          TextField(
            controller: _c,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Tajawal', fontSize: 26, letterSpacing: 6),
            decoration: const InputDecoration(counterText: '', hintText: '000000', border: OutlineInputBorder()),
            onSubmitted: (_) => _go(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            icon: const Icon(Icons.person_search),
            label: const Text('ابحث'),
            onPressed: _go,
          ),
          const SizedBox(height: 10),
          Text(Cloud.instance.isAdmin ? 'أنت من الإدارة: بحثك بلا حد.' : 'بقي لك اليوم: $_left من ${Profiles.searchesPerDay} بحوث',
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
        ]),
      );
}

/// «من أتابعهم»: the people the reader follows, with a glance at each.
class FollowingScreen extends StatefulWidget {
  const FollowingScreen({super.key});

  @override
  State<FollowingScreen> createState() => _FollowingScreenState();
}

class _FollowingScreenState extends State<FollowingScreen> {
  @override
  void initState() {
    super.initState();
    Profiles.instance.load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Profiles.instance,
        builder: (context, _) {
          final pr = Profiles.instance;
          final l = pr.following.toList()..sort();
          final friends = l.where(pr.isFriend).toList();
          Widget tile(String no) {
            final m = pr.page(no);
            int n(String k) => (m?[k] as num?)?.toInt() ?? 0;
            final name = '${m?['n'] ?? ''}'.trim();
            final friend = pr.isFriend(no);
            return ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFF0E3B44), child: Icon(Icons.person, color: kGold)),
              title: Text(name.isEmpty ? 'رقم $no' : name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(m == null
                  ? 'لم يتحدّث ملفه بعد'
                  : '${Progress.rankOf(n('p'))} · 🔥 ${n('d')} يوم   📖 ${n('rd')}   🏆 ${n('cw')} من ${n('cp')}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: friend ? 'إزالة من الأصدقاء' : 'أضفه إلى الأصدقاء',
                  icon: Icon(friend ? Icons.star_rounded : Icons.star_outline_rounded, color: friend ? kGold : null),
                  onPressed: () => pr.toggleFriend(no),
                ),
                if (friend)
                  IconButton(
                    tooltip: 'تحدَّه',
                    icon: const Icon(Icons.bolt, color: kGold),
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => PublicProfileScreen(no: int.parse(no)))),
                  ),
              ]),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => PublicProfileScreen(no: int.parse(no)))),
            );
          }

          // «سباق القراءة»: this month's reading among the people one follows, and oneself.
          final mk = '${DateTime.now().year}-${DateTime.now().month}';
          final race = <(String, String, int, bool)>[
            for (final no in l)
              if (pr.page(no) case final Map m)
                ('${m['n'] ?? ''}'.trim().isEmpty ? 'رقم $no' : '${m['n']}', no, m['mk'] == mk ? (m['rm'] as num? ?? 0).toInt() : 0, false),
            ('أنت', '', Repository.instance.readThisMonth, true),
          ]..sort((a, b) => b.$3.compareTo(a.$3));

          return DefaultTabController(
            length: 3,
            child: Scaffold(
              appBar: AppBar(
                title: Text('من أتابعهم (${l.length})'),
                bottom: TabBar(tabs: [
                  const Tab(text: 'الكل'),
                  Tab(text: 'الأصدقاء (${friends.length})'),
                  const Tab(text: 'سباق القراءة'),
                ]),
              ),
              body: TabBarView(children: [
                l.isEmpty
                    ? const EmptyState(icon: Icons.group_outlined, text: 'لا تتابع أحداً بعد. ابحث برقم شخص ثم اضغط «تابِع».')
                    : ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [for (final no in l) tile(no)]),
                friends.isEmpty
                    ? const EmptyState(
                        icon: Icons.star_outline_rounded, text: 'اضغط النجمة بجانب من تتابعه ليصير في أصدقائك، فتتحدّاه بسرعة.')
                    : ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [for (final no in friends) tile(no)]),
                ListView(padding: const EdgeInsets.all(12), children: [
                  const Text('من قرأ أكثر هذا الشهر بينك وبين من تتابعهم. يتحدّث كل بضع ساعات.',
                      style: TextStyle(color: Colors.grey, height: 1.6)),
                  const SizedBox(height: 8),
                  for (var i = 0; i < race.length; i++)
                    Card(
                      color: race[i].$4 ? kGold.withValues(alpha: .14) : null,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: i < 3 ? kGold : Colors.grey.withValues(alpha: .25),
                          child: Text('${i + 1}', style: TextStyle(color: i < 3 ? Colors.white : null)),
                        ),
                        title: Text(race[i].$1, style: const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: Text('📖 ${race[i].$3}',
                            style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 17)),
                      ),
                    ),
                ]),
              ]),
            ),
          );
        },
      );
}

/// «اقتباساتي»: the reader's quotes, with delete.
class MyQuotesScreen extends StatelessWidget {
  const MyQuotesScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Profiles.instance,
        builder: (context, _) {
          final q = Profiles.instance.quotes;
          return Scaffold(
            appBar: AppBar(title: Text('اقتباساتي (${q.length})')),
            body: q.isEmpty
                ? const EmptyState(
                    icon: Icons.format_quote, text: 'أضف اقتباساً من صفحة أي جواب (الزر ❝ في الأعلى) أو من داخل أي كتاب.')
                : ListView(padding: const EdgeInsets.all(10), children: [
                    for (var i = 0; i < q.length; i++)
                      QuoteCard(text: '${q[i]['t']}', source: '${q[i]['s']}', onDelete: () => Profiles.instance.removeQuote(i)),
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('تظهر اقتباساتك في ملفك لمن يتابعك، وتتحدّث كل 6 ساعات.',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ),
                  ]),
          );
        },
      );
}

/// Opens a dialog to add a quote (text can be shortened before saving).
Future<void> addQuoteDialog(BuildContext context, {required String text, required String source}) async {
  if (Cloud.instance.user == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('سجّل الدخول أولاً لتحفظ اقتباساتك في ملفك')));
    return;
  }
  final c = TextEditingController(text: text.length > 600 ? text.substring(0, 600) : text);
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('أضف إلى اقتباساتي'),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('احذف ما لا تريده، واترك الجملة التي تريد اقتباسها (600 حرف على الأكثر).',
              style: TextStyle(color: Colors.grey, fontSize: 12.5)),
          const SizedBox(height: 8),
          TextField(controller: c, maxLines: 8, minLines: 3, maxLength: 600, decoration: const InputDecoration(border: OutlineInputBorder())),
          Text(source, style: const TextStyle(color: kGoldChip, fontSize: 12.5)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('أضف')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final err = await Profiles.instance.addQuote(c.text, source);
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(err ?? 'أُضيف إلى اقتباساتك، ويظهر في ملفك خلال 6 ساعات')));
  }
}

/// The top three of the quiz on the home page (from the site file).
class LeadersHomeCard extends StatefulWidget {
  const LeadersHomeCard({super.key});

  @override
  State<LeadersHomeCard> createState() => _LeadersHomeCardState();
}

class _LeadersHomeCardState extends State<LeadersHomeCard> {
  late final Future<(List<LeaderRow>, bool)> _load = () async {
    final m = await Quiz.instance.leaders('month');
    if (m.isNotEmpty) return (m, true);
    return (await Quiz.instance.leaders('all'), false);
  }();

  @override
  Widget build(BuildContext context) => FutureBuilder<(List<LeaderRow>, bool)>(
        future: _load,
        builder: (context, snap) {
          final waiting = snap.connectionState == ConnectionState.waiting;
          final l = (snap.data?.$1 ?? const <LeaderRow>[]).take(3).toList();
          final month = snap.data?.$2 ?? true;
          // Second on the right, first in the middle, third on the left.
          Widget step(int rank) {
            final r = rank <= l.length ? l[rank - 1] : null;
            const medals = ['🥇', '🥈', '🥉'];
            const heights = [92.0, 70.0, 54.0];
            return Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(medals[rank - 1], style: TextStyle(fontSize: rank == 1 ? 34 : 28)),
                const SizedBox(height: 2),
                if (waiting)
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Skeleton(height: 14, radius: 7))
                else
                  Text(r?.name ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: rank == 1 ? 15 : 13.5)),
                Text(r == null ? ' ' : '${r.score} إجابة صحيحة',
                    style: const TextStyle(color: kGold, fontSize: 12)),
                const SizedBox(height: 4),
                Container(
                  height: heights[rank - 1],
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: rank == 1
                          ? const [Color(0xFFE9C46A), Color(0xFFB8913A)]
                          : rank == 2
                              ? const [Color(0xFFD9DEE2), Color(0xFF9AA5AD)]
                              : const [Color(0xFFD9A066), Color(0xFF9C6B3A)],
                    ),
                  ),
                  child: Text('$rank',
                      style: const TextStyle(
                          fontFamily: 'Tajawal', fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF1B1B1B))),
                ),
              ]),
            );
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Material(
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              elevation: 2,
              child: Ink(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF0E3B44), Color(0xFF1F5E3B)]),
                ),
                child: InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeaderboardScreen())),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        const Icon(Icons.emoji_events, color: kGold, size: 26),
                        const SizedBox(width: 8),
                        const Text('المتصدّرون',
                            style: TextStyle(fontFamily: 'Tajawal', color: Colors.white, fontWeight: FontWeight.bold, fontSize: 19)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: kGold.withValues(alpha: .2), borderRadius: BorderRadius.circular(10)),
                          child: Text(month ? 'هذا الشهر' : 'كل الوقت',
                              style: const TextStyle(color: kGold, fontSize: 12)),
                        ),
                        const Spacer(),
                        const Text('الكل', style: TextStyle(color: Colors.white70)),
                        const Icon(Icons.chevron_left, color: Colors.white70),
                      ]),
                      if (!waiting && l.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text('كن أول المتصدّرين: أجب عن الأسئلة واجمع النقاط',
                              textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 13)),
                        ),
                      const SizedBox(height: 8),
                      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [step(2), step(1), step(3)]),
                    ]),
                  ),
                ),
              ),
            ),
          );
        },
      );
}
