import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/design.dart';
import '../../jobs/data/jobs_store.dart';
import '../../jobs/domain/job.dart';
import '../../jobs/presentation/post_job.dart';
import 'auth_page.dart';
import 'applications_page.dart';
import 'chat_page.dart';
import 'platform_ui.dart';

class PublisherPanel extends StatelessWidget {
  const PublisherPanel({super.key, required this.store});
  final JobsStore store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store.platform,
    builder: (context, _) {
      final actionHeader = SanadActionHeader(
        minimumRowWidth: 280,
        title: const Text(
          'إعلاناتك',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        actions: [
          SanadPrimaryButton.icon(
            onPressed: () => showPostJob(context, store),
            icon: const AppIcon(CupertinoIcons.plus, size: 19),
            label: const Text('أضف فرصة عمل'),
          ),
        ],
      );
      final header = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          actionHeader,
          const SizedBox(height: 12),
          SanadActions(
            children: [
              TextButton.icon(
                onPressed: () async {
                  if (await ensureAccount(context, store.platform) &&
                      context.mounted) {
                    await platformRoute<void>(
                      context,
                      ApplicationsPage(store: store),
                    );
                  }
                },
                icon: const AppIcon(CupertinoIcons.doc_text, size: 18),
                label: const Text('طلباتي'),
              ),
              TextButton.icon(
                onPressed: () async {
                  if (await ensureAccount(context, store.platform) &&
                      context.mounted) {
                    await platformRoute<void>(
                      context,
                      ConversationsPage(store: store.platform),
                    );
                  }
                },
                icon: const AppIcon(CupertinoIcons.chat_bubble_2, size: 18),
                label: const Text('الرسائل'),
              ),
            ],
          ),
        ],
      );
      if (!store.platform.signedIn) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            header,
            const SizedBox(height: 32),
            EmptyPanel(
              icon: CupertinoIcons.briefcase,
              title: 'اعثر على الشخص المناسب لفرصتك',
              description:
                  'أضف تفاصيل واضحة، وتابع مراجعة إعلانك، ثم راجع المتقدمين وتواصل معهم من مكان واحد.',
              action: OutlinedButton(
                onPressed: () => ensureAccount(
                  context,
                  store.platform,
                  reason: 'لإدارة إعلاناتك',
                ),
                child: const Text('تسجيل الدخول أو إنشاء حساب'),
              ),
            ),
            const SizedBox(height: 24),
            const _PostingSteps(),
          ],
        );
      }
      return PlatformCollection(
        store: store.platform,
        path: '/me/jobs',
        header: header,
        empty: Column(
          children: [
            const EmptyPanel(
              icon: CupertinoIcons.briefcase,
              title: 'فرصتك الأولى تبدأ هنا',
              description:
                  'انشر فرصة بتفاصيل واضحة. سنراجعها قبل ظهورها، وستتابع الطلبات والمحادثات من حسابك.',
            ),
            const _PostingSteps(),
          ],
        ),
        builder: (context, data) => OwnedJobCard(
          store: store,
          job: Job.fromApi(data),
          applicants: (data['applications_count'] as num?)?.toInt() ?? 0,
        ),
      );
    },
  );
}

class _PostingSteps extends StatelessWidget {
  const _PostingSteps();
  @override
  Widget build(BuildContext context) => Glass(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'من الإعلان إلى التواصل',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 18),
        for (final (index, title, text) in [
          (1, 'أضف الفرصة', 'المسمّى والتفاصيل ومكان العمل.'),
          (2, 'مراجعة ثم نشر', 'تصلك نتيجة المراجعة في حسابك.'),
          (3, 'راجع الطلبات', 'تابع المتقدمين وابدأ المحادثة.'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: context.sanad.tint,
                  child: Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.sanad.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        text,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.sanad.secondary,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class OwnedJobCard extends StatelessWidget {
  const OwnedJobCard({
    super.key,
    required this.store,
    required this.job,
    this.applicants = 0,
  });
  final JobsStore store;
  final Job job;
  final int applicants;
  @override
  Widget build(BuildContext context) => Glass(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusChip(job.status, posting: true),
        const SizedBox(height: 14),
        Text(
          job.title,
          textDirection: textDirectionFor(job.title),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          job.company,
          textDirection: textDirectionFor(job.company),
          style: TextStyle(color: context.sanad.secondary),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            AppTag('${job.country} · ${job.city}'),
            AppTag(job.workType),
            if (job.salaryMin != null || job.salaryMax != null)
              AppTag(job.salaryLabel),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          job.description.isEmpty
              ? 'افتح الإعلان للاطلاع على بياناته وحالته.'
              : job.description,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, height: 1.8),
        ),
        const SizedBox(height: 16),
        SanadActions(
          children: [
            OutlinedButton.icon(
              onPressed: () => platformRoute<void>(
                context,
                OwnedJobDetailsPage(store: store, job: job),
              ),
              icon: const AppIcon(CupertinoIcons.doc_text, size: 18),
              label: const Text('تفاصيل الإعلان'),
            ),
            if (job.status == 'published' || applicants > 0)
              TextButton.icon(
                onPressed: () => platformRoute<void>(
                  context,
                  ApplicationsPage(store: store, job: job),
                ),
                icon: const AppIcon(CupertinoIcons.person_2, size: 18),
                label: Text('المتقدمون ($applicants)'),
              ),
          ],
        ),
      ],
    ),
  );
}

class OwnedJobDetailsPage extends StatefulWidget {
  const OwnedJobDetailsPage({
    super.key,
    required this.store,
    required this.job,
  });
  final JobsStore store;
  final Job job;
  @override
  State<OwnedJobDetailsPage> createState() => _OwnedJobDetailsPageState();
}

class _OwnedJobDetailsPageState extends State<OwnedJobDetailsPage> {
  bool confirm = false, busy = false, withdrawn = false;
  String? error;
  Future<void> withdraw() async {
    setState(() => busy = true);
    try {
      await widget.store.platform.withdrawJob(widget.job.id);
      if (mounted) {
        setState(() {
          withdrawn = true;
          confirm = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final j = widget.job;
    return PlatformScaffold(
      title: 'تفاصيل إعلانك',
      account: widget.store.platform,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          StatusChip(withdrawn ? 'withdrawn' : j.status, posting: true),
          const SizedBox(height: 20),
          Text(
            j.title,
            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(j.company),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              AppTag('${j.country} · ${j.city}'),
              AppTag(j.workType),
              AppTag(j.workMode),
              AppTag(j.salaryLabel),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'وصف الفرصة',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(j.description, style: const TextStyle(height: 1.9)),
          if (j.requirements.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              'المتطلبات',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            for (final item in j.requirements)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('• $item', style: const TextStyle(height: 1.8)),
              ),
          ],
          const SizedBox(height: 24),
          const Text(
            'بيانات التواصل',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (j.phone.isNotEmpty)
            SelectableText(j.phone, textDirection: TextDirection.ltr),
          if (j.email.isNotEmpty)
            SelectableText(j.email, textDirection: TextDirection.ltr),
          if (j.companyWebsite.isNotEmpty)
            SelectableText(j.companyWebsite, textDirection: TextDirection.ltr),
          const SizedBox(height: 24),
          if (j.status == 'pending')
            const SignalCard(
              'إعلانك قيد المراجعة ولا يظهر للعامة بعد. ستصلك نتيجة المراجعة إلى حسابك.',
            ),
          if (j.rejectionReason.isNotEmpty) SignalCard(j.rejectionReason),
          if (error != null) ...[
            const SizedBox(height: 16),
            SignalCard(error!),
          ],
          const SizedBox(height: 20),
          if (!withdrawn && j.status == 'published')
            SanadPrimaryButton.icon(
              onPressed: () => platformRoute<void>(
                context,
                ApplicationsPage(store: widget.store, job: j),
              ),
              icon: const AppIcon(CupertinoIcons.person_2),
              label: const Text('مراجعة المتقدمين'),
            ),
          const SizedBox(height: 12),
          if (!withdrawn && !['withdrawn', 'expired'].contains(j.status))
            TextButton(
              onPressed: busy ? null : () => setState(() => confirm = !confirm),
              child: const Text('سحب الإعلان'),
            ),
          if (confirm)
            SignalCard(
              'سيتوقف ظهور الإعلان واستقبال طلبات جديدة. تبقى الطلبات السابقة متاحة للمراجعة.',
              action: busy ? null : withdraw,
              actionLabel: 'تأكيد السحب',
            ),
        ],
      ),
    );
  }
}
