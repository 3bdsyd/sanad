import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/design.dart';
import '../../jobs/data/jobs_store.dart';
import '../../jobs/domain/job.dart';
import '../../jobs/presentation/job_details.dart';
import '../data/platform_store.dart';
import '../data/review_moments.dart';
import '../domain/platform_models.dart';
import 'auth_page.dart';
import 'platform_ui.dart';
import 'chat_page.dart';
import 'account_page.dart';

Future<void> openApply(BuildContext context, JobsStore store, Job job) async {
  if (!await ensureAccount(
        context,
        store.platform,
        reason: 'للتقديم على هذه الفرصة',
      ) ||
      !context.mounted) {
    return;
  }
  await platformRoute<void>(context, ApplyPage(store: store, job: job));
}

class ApplyPage extends StatefulWidget {
  const ApplyPage({super.key, required this.store, required this.job});
  final JobsStore store;
  final Job job;
  @override
  State<ApplyPage> createState() => _ApplyPageState();
}

class _ApplyPageState extends State<ApplyPage> {
  final note = TextEditingController();
  bool consent = false, busy = false;
  String? error;
  ApplicationRecord? submitted;
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (!consent) {
      setState(() => error = 'وافق على مشاركة بيانات ملفك مع جهة العمل.');
      return;
    }
    if (note.text.trim().length > 2000) {
      setState(() => error = 'رسالة التقديم طويلة. الحد الأقصى 2000 محرف.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      submitted = await widget.store.platform.apply(
        widget.job,
        note.text.trim(),
      );
      if (mounted) setState(() {});
      await ReviewMoments.completedAction(demo: widget.store.isDemo);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PlatformScaffold(
    title: 'التقديم على الفرصة',
    account: widget.store.platform,
    child: ListenableBuilder(
      listenable: widget.store.platform,
      builder: (context, _) {
        final member = widget.store.platform.user;
        if (submitted != null) {
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              EmptyPanel(
                icon: CupertinoIcons.checkmark_seal,
                title: 'تم إرسال طلبك',
                description:
                    'يمكنك متابعة حالة الطلب من «طلباتي». تظهر أي دعوة للمحادثة في الرسائل.',
                action: SanadPrimaryButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('العودة إلى الفرصة'),
                ),
              ),
              OutlinedButton(
                onPressed: () => platformRoute<void>(
                  context,
                  ApplicationsPage(store: widget.store),
                ),
                child: const Text('متابعة طلباتي'),
              ),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.job.title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.job.company} · ${widget.job.city}',
              style: TextStyle(color: context.sanad.secondary),
            ),
            const SizedBox(height: 24),
            Glass(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ملفك المهني',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Text(member?.name ?? ''),
                  const SizedBox(height: 6),
                  Text(member?.headline ?? ''),
                  if (member != null) ...[
                    const SizedBox(height: 12),
                    ProfessionalSummary(member: member),
                  ],
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => platformRoute<void>(
                      context,
                      ProfilePage(store: widget.store.platform),
                    ),
                    icon: const AppIcon(CupertinoIcons.pencil),
                    label: const Text('مراجعة بيانات الملف'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: note,
              minLines: 4,
              maxLines: 8,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'رسالة إلى جهة العمل (اختياري)',
                hintText: 'اذكر بإيجاز خبرتك وسبب اهتمامك بالفرصة.',
              ),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: consent,
              onChanged: busy
                  ? null
                  : (v) => setState(() => consent = v ?? false),
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'أوافق على مشاركة اسمي وبيانات ملفي ورسالة التقديم مع صاحب الفرصة.',
                style: TextStyle(fontSize: 13),
              ),
            ),
            if (error != null) ...[
              SignalCard(error!),
              const SizedBox(height: 16),
            ],
            SanadPrimaryButton.icon(
              onPressed: busy ? null : send,
              icon: const AppIcon(CupertinoIcons.paperplane),
              label: Text(busy ? 'جارٍ إرسال الطلب…' : 'إرسال الطلب'),
            ),
            const SizedBox(height: 12),
            const Text(
              'التقديم مجاني. لا ترسل أي مبلغ مقابل الحصول على وظيفة.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        );
      },
    ),
  );
}

class ApplicationsPage extends StatefulWidget {
  const ApplicationsPage({super.key, required this.store, this.job});
  final JobsStore store;
  final Job? job;
  @override
  State<ApplicationsPage> createState() => _ApplicationsPageState();
}

class _ApplicationsPageState extends State<ApplicationsPage> {
  final search = TextEditingController();
  String query = '', status = '', sort = 'newest';
  bool filters = false;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  String get path {
    final base = widget.job == null
        ? '/me/applications'
        : '/jobs/${widget.job!.id}/applications';
    final params = <String, String>{
      if (query.isNotEmpty) 'q': query,
      if (status.isNotEmpty) 'status': status,
      if (sort != 'newest') 'sort': sort,
    };
    return params.isEmpty
        ? base
        : '$base?${Uri(queryParameters: params).query}';
  }

  void submitSearch() => setState(() => query = search.text.trim());
  @override
  Widget build(BuildContext context) => PlatformScaffold(
    title: widget.job == null ? 'طلباتي' : 'المتقدمون للفرصة',
    account: widget.store.platform,
    child: PlatformCollection(
      store: widget.store.platform,
      path: path,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.job?.title ?? 'تابع كل خطوة في طلباتك',
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: search,
            maxLength: 200,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => submitSearch(),
            decoration: InputDecoration(
              labelText: widget.job == null
                  ? 'ابحث بعنوان الفرصة أو جهة العمل'
                  : 'ابحث باسم المتقدم أو مهارته',
              counterText: '',
              suffixIcon: IconButton(
                tooltip: 'بحث في الطلبات',
                onPressed: submitSearch,
                icon: const AppIcon(CupertinoIcons.search),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SanadActions(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => filters = !filters),
                icon: const AppIcon(CupertinoIcons.slider_horizontal_3),
                label: Text(
                  status.isEmpty ? 'تصفية الطلبات' : applicationLabels[status]!,
                ),
              ),
              if (query.isNotEmpty || status.isNotEmpty || sort != 'newest')
                TextButton(
                  onPressed: () => setState(() {
                    search.clear();
                    query = '';
                    status = '';
                    sort = 'newest';
                  }),
                  child: const Text('إعادة ضبط'),
                ),
            ],
          ),
          if (filters) ...[
            const SizedBox(height: 12),
            const Text(
              'حالة الطلب',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final entry in {'': 'الكل', ...applicationLabels}.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: status == entry.key,
                    onSelected: (_) => setState(() => status = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'ترتيب الطلبات',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final entry in {
                  'newest': 'الأحدث أولاً',
                  'oldest': 'الأقدم أولاً',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: sort == entry.key,
                    onSelected: (_) => setState(() => sort = entry.key),
                  ),
              ],
            ),
          ],
        ],
      ),
      empty: EmptyPanel(
        icon: CupertinoIcons.doc_text_search,
        title: query.isNotEmpty || status.isNotEmpty
            ? 'لا توجد طلبات مطابقة'
            : widget.job == null
            ? 'ابدأ بخطوتك التالية'
            : 'بانتظار أول طلب',
        description: query.isNotEmpty || status.isNotEmpty
            ? 'جرّب بحثاً آخر أو أعد ضبط التصفية لعرض بقية الطلبات.'
            : widget.job == null
            ? 'عندما تتقدم إلى فرصة، ستجدها هنا مع حالتها وآخر تحديث من جهة العمل.'
            : 'بعد نشر فرصتك، ستظهر طلبات المتقدمين هنا لتراجعها وتبدأ التواصل.',
      ),
      builder: (context, row) => _ApplicationCard(
        store: widget.store,
        record: ApplicationRecord(row),
        employer: widget.job != null,
      ),
    ),
  );
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({
    required this.store,
    required this.record,
    required this.employer,
  });
  final JobsStore store;
  final ApplicationRecord record;
  final bool employer;
  @override
  Widget build(BuildContext context) => Pressable(
    onTap: () => platformRoute<void>(
      context,
      ApplicationDetailsPage(store: store, initial: record, employer: employer),
    ),
    child: Glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            employer ? record.applicant.name : record.job.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            employer ? record.applicant.headline : record.job.company,
            style: TextStyle(color: context.sanad.secondary),
          ),
          const SizedBox(height: 16),
          StatusChip(record.status),
          if (record.createdAt.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'تاريخ التقديم: ${record.createdAt.split('T').first}',
              style: TextStyle(color: context.sanad.secondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  employer ? 'مراجعة الملف والطلب' : 'عرض تفاصيل الطلب',
                  style: TextStyle(color: context.sanad.primary),
                ),
              ),
              const AppIcon(CupertinoIcons.chevron_back, size: 16),
            ],
          ),
        ],
      ),
    ),
  );
}

class ApplicationDetailsPage extends StatefulWidget {
  const ApplicationDetailsPage({
    super.key,
    required this.store,
    required this.initial,
    this.employer = false,
  });
  final JobsStore store;
  final ApplicationRecord initial;
  final bool employer;
  @override
  State<ApplicationDetailsPage> createState() => _ApplicationDetailsPageState();
}

class _ApplicationDetailsPageState extends State<ApplicationDetailsPage> {
  late ApplicationRecord record = widget.initial;
  bool busy = false, confirmWithdraw = false, chooseStatus = false;
  String? error;
  PlatformStore get store => widget.store.platform;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final data = await store.load('/applications/${record.id}');
      if (mounted && data['data'] is Map) {
        setState(() => record = ApplicationRecord(object(data['data'])));
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> action(String status) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await store.applicationAction(
        record.id,
        status,
        expectedVersion: record.version,
      );
      record = ApplicationRecord({
        ...record.data,
        'status': status,
        'version': record.version + 1,
      });
      if (!store.demo) await refresh();
      if (mounted) {
        setState(() {
          chooseStatus = false;
          confirmWithdraw = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chat() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final thread = await store.startConversation(record.id);
      if (mounted) {
        await platformRoute<void>(
          context,
          ChatPage(store: store, conversation: thread),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PlatformScaffold(
    title: 'تفاصيل الطلب',
    account: store,
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          record.job.title,
          style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(record.job.company),
        const SizedBox(height: 20),
        StatusChip(record.status),
        const SizedBox(height: 24),
        if (widget.employer) ...[
          Glass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.applicant.name,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(record.applicant.headline),
                const SizedBox(height: 12),
                ProfessionalSummary(member: record.applicant),
                if (record.applicant.email.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    record.applicant.email,
                    textDirection: TextDirection.ltr,
                  ),
                ],
                if (record.applicant.phone.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    record.applicant.phone,
                    textDirection: TextDirection.ltr,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (record.note.isNotEmpty) ...[
          const Text(
            'رسالة التقديم',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(record.note, style: const TextStyle(height: 1.8)),
          const SizedBox(height: 24),
        ],
        const Text(
          'مسار الطلب',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (record.history.isEmpty)
          Text(applicationLabels[record.status] ?? record.status),
        for (final item in record.history)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppIcon(
                  CupertinoIcons.checkmark_circle,
                  color: context.sanad.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        applicationLabels[textOf(item['status'])] ??
                            'تحديث الطلب',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        textOf(
                          item['at'],
                        ).replaceFirst('T', ' ').split('.').first,
                        style: TextStyle(
                          color: context.sanad.secondary,
                          fontSize: 12,
                        ),
                      ),
                      if (textOf(item['note']).isNotEmpty)
                        Text(textOf(item['note'])),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (error != null) ...[
          SignalCard(error!, action: refresh, actionLabel: 'تحديث الحالة'),
          const SizedBox(height: 16),
        ],
        SanadActions(
          children: [
            if ((widget.employer && record.status != 'withdrawn') ||
                record.conversationId.isNotEmpty)
              SanadPrimaryButton.icon(
                onPressed: busy ? null : chat,
                icon: const AppIcon(CupertinoIcons.chat_bubble_2),
                label: Text(
                  widget.employer ? 'مراسلة المتقدم' : 'فتح المحادثة',
                ),
              ),
            if (widget.employer &&
                !['withdrawn', 'accepted', 'rejected'].contains(record.status))
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => setState(() => chooseStatus = !chooseStatus),
                child: const Text('تحديث حالة الطلب'),
              ),
            if (!widget.employer &&
                !['withdrawn', 'accepted', 'rejected'].contains(record.status))
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() => confirmWithdraw = !confirmWithdraw),
                child: const Text('سحب الطلب'),
              ),
            TextButton(
              onPressed: () => platformRoute<void>(
                context,
                JobDetails(job: record.job, store: widget.store),
              ),
              child: const Text('عرض الفرصة'),
            ),
          ],
        ),
        if (chooseStatus) ...[
          const SizedBox(height: 16),
          Glass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'اختر الحالة الجديدة',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                for (final state
                    in applicationTransitions[record.status] ?? <String>[])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OutlinedButton(
                      onPressed: busy ? null : () => action(state),
                      child: Text(applicationLabels[state]!),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (confirmWithdraw) ...[
          const SizedBox(height: 16),
          SignalCard(
            'سيُبلّغ صاحب الفرصة بسحب طلبك. هل تريد المتابعة؟',
            action: busy ? null : () => action('withdrawn'),
            actionLabel: 'تأكيد سحب الطلب',
          ),
        ],
      ],
    ),
  );
}
