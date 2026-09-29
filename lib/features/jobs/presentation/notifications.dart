import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/design.dart';
import '../../../core/motion.dart';
import '../../../core/sanad_refresh.dart';
import '../../../core/web_layout.dart';
import '../data/jobs_store.dart';
import '../domain/job.dart';
import '../domain/job_filters.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    required this.store,
    required this.onJob,
  });
  final JobsStore store;
  final FutureOr<void> Function(Job) onJob;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final scroll = ScrollController();
  final refreshKey = GlobalKey<SanadRefreshState>();
  final feedbackKey = GlobalKey();
  bool refreshing = false, onlyUnread = false;
  final expandedSubmissions = <String>{};
  String? openingId, feedback;
  JobsStore get store => widget.store;

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void message(String value) {
    if (!mounted) return;
    setState(() => feedback = value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && feedbackKey.currentContext != null) {
        Scrollable.ensureVisible(
          feedbackKey.currentContext!,
          alignment: .1,
          duration: motionDuration(context, 280),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> refresh() async => refreshKey.currentState?.refresh();

  Future<String?> refreshResults() async {
    if (refreshing || store.loading) return 'التحديث جارٍ. انتظر اكتماله.';
    if (store.busy) {
      return 'انتظر انتهاء الطلب الحالي، وبعدها حدّث المتابعة.';
    }
    setState(() {
      refreshing = true;
      feedback = null;
    });
    var failedSubmissions = false;
    try {
      await store.refresh();
      for (final submission in store.submissions.toList()) {
        try {
          await store.refreshSubmission(submission);
        } catch (_) {
          failedSubmissions = true;
        }
      }
      if (failedSubmissions) {
        const error = 'تعذّر تحديث بعض إعلاناتك. حاول مجدداً.';
        message(error);
        return store.error ?? error;
      }
      return store.error;
    } catch (_) {
      const error = 'تعذّر تحديث المتابعة. تحقق من الاتصال وحاول مجدداً.';
      message(error);
      return error;
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  Future<void> openJob(Job job) async {
    if (openingId != null || refreshing) return;
    if (!store.discoverableJobs.any((current) => current.id == job.id)) {
      message('هذه الفرصة لم تعد متاحة. حدّث النتائج لتشوف الفرص الحالية.');
      return;
    }
    setState(() => openingId = job.id);
    try {
      final current = await store.verifyAvailableJob(job);
      if (!mounted) return;
      await store.markUpdateRead('job-${current.id}');
      if (!mounted) return;
      await widget.onJob(current);
    } catch (error) {
      message(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => openingId = null);
    }
  }

  List<Job> get matchedJobs {
    final filters = store.savedSearches
        .map(
          (search) => (
            filters: JobFilters.fromJson(
              Map<String, dynamic>.from(search['filters'] as Map),
            ),
            query: search['query'] as String,
          ),
        )
        .toList();
    final matches = store.discoverableJobs
        .where(
          (job) => filters.any(
            (search) => search.filters.matches(job, search.query),
          ),
        )
        .toList();
    matches.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return matches;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final matches = matchedJobs;
      final unread = matches
          .where((job) => !store.isUpdateRead('job-${job.id}'))
          .length;
      final visible = onlyUnread
          ? matches
                .where((job) => !store.isUpdateRead('job-${job.id}'))
                .toList()
          : matches;
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: context.sanad.isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: ReferenceBackdrop(
            child: SafeArea(
              top: false,
              bottom: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: kIsWeb ? WebLayout.readingMax : 720,
                  ),
                  child: SanadRefresh(
                    key: refreshKey,
                    enabled: !refreshing && !store.loading && !store.busy,
                    topInset: MediaQuery.paddingOf(context).top,
                    onRefresh: refreshResults,
                    loadingLabel: 'عم نراجع الفرص وإعلاناتك…',
                    successLabel: store.isDemo
                        ? 'تحدّثت المتابعة التجريبية'
                        : 'صارت متابعتك محدّثة',
                    child: CustomScrollView(
                      controller: scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverAppBar(
                          pinned: true,
                          toolbarHeight: 76,
                          backgroundColor: Colors.transparent,
                          surfaceTintColor: Colors.transparent,
                          elevation: 0,
                          scrolledUnderElevation: 0,
                          flexibleSpace: sanadHeaderFill(context),
                          leadingWidth: 76,
                          leading: Padding(
                            padding: const EdgeInsetsDirectional.only(
                              start: 20,
                            ),
                            child: Center(
                              child: IconButton(
                                tooltip: 'رجوع',
                                onPressed: () => Navigator.pop(context),
                                icon: AppIcon(
                                  CupertinoIcons.chevron_right,
                                  color: context.sanad.ink,
                                ),
                              ),
                            ),
                          ),
                          title: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'على بالك',
                                style: TextStyle(
                                  color: context.sanad.ink,
                                  fontSize: kIsWeb ? 22 : 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'متابعة الفرص والإعلانات',
                                style: TextStyle(
                                  color: context.sanad.secondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          actions: [
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 8),
                              child: IconButton.filledTonal(
                                tooltip: 'تحديث المتابعة',
                                style: IconButton.styleFrom(
                                  backgroundColor: context.sanad.tint,
                                ),
                                onPressed:
                                    refreshing || store.loading || store.busy
                                    ? null
                                    : refresh,
                                icon: refreshing || store.loading
                                    ? const SanadLoader(size: 22)
                                    : AppIcon(
                                        CupertinoIcons.arrow_clockwise,
                                        color: context.sanad.primary,
                                        size: 20,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SanadReveal(child: intro(unread)),
                                if (feedback != null) ...[
                                  const SizedBox(height: 16),
                                  SignalCard(
                                    key: feedbackKey,
                                    feedback!,
                                    onClose: () =>
                                        setState(() => feedback = null),
                                    action: refresh,
                                  ),
                                ],
                                if (store.error != null) ...[
                                  const SizedBox(height: 16),
                                  SignalCard(
                                    store.error!,
                                    action: refresh,
                                    onClose: store.clearError,
                                  ),
                                ],
                                if (store.isOffline) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    'عم تشوف آخر نتائج محفوظة. حدّثها عند عودة الاتصال.',
                                    style: TextStyle(
                                      color: context.sanad.secondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                                if (store.isDemo) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    'نسخة عرض • النتائج والإعلانات تجريبية',
                                    style: TextStyle(
                                      color: context.sanad.secondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 30),
                                if (store.notices.isNotEmpty) ...[
                                  sectionHeading(
                                    'من سند',
                                    'تنبيهات وصلت لهذا الجهاز',
                                    CupertinoIcons.bell,
                                  ),
                                  const SizedBox(height: 12),
                                  for (final notice in store.notices.take(8))
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 10,
                                      ),
                                      child: SignalCard(
                                        notice.text,
                                        actionLabel: 'تمت القراءة',
                                        action: notice.read
                                            ? null
                                            : () => store.markNoticeRead(
                                                notice.id,
                                              ),
                                      ),
                                    ),
                                  const SizedBox(height: 18),
                                ],
                                sectionHeading(
                                  'على قياس بحثك',
                                  'فرص من عمليات البحث اللي حفظتها',
                                  CupertinoIcons.search,
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    modeChip(
                                      'الكل · ${matches.length}',
                                      selected: !onlyUnread,
                                      onTap: () =>
                                          setState(() => onlyUnread = false),
                                    ),
                                    modeChip(
                                      'الجديدة عليك · $unread',
                                      selected: onlyUnread,
                                      onTap: () =>
                                          setState(() => onlyUnread = true),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (visible.isEmpty)
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            sliver: SliverToBoxAdapter(
                              child: SanadReveal(
                                key: ValueKey('empty-$onlyUnread'),
                                child: emptyMatches(matches.isNotEmpty),
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            sliver: SliverList.builder(
                              itemCount: visible.length,
                              itemBuilder: (context, index) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: SanadReveal(
                                  key: ValueKey(
                                    '${visible[index].id}-$onlyUnread',
                                  ),
                                  order: index,
                                  child: jobTile(visible[index]),
                                ),
                              ),
                            ),
                          ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 26, 20, 12),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                sectionHeading(
                                  'من طرفك',
                                  'حالة كل فرصة أضفتها من هذا الجهاز.',
                                  CupertinoIcons.doc_text,
                                ),
                                if (store.submissions.isEmpty) ...[
                                  const SizedBox(height: 14),
                                  panel(
                                    child: Row(
                                      children: [
                                        iconTile(CupertinoIcons.doc_text),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'بعد ما نشرت فرصة',
                                                style: TextStyle(
                                                  color: context.sanad.ink,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'لما تضيف إعلان، بتتابع مراجعته وحالته هون.',
                                                style: TextStyle(
                                                  color:
                                                      context.sanad.secondary,
                                                  fontSize: 12,
                                                  height: 1.7,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          sliver: SliverList.builder(
                            itemCount: store.submissions.length,
                            itemBuilder: (context, index) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: SanadReveal(
                                key: ValueKey(store.submissions[index].job.id),
                                order: index,
                                child: submissionTile(store.submissions[index]),
                              ),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: SafeArea(
                            top: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                26,
                                20,
                                26,
                                28,
                              ),
                              child: Column(
                                children: [
                                  localNotice(),
                                  if (store.lastUpdated != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'آخر تحديث ${time(store.lastUpdated!)}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: context.sanad.secondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget intro(int unread) {
    final colors = context.sanad;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: colors.isDark
              ? [colors.surface, colors.tint, colors.background]
              : const [Color(0xFFFFFFFF), Color(0xFFE7F0FA), Color(0xFFD3E6F7)],
        ),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: colors.isDark ? .18 : .08),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: .14),
                  ),
                ),
                child: AppIcon(
                  CupertinoIcons.bell,
                  color: colors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unread > 0
                          ? 'في فرص ناطرة تشوفها'
                          : 'خطوتك الجاية، على بالك',
                      style: TextStyle(
                        color: colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'نتائج تهمّك، ومتابعة لإعلاناتك بمكان واحد.',
                      style: TextStyle(
                        color: colors.secondary,
                        height: 1.55,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              summaryCount('$unread', 'غير مقروءة'),
              summaryCount('${store.savedSearches.length}', 'بحث محفوظ'),
              summaryCount('${store.submissions.length}', 'من إعلاناتك'),
            ],
          ),
        ],
      ),
    );
  }

  Widget summaryCount(String count, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: context.sanad.surface.withValues(alpha: .88),
      border: Border.all(color: context.sanad.border),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$count  ',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.sanad.primary,
            ),
          ),
          TextSpan(
            text: label,
            style: TextStyle(color: context.sanad.secondary, fontSize: 12),
          ),
        ],
      ),
    ),
  );

  Widget sectionHeading(String title, String subtitle, IconData icon) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      iconTile(icon, size: 42),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: context.sanad.ink,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(
                color: context.sanad.secondary,
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget iconTile(IconData icon, {double size = 48, Color? color}) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: (color ?? context.sanad.primary).withValues(alpha: .08),
      borderRadius: BorderRadius.circular(17),
      border: Border.all(
        color: (color ?? context.sanad.primary).withValues(alpha: .1),
      ),
    ),
    child: AppIcon(icon, color: color ?? context.sanad.primary, size: 22),
  );

  Widget localNotice() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: AppIcon(
          CupertinoIcons.info_circle,
          color: context.sanad.secondary,
          size: 15,
        ),
      ),
      const SizedBox(width: 7),
      Flexible(
        child: Text(
          'المتابعة داخل التطبيق، وتتحدّث بالسحب أو عند فتحه.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.sanad.secondary,
            fontSize: 11,
            height: 1.7,
          ),
        ),
      ),
    ],
  );

  Widget emptyMatches(bool hasMatches) => panel(
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(19),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              colors: context.sanad.isDark
                  ? [context.sanad.tint, context.sanad.surface]
                  : const [Color(0xFFDDECFB), Color(0xFFF0F6FD)],
            ),
            border: Border.all(color: context.sanad.border),
          ),
          child: AppIcon(
            hasMatches ? CupertinoIcons.checkmark_circle : Icons.saved_search,
            color: context.sanad.primary,
            size: 32,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          hasMatches
              ? 'صرت مطّلع على كل الفرص'
              : store.savedSearches.isEmpty
              ? 'خلّي الفرص المناسبة قريبة'
              : 'بحثك محفوظ، ولسّه ناطرين التطابق',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: context.sanad.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hasMatches
              ? 'فيك ترجع لكل النتائج بأي وقت.'
              : store.savedSearches.isEmpty
              ? 'احفظ بحثك من الرئيسية. الفرص اللي بتناسبه بتجتمع هون لحتى تراجعها بسهولة.'
              : 'ما في فرص مطابقة حالياً. حدّث النتائج لاحقاً أو جرّب فلاتر أوسع من الرئيسية.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.sanad.secondary,
            fontSize: 13,
            height: 1.8,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.tonal(
          onPressed: hasMatches
              ? () => setState(() => onlyUnread = false)
              : () => Navigator.pop(context),
          child: Text(hasMatches ? 'عرض كل النتائج' : 'استكشف الفرص'),
        ),
      ],
    ),
  );

  Widget jobTile(Job job) {
    final read = store.isUpdateRead('job-${job.id}');
    final enabled = openingId == null && !refreshing;
    final card = AnimatedContainer(
      duration: motionDuration(context, 240),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.sanad.surface.withValues(alpha: read ? .72 : 1),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: read
              ? context.sanad.border
              : context.sanad.primary.withValues(alpha: .35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              iconTile(
                categoryIcon(job.category),
                color: context.sanad.isDark
                    ? Color.lerp(
                        categoryColor(job.category),
                        context.sanad.primary,
                        .65,
                      )!
                    : categoryColor(job.category),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.company,
                      style: TextStyle(
                        color: context.sanad.secondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      job.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.sanad.ink,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (openingId == job.id)
                const SanadLoader(size: 24)
              else if (!read)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.sanad.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox.square(dimension: 8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              detailBadge(job.locationLabel, CupertinoIcons.location),
              detailBadge(job.workMode, CupertinoIcons.briefcase),
              detailBadge(
                read ? 'اطّلعت عليها' : 'مطابقة لبحثك',
                read ? CupertinoIcons.checkmark : Icons.saved_search,
              ),
            ],
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: read ? 'فرصة مقروءة' : 'فرصة غير مقروءة',
      child: enabled ? Pressable(onTap: () => openJob(job), child: card) : card,
    );
  }

  Widget detailBadge(String text, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: context.sanad.tint.withValues(alpha: .7),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 5),
              child: AppIcon(icon, size: 13, color: context.sanad.primary),
            ),
          ),
          TextSpan(text: text),
        ],
      ),
      style: TextStyle(color: context.sanad.primary, fontSize: 11, height: 1.6),
    ),
  );

  Widget submissionTile(Submission submission) {
    final state = submission.status == 'published' && submission.job.isExpired
        ? 'expired'
        : submission.status;
    final label = switch (state) {
      'published' => 'منشورة',
      'rejected' => 'لم تُقبل',
      'withdrawn' => 'تم سحبها',
      'expired' => 'انتهت مدتها',
      _ => 'قيد المراجعة',
    };
    final icon = switch (state) {
      'published' => CupertinoIcons.checkmark_circle,
      'rejected' => CupertinoIcons.info_circle,
      'withdrawn' => CupertinoIcons.doc_text,
      _ => CupertinoIcons.clock,
    };
    final statusColor = switch (state) {
      'rejected' =>
        context.sanad.isDark
            ? const Color(0xFFFFB4A8)
            : const Color(0xFF934E3F),
      'expired' || 'withdrawn' => context.sanad.secondary,
      _ => context.sanad.primary,
    };
    final description = submission.isDemo
        ? 'إعلان تجريبي محفوظ على جهازك فقط، وغير منشور للعامة.'
        : switch (state) {
            'published' => 'إعلانك ظاهر حالياً للباحثين عن فرصة.',
            'rejected' =>
              'إعلانك غير ظاهر للباحثين. راجع تفاصيله من صفحة إعلاناتك.',
            'withdrawn' => 'سحبت هالإعلان وما عاد ظاهر للباحثين.',
            'expired' => 'خلصت مدة الإعلان وما عاد ظاهر ضمن الفرص المتاحة.',
            _ => 'إعلانك بانتظار المراجعة. بيظهر للباحثين بعد الموافقة.',
          };
    final expanded = expandedSubmissions.contains(submission.job.id);
    return panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              iconTile(icon, color: statusColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      submission.job.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.sanad.ink,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => setState(() {
                if (expanded) {
                  expandedSubmissions.remove(submission.job.id);
                } else {
                  expandedSubmissions.add(submission.job.id);
                }
              }),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(expanded ? 'إخفاء التفاصيل' : 'تفاصيل الحالة'),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: expanded ? .5 : 0,
                    duration: motionDuration(context, 240),
                    curve: Curves.easeOutCubic,
                    child: AppIcon(
                      CupertinoIcons.chevron_down,
                      color: context.sanad.primary,
                      size: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
          MotionSize(
            duration: motionDuration(context, 280),
            curve: Curves.easeOutCubic,
            alignment: AlignmentDirectional.topStart,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          description,
                          style: TextStyle(
                            color: context.sanad.secondary,
                            fontSize: 13,
                            height: 1.8,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'أُضيفت ${time(submission.createdAt)}',
                          style: TextStyle(
                            color: context.sanad.secondary,
                            fontSize: 11,
                          ),
                        ),
                        if (submission.isDemo) ...[
                          const SizedBox(height: 4),
                          Text(
                            'إعلان تجريبي · محفوظ على جهازك',
                            style: TextStyle(
                              color: context.sanad.secondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget modeChip(
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) => Semantics(
    button: true,
    selected: selected,
    child: Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: motionDuration(context, 240),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected
                ? context.sanad.primary.withValues(alpha: .5)
                : context.sanad.border,
          ),
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: selected
                ? const [blue, Color(0xFF3673B4)]
                : context.sanad.isDark
                ? [context.sanad.tint, context.sanad.surface]
                : const [Color(0xFFDEEBF9), Color(0xFFF5F9FE)],
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : context.sanad.primary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );

  Widget panel({required Widget child}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: context.sanad.surface.withValues(alpha: .88),
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: context.sanad.border),
    ),
    child: child,
  );

  String time(DateTime value) {
    final local = value.toLocal();
    return '${local.day}/${local.month}، ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
