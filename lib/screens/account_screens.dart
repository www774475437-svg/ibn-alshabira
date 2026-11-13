import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../data/repository.dart';
import '../services/cloud.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'admin_extra.dart';
import 'fatwa_screen.dart';

void _toast(BuildContext context, String t) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

/// Sign in with Google, see your account, open the admin panel.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cloud = Cloud.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('الحساب')),
      body: ListenableBuilder(
        listenable: cloud,
        builder: (context, _) {
          final u = cloud.user;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (u == null) ...[
                const _EmailAuthForm(),
              ] else ...[
                CircleAvatar(
                  radius: 44,
                  backgroundColor: kGold.withValues(alpha: 0.2),
                  backgroundImage: u.photoURL != null ? NetworkImage(u.photoURL!) : null,
                  child: u.photoURL == null ? const Icon(Icons.person, size: 44, color: kGold) : null,
                ),
                const SizedBox(height: 12),
                Text(u.displayName ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text(u.email ?? '', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 10),
                const Text('✅ محفوظاتك تُحفظ على حسابك', textAlign: TextAlign.center),
                if (cloud.isAdmin) ...[
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: kGold,
                      foregroundColor: Colors.black,
                    ),
                    icon: Badge(
                      isLabelVisible: cloud.newQuestions > 0,
                      label: Text('${cloud.newQuestions}'),
                      child: const Icon(Icons.admin_panel_settings),
                    ),
                    label: Text(cloud.isFullAdmin ? 'لوحة الإدارة' : 'لوحة المحرّر',
                        style: const TextStyle(fontSize: 17)),
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const AdminScreen())),
                  ),
                ],
                const SizedBox(height: 20),
                const _AskName(),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  icon: const Icon(Icons.logout),
                  label: const Text('تسجيل الخروج'),
                  onPressed: cloud.signOut,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Ordinary registration with email and password, plus Google as an option.
class _EmailAuthForm extends StatefulWidget {
  const _EmailAuthForm();

  @override
  State<_EmailAuthForm> createState() => _EmailAuthFormState();
}

class _EmailAuthFormState extends State<_EmailAuthForm> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _hide = true;

  Future<void> _run(Future<String?> Function() action, {String? ok}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final err = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      _toast(context, err);
    } else if (ok != null) {
      _toast(context, ok);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloud = Cloud.instance;
    InputDecoration deco(String label, IconData icon) => InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.account_circle_outlined, size: 76, color: kGold),
        const SizedBox(height: 8),
        Text(_register ? 'إنشاء حساب جديد' : 'تسجيل الدخول',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('لتُحفظ محفوظاتك، وتسأل الشيخ ويصلك جوابه.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 18),
        if (_register) ...[
          TextField(controller: _name, decoration: deco('الاسم', Icons.person_outline)),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          autofillHints: const [AutofillHints.email],
          decoration: deco('البريد الإلكتروني', Icons.email_outlined),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: _hide,
          textDirection: TextDirection.ltr,
          decoration: deco('كلمة السر', Icons.lock_outline).copyWith(
            suffixIcon: IconButton(
              icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _hide = !_hide),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _busy
              ? null
              : () => _run(() => _register
                  ? cloud.registerEmail(_name.text, _email.text, _password.text)
                  : cloud.signInEmail(_email.text, _password.text)),
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_register ? 'إنشاء الحساب' : 'دخول', style: const TextStyle(fontSize: 17)),
        ),
        TextButton(
          onPressed: () => setState(() => _register = !_register),
          child: Text(_register ? 'عندي حساب، أريد الدخول' : 'ليس عندي حساب، إنشاء حساب جديد'),
        ),
        if (!_register)
          TextButton(
            onPressed: () => _run(() => cloud.resetPassword(_email.text),
                ok: 'أرسلنا إلى بريدك رسالة لتغيير كلمة السر'),
            child: const Text('نسيت كلمة السر'),
          ),
        const Row(children: [
          Expanded(child: Divider()),
          Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('أو')),
          Expanded(child: Divider()),
        ]),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: const Text('G',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF4285F4))),
          label: const Text('الدخول بحساب جوجل',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          onPressed: () => _run(cloud.signIn),
        ),
      ],
    );
  }
}

/// «الأكثر قراءة»
class MostReadScreen extends StatelessWidget {
  const MostReadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('الأكثر قراءة')),
      body: FutureBuilder(
        future: Cloud.instance.mostRead(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = [
            for (final (id, count) in snap.data ?? <(String, int)>[])
              if (repo.findById(id) case final f?) (f, count),
          ];
          if (items.isEmpty) {
            return const EmptyState(icon: Icons.trending_up, text: 'لا توجد مشاهدات بعد');
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final (f, count) = items[i];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: i < 3 ? kGold : kGold.withValues(alpha: 0.2),
                    child: Text('${i + 1}',
                        style: TextStyle(
                            color: i < 3 ? Colors.black : kGoldChip, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text('👁 $count مشاهدة · باب ${repo.chapterName(f.chapter)}'),
                  onTap: () => openFatwa(context, f),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Admin panel: stats, admins, reports, publish an answer.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cloud = Cloud.instance;
    return ListenableBuilder(
      listenable: cloud,
      builder: (context, _) {
        final full = cloud.isFullAdmin;
        final tabs = <(Widget, Widget)>[
          (const Tab(icon: Icon(Icons.bar_chart), text: 'الإحصائيات'), const _StatsTab()),
          (
            Tab(
              icon: Badge(
                isLabelVisible: cloud.newQuestions > 0,
                label: Text('${cloud.newQuestions}'),
                child: const Icon(Icons.forum),
              ),
              text: 'الأسئلة',
            ),
            const QuestionsTab()
          ),
          (const Tab(icon: Icon(Icons.edit_note), text: 'نشر ومسودات'), const _PublishTab()),
          if (full) (const Tab(icon: Icon(Icons.campaign), text: 'الإعلان'), const AnnouncementTab()),
          if (full) (const Tab(icon: Icon(Icons.category), text: 'الأبواب'), const ChaptersTab()),
          if (full) (const Tab(icon: Icon(Icons.person_pin), text: 'عن الشيخ'), const AboutTab()),
          (const Tab(icon: Icon(Icons.flag), text: 'البلاغات'), const _ReportsTab()),
          (const Tab(icon: Icon(Icons.search_off), text: 'بحث بلا نتيجة'), const MissesTab()),
          if (full) (const Tab(icon: Icon(Icons.group), text: 'المشرفون'), const _AdminsTab()),
          if (cloud.isDeveloper) (const Tab(icon: Icon(Icons.history), text: 'السجل'), const LogTab()),
        ];
        return DefaultTabController(
          key: ValueKey(tabs.length),
          length: tabs.length,
          child: Scaffold(
            appBar: AppBar(
              title: Text(full ? 'لوحة الإدارة' : 'لوحة المحرّر'),
              bottom: TabBar(
                isScrollable: true,
                labelColor: kGold,
                unselectedLabelColor: Colors.white70,
                indicatorColor: kGold,
                tabs: [for (final t in tabs) t.$1],
              ),
            ),
            body: TabBarView(children: [for (final t in tabs) t.$2]),
          ),
        );
      },
    );
  }
}

class _StatsTab extends StatelessWidget {
  const _StatsTab();

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return FutureBuilder(
      future: Cloud.instance.overview(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final s = snap.data ?? {};
        Widget tile(IconData icon, String label, Object value) => Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: kGold, size: 28),
                    const SizedBox(height: 6),
                    Text('$value', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            );
        return ListView(
          children: [
            GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          crossAxisCount: 2,
          childAspectRatio: 1.25,
          children: [
            tile(Icons.person_outline, 'قرّاء اليوم', s['readersToday'] ?? 0),
            tile(Icons.groups_outlined, 'قرّاء آخر 7 أيام', s['readersWeek'] ?? 0),
            tile(Icons.visibility, 'مجموع المشاهدات', s['views'] ?? 0),
            tile(Icons.article, 'عدد الأجوبة في التطبيق', repo.fatwas.length),
            tile(Icons.auto_stories, 'أجوبة قُرئت', s['answersViewed'] ?? 0),
            tile(Icons.publish, 'أجوبة نُشرت من التطبيق', s['published'] ?? 0),
            tile(Icons.thumb_up, 'أفادهم الجواب', s['helpful'] ?? 0),
            tile(Icons.thumb_down, 'لم يُفدهم', s['notHelpful'] ?? 0),
            tile(Icons.flag, 'البلاغات', s['reports'] ?? 0),
            tile(Icons.share, 'مرات نشر التطبيق', s['shares'] ?? 0),
          ],
            ),
            const _VotesLists(),
          ],
        );
      },
    );
  }
}

/// Which answers helped people most, and which need improving.
/// Optional name or kunya the asker wants the sheikh to see with their
/// questions. Only the sheikh and the staff ever see it.
class _AskName extends StatefulWidget {
  const _AskName();

  @override
  State<_AskName> createState() => _AskNameState();
}

class _AskNameState extends State<_AskName> {
  final _c = TextEditingController();

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) _c.text = p.getString('askName') ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _c,
          maxLength: 40,
          decoration: InputDecoration(
            labelText: 'اسمك أو كنيتك (اختياري)',
            hintText: 'مثل: أبو عبد الرحمن',
            helperText: 'يراه الشيخ والمشرفون فقط مع أسئلتك، ولا يظهر لأحد غيرهم ولا في الأجوبة المنشورة.',
            helperMaxLines: 3,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: 'حفظ',
              icon: const Icon(Icons.check),
              onPressed: () async {
                final p = await SharedPreferences.getInstance();
                await p.setString('askName', _c.text.trim());
                if (!context.mounted) return;
                FocusScope.of(context).unfocus();
                _toast(context, 'حُفظ الاسم');
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _VotesLists extends StatelessWidget {
  const _VotesLists();

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return FutureBuilder(
      future: Cloud.instance.votes(),
      builder: (context, snap) {
        final all = snap.data ?? [];
        final best = all.where((e) => e.$2 > 0).toList()..sort((a, b) => b.$2.compareTo(a.$2));
        final worst = all.where((e) => e.$3 > 0).toList()..sort((a, b) => b.$3.compareTo(a.$3));
        Widget section(String title, IconData icon, List<(String, int, int)> items, bool good) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Text('لا تقييمات بعد', style: TextStyle(color: Colors.grey)),
                  ),
                for (final e in items.take(10))
                  ListTile(
                    dense: true,
                    leading: Icon(icon, color: good ? kGold : Colors.grey),
                    title: Text(repo.findById(e.$1)?.title ?? '(جواب محذوف)',
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: Text('${good ? e.$2 : e.$3}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    onTap: () {
                      final f = repo.findById(e.$1);
                      if (f != null) {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => FatwaScreen(fatwa: f)));
                      }
                    },
                  ),
              ],
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            section('أكثر الأجوبة نفعاً', Icons.thumb_up, best, true),
            section('أجوبة قيل فيها «لم يفدني»', Icons.thumb_down, worst, false),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }
}

class _PublishTab extends StatefulWidget {
  const _PublishTab();

  @override
  State<_PublishTab> createState() => _PublishTabState();
}

class _PublishTabState extends State<_PublishTab> {
  final _title = TextEditingController();
  final _question = TextEditingController();
  final _answer = TextEditingController();
  final _tags = TextEditingController();
  final _audio = TextEditingController();
  String _sub = '';
  DateTime? _publishAt;
  String _chapter = Repository.instance.chapters.first.id;
  String? _draftId;
  bool _busy = false;

  void _clear() {
    _title.clear();
    _question.clear();
    _answer.clear();
    _tags.clear();
    _audio.clear();
    _sub = '';
    _publishAt = null;
    _draftId = null;
  }

  Future<void> _publish() async {
    if (_title.text.trim().isEmpty || _answer.text.trim().isEmpty) {
      _toast(context, 'اكتب العنوان والجواب');
      return;
    }
    setState(() => _busy = true);
    final later = _publishAt != null && _publishAt!.isAfter(DateTime.now());
    final err = await Cloud.instance.publishAnswer(
        chapter: _chapter,
        title: _title.text,
        question: _question.text,
        answer: _answer.text,
        tags: parseTags(_tags.text),
        sub: _sub,
        audio: _audio.text,
        publishAt: later ? _publishAt : null);
    if (err == null && _draftId != null) await Cloud.instance.deleteDraft(_draftId!);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (err == null) _clear();
    });
    _toast(context, err ?? (later ? 'جُدول الجواب ✅ ويظهر للناس في وقته' : 'تم النشر ✅ يظهر الآن لكل مستخدمي التطبيق'));
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final day = await showDatePicker(
        context: context, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 365)));
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now));
    if (time == null || !mounted) return;
    setState(() => _publishAt = DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }

  String _fmt(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '${t.day}/${t.month}/${t.year} الساعة $h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'ص' : 'م'}';
  }

  Future<void> _saveDraft() async {
    if (_title.text.trim().isEmpty && _answer.text.trim().isEmpty) {
      _toast(context, 'اكتب شيئاً أولاً');
      return;
    }
    final err = await Cloud.instance.saveDraft(_draftId,
        chapter: _chapter, title: _title.text, question: _question.text, answer: _answer.text);
    if (!mounted) return;
    if (err == null) setState(_clear);
    _toast(context, err ?? 'حُفظت المسودة، وتجدها في الأسفل');
  }

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    if (!repo.chapters.any((c) => c.id == _chapter)) _chapter = repo.chapters.first.id;
    InputDecoration deco(String label) =>
        InputDecoration(labelText: label, border: const OutlineInputBorder(), alignLabelWithHint: true);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_draftId != null)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text('تعدّل الآن مسودة محفوظة', style: TextStyle(color: kGoldChip)),
          ),
        DropdownButtonFormField<String>(
          key: ValueKey(_chapter),
          value: _chapter,
          decoration: deco('الباب'),
          items: [for (final c in repo.chapters) DropdownMenuItem(value: c.id, child: Text(c.name))],
          onChanged: (v) => setState(() {
            _chapter = v ?? _chapter;
            _sub = '';
          }),
        ),
        SubPicker(chapterId: _chapter, value: _sub, onChanged: (v) => setState(() => _sub = v)),
        const SizedBox(height: 12),
        TextField(controller: _title, decoration: deco('العنوان')),
        const SizedBox(height: 12),
        TextField(controller: _question, maxLines: 3, decoration: deco('السؤال (اختياري)')),
        const SizedBox(height: 12),
        TextField(controller: _answer, maxLines: 10, decoration: deco('الجواب')),
        const SizedBox(height: 12),
        TextField(controller: _tags, decoration: deco('الوسوم (اختياري، افصل بينها بفاصلة)')),
        const SizedBox(height: 12),
        TextField(
          controller: _audio,
          textDirection: TextDirection.ltr,
          decoration: deco('رابط تسجيل صوتي للجواب (اختياري)'),
        ),
        const SizedBox(height: 6),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule, color: kGold),
          title: Text(_publishAt == null ? 'وقت النشر: الآن' : 'يُنشر في ${_fmt(_publishAt!)}'),
          trailing: _publishAt == null
              ? TextButton(onPressed: _pickTime, child: const Text('جدولة'))
              : IconButton(
                  tooltip: 'إلغاء الجدولة',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _publishAt = null)),
          onTap: _pickTime,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                icon: const Icon(Icons.save_outlined),
                label: const Text('حفظ مسودة'),
                onPressed: _busy ? null : _saveDraft,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.publish),
                label: Text(_publishAt == null ? 'نشر' : 'جدولة'),
                onPressed: _busy ? null : _publish,
              ),
            ),
          ],
        ),
        const Divider(height: 36),
        const Text('المسودات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        StreamBuilder(
          stream: Cloud.instance.draftsStream(),
          builder: (context, snap) {
            final all = snap.data?.docs ?? [];
            final docs = all.where((d) => d.data()['trash'] != true).toList();
            final trash = all.where((d) => d.data()['trash'] == true).toList();
            // Empty the trash of anything older than 30 days.
            for (final d in trash) {
              final at = d.data()['deletedAt'];
              if (at is Timestamp && DateTime.now().difference(at.toDate()).inDays >= 30) {
                Cloud.instance.deleteDraft(d.id);
              }
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (docs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('لا توجد مسودات', style: TextStyle(color: Colors.grey)),
                  ),
                for (final d in docs)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: const Icon(Icons.drafts_outlined, color: kGold),
                      title: Text('${d.data()['title'] ?? ''}'.isEmpty ? '(بلا عنوان)' : '${d.data()['title']}',
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${d.data()['by'] ?? ''}', textDirection: TextDirection.ltr),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => Cloud.instance.deleteDraft(d.id),
                      ),
                      onTap: () => setState(() {
                        final m = d.data();
                        _draftId = d.id;
                        _title.text = '${m['title'] ?? ''}';
                        _question.text = '${m['question'] ?? ''}';
                        _answer.text = '${m['answer'] ?? ''}';
                        final ch = '${m['chapter'] ?? ''}';
                        if (repo.chapters.any((c) => c.id == ch)) _chapter = ch;
                      }),
                    ),
                  ),
                if (Cloud.instance.scheduled.isNotEmpty) ...[
                  const Divider(height: 30),
                  const Text('أجوبة مجدولة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  for (final (id, title, at) in Cloud.instance.scheduled)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.schedule, color: kGold),
                        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text('يُنشر في ${_fmt(at)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'انشره الآن',
                              icon: const Icon(Icons.publish),
                              onPressed: () async {
                                final err = await Cloud.instance.publishNow(id);
                                if (!context.mounted) return;
                                _toast(context, err ?? 'نُشر الآن ✅');
                                setState(() {});
                              },
                            ),
                            IconButton(
                              tooltip: 'إلغاء وحذف',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                await Cloud.instance.cancelScheduled(id);
                                if (mounted) setState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                if (trash.isNotEmpty) ...[
                  const Divider(height: 30),
                  const Text('سلة المحذوفات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Text('تُحذف نهائياً بعد 30 يوماً', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  for (final d in trash)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.delete_sweep_outlined, color: Colors.grey),
                        title: Text('${d.data()['title'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text('حذفه: ${d.data()['deletedBy'] ?? ''}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'استرجاع',
                              icon: const Icon(Icons.restore),
                              onPressed: () async {
                                final err = await Cloud.instance.restoreAnswer(d.id);
                                if (!context.mounted) return;
                                _toast(context, err ?? 'استُرجع الجواب ✅');
                              },
                            ),
                            IconButton(
                              tooltip: 'حذف نهائي',
                              icon: const Icon(Icons.delete_forever_outlined),
                              onPressed: () => Cloud.instance.deleteDraft(d.id),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ReportsTab extends StatelessWidget {
  const _ReportsTab();

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return StreamBuilder(
      stream: Cloud.instance.reportsStream(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const EmptyState(icon: Icons.flag_outlined, text: 'لا توجد بلاغات');
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final f = repo.findById('${d['answerId']}');
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: ListTile(
                title: Text('${d['title']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${d['note'] ?? ''}\n${d['by'] ?? ''}'),
                isThreeLine: true,
                onTap: f == null ? null : () => openFatwa(context, f),
                trailing: IconButton(
                  tooltip: 'حذف البلاغ',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => Cloud.instance.deleteReport(docs[i].id),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AdminsTab extends StatefulWidget {
  const _AdminsTab();

  @override
  State<_AdminsTab> createState() => _AdminsTabState();
}

class _AdminsTabState extends State<_AdminsTab> {
  final _email = TextEditingController();
  String _role = 'editor';

  @override
  Widget build(BuildContext context) {
    final cloud = Cloud.instance;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '«المحرّر» ينشر الأجوبة ويعدّلها ويرد على الأسئلة.\n'
          '«المشرف الكامل» يفعل ذلك كله، ويدير المشرفين والأبواب والإعلان والإعدادات.\n'
          'يدخل المشرف بحساب جوجل بنفس البريد المضاف هنا.',
          style: TextStyle(height: 1.8),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(hintText: 'example@gmail.com', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'editor', label: Text('محرّر'), icon: Icon(Icons.edit)),
            ButtonSegment(value: 'admin', label: Text('مشرف كامل'), icon: Icon(Icons.admin_panel_settings)),
          ],
          selected: {_role},
          onSelectionChanged: (s) => setState(() => _role = s.first),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          icon: const Icon(Icons.person_add),
          label: const Text('إضافة'),
          onPressed: () async {
            final err = await cloud.addAdmin(_email.text, role: _role);
            if (!context.mounted) return;
            if (err == null) _email.clear();
            _toast(context, err ?? 'تمت الإضافة ✅');
          },
        ),
        const SizedBox(height: 16),
        const ListTile(
          leading: Icon(Icons.verified, color: kGold),
          title: Text(Cloud.developerEmail, textDirection: TextDirection.ltr),
          subtitle: Text('المطوّر (دائماً)'),
        ),
        StreamBuilder(
          stream: cloud.adminsStream(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            return Column(
              children: [
                for (final d in docs)
                  ListTile(
                    leading: Icon((d.data()['role'] ?? 'admin') == 'admin'
                        ? Icons.admin_panel_settings
                        : Icons.edit),
                    title: Text(d.id, textDirection: TextDirection.ltr),
                    subtitle: Text(((d.data()['role'] ?? 'admin') == 'admin' ? 'مشرف كامل' : 'محرّر') +
                        (cloud.isDeveloper ? ' · اضغط لترى نشاطه' : '')),
                    onTap: cloud.isDeveloper
                        ? () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => StaffActivityScreen(email: d.id)))
                        : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                      onPressed: () => cloud.removeAdmin(d.id),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Shown on the website for features that live in the Android app.
class AppOnlyScreen extends StatelessWidget {
  final String title;
  const AppOnlyScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.android, size: 72, color: kGold),
            const SizedBox(height: 14),
            const Text('هذه الميزة متوفرة في تطبيق أندرويد',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('تحميل التطبيق'),
              onPressed: () => openUrl(context, AppConfig.apkUrl),
            ),
          ],
        ),
      );
}
