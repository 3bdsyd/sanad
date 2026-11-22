import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/design.dart';
import '../../../core/motion.dart';
import '../../../core/push_notifications.dart';
import '../../../core/sanad_refresh.dart';
import '../../ads/data/banner_ad_session.dart';
import '../../ads/domain/ad_config.dart';
import '../../ads/presentation/screen_banner.dart';
import '../data/jobs_store.dart';
import '../domain/job.dart';
import '../../platform/presentation/notification_destination.dart';
import '../../platform/domain/platform_models.dart' show object;

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    required this.store,
    required this.onJob,
    this.initialSection = 0,
    this.initialNewOnly = false,
    this.focusJobIds,
    this.bannerSession,
  });
  final BannerAdSession? bannerSession;
  final int initialSection;
  final bool initialNewOnly;
  final Set<String>? focusJobIds;
  final JobsStore store;
  final FutureOr<void> Function(Job) onJob;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final scroll = ScrollController();
  final refreshKey = GlobalKey<SanadRefreshState>();
  final feedbackKey = GlobalKey();
  bool refreshing = false;
  late bool onlyUnread = widget.initialNewOnly;
  late int section = widget.initialSection;
  bool showPushSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(store.refreshSavedSearchMatches());
    });
  }

  final expandedSubmissions = <String>{};
  final confirmingWithdrawals = <String>{};
  final withdrawingSubmissions = <String>{};
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

  Future<void> withdrawSubmission(Submission submission) async {
    final id = submission.id;
    if (!withdrawingSubmissions.add(id)) return;
    setState(() {});
    try {
      await store.withdraw(submission);
      if (mounted) {
        setState(() {
          confirmingWithdrawals.remove(id);
          expandedSubmissions.remove(id);
          feedback = 'تم سحب الإعلان وحذفه من قائمة إعلاناتك.';
        });
      }
    } catch (_) {
      message('تعذّر سحب الإعلان. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => withdrawingSubmissions.remove(id));
    }
  }

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
      await store.refreshSavedSearchMatches(force: true);
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
    if (!store.savedSearchMatches.any((current) => current.id == job.id)) {
      message('لم تعد هذه الفرصة متاحة. حدّث النتائج لعرض الفرص الحالية.');
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

  List<Job> get matchedJobs => store.savedSearchMatches;

  Widget _pushStatus() => ListenableBuilder(
    listenable: store.push,
    builder: (context, _) {
      final status = store.push.state;
      if (status == PushState.ready) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(switch (status) {
              PushState.denied =>
                'إشعارات الهاتف معطّلة. يمكنك تفعيلها من إعدادات الجهاز > سند > الإشعارات.',
              PushState.failed =>
                'تعذّر تفعيل إشعارات الهاتف. تحقق من الاتصال وأعد المحاولة.',
              PushState.connecting => 'جارٍ إعداد إشعارات الهاتف…',
              _ => 'فعّل إشعارات الهاتف لاستلام تحديثات الفرص والإعلانات.',
            }, textAlign: TextAlign.center),
            if (status != PushState.connecting)
              TextButton(
                onPressed: () => store.push.start(requestAgain: true),
                child: const Text('تفعيل الإشعارات'),
              ),
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final matches = matchedJobs;
      final unread = matches
          .where((job) => store.isNewSavedMatch(job.id))
          .length;
      final visible = matches
          .where(
            (job) =>
                (!onlyUnread || store.isNewSavedMatch(job.id)) &&
                (!onlyUnread ||
                    widget.focusJobIds == null ||
                    widget.focusJobIds!.contains(job.id)),
          )
          .toList();
      final hasContent = switch (section) {
        0 => visible.isNotEmpty,
        1 => store.submissions.isNotEmpty,
        _ => store.notices.isNotEmpty,
      };
      final labels = ['الفرص المطابقة', 'إعلاناتي', 'تنبيهات سند'];
      final counts = [unread, store.submissions.length, store.noticesUnread];
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: sanadSystemBars(context.sanad),
        child: ReferenceBackdrop(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: const Text('الإشعارات'),
              flexibleSpace: sanadHeaderFill(context, blur: false),
              actions: [
                IconButton(
                  tooltip: 'تحديث الإشعارات',
                  onPressed: refreshing || store.loading || store.busy
                      ? null
                      : refresh,
                  icon: refreshing
                      ? const SanadLoader(size: 22)
                      : const AppIcon(CupertinoIcons.arrow_clockwise, size: 21),
                ),
                const SizedBox(width: 12),
              ],
            ),
            bottomNavigationBar:
                AdConfig.supported && !store.isDemo && hasContent
                ? SafeArea(
                    top: false,
                    child: ScreenBanner(
                      placement: 'notifications_banner',
                      contextKey: 'notifications',
                      session: widget.bannerSession,
                    ),
                  )
                : null,
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: SanadRefresh(
                  key: refreshKey,
                  enabled: !refreshing && !store.loading && !store.busy,
                  onRefresh: refreshResults,
                  loadingLabel: 'جارٍ تحديث الإشعارات…',
                  successLabel: 'تم تحديث الإشعارات',
                  child: CustomScrollView(
                    controller: scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.all(20),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SanadActions(
                                children: [
                                  for (
                                    var index = 0;
                                    index < labels.length;
                                    index++
                                  )
                                    modeChip(
                                      '${labels[index]}${counts[index] > 0 ? ' · ${counts[index]}' : ''}',
                                      selected: section == index,
                                      onTap: () =>
                                          setState(() => section = index),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Text(switch (section) {
                                0 =>
                                  'أحدث فرص العمل التي تطابق عمليات البحث المحفوظة.',
                                1 =>
                                  'حالة مراجعة ونشر الإعلانات التي أضفتها من هذا الجهاز.',
                                _ => 'الإشعارات والتحديثات الواردة من سند.',
                              }, style: TextStyle(color: context.sanad.secondary)),
                              if (feedback != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: SignalCard(
                                    key: feedbackKey,
                                    feedback!,
                                    onClose: () =>
                                        setState(() => feedback = null),
                                  ),
                                ),
                              if (store.error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: SignalCard(
                                    store.error!,
                                    action: refresh,
                                    onClose: store.clearError,
                                  ),
                                ),
                              if (section == 0) ...[
                                const SizedBox(height: 16),
                                SanadActions(
                                  children: [
                                    modeChip(
                                      'الجميع',
                                      selected: !onlyUnread,
                                      onTap: () =>
                                          setState(() => onlyUnread = false),
                                    ),
                                    modeChip(
                                      'الجديدة · $unread',
                                      selected: onlyUnread,
                                      onTap: () =>
                                          setState(() => onlyUnread = true),
                                    ),
                                  ],
                                ),
                                if (store.savedMatchesLoading)
                                  const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: SanadLoader(size: 28),
                                  ),
                                if (store.savedMatchesError != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: SignalCard(
                                      store.savedMatchesError!,
                                      action: () =>
                                          store.refreshSavedSearchMatches(
                                            force: true,
                                          ),
                                    ),
                                  ),
                                const SizedBox(height: 16),
                                if (visible.isEmpty)
                                  emptyMatches(matches.isNotEmpty),
                              ],
                              if (section == 1 && store.submissions.isEmpty)
                                panel(
                                  child: const Text(
                                    'لم تضف إعلانات بعد. يمكنك إضافة فرصة من القسم المخصص، ثم متابعة حالتها هنا.',
                                  ),
                                ),
                              if (section == 2 && store.notices.isEmpty)
                                panel(
                                  child: const Text(
                                    'لا توجد تنبيهات من سند حالياً.',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (section == 0)
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          sliver: SliverList.builder(
                            itemCount: visible.length,
                            itemBuilder: (context, index) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: jobTile(visible[index]),
                            ),
                          ),
                        ),
                      if (section == 1)
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          sliver: SliverList.builder(
                            itemCount: store.submissions.length,
                            itemBuilder: (context, index) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: submissionTile(store.submissions[index]),
                            ),
                          ),
                        ),
                      if (section == 2)
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          sliver: SliverList.builder(
                            itemCount: store.notices.length,
                            itemBuilder: (context, index) {
                              final notice = store.notices[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: SignalCard(
                                  notice.text,
                                  actionLabel: notice.payload.isEmpty
                                      ? 'تحديد كمقروء'
                                      : 'عرض التحديث',
                                  action: notice.payload.isNotEmpty
                                      ? () async {
                                          try {
                                            await store.markNoticeRead(
                                              notice.id,
                                            );
                                            if (context.mounted) {
                                              await openNotificationDestination(
                                                context,
                                                store,
                                                notice.payload,
                                              );
                                            }
                                          } catch (e) {
                                            message(e.toString());
                                          }
                                        }
                                      : notice.read
                                      ? null
                                      : () => store.markNoticeRead(notice.id),
                                ),
                              );
                            },
                          ),
                        ),
                      if (store.accountsEnabled &&
                          store.platform.signedIn &&
                          object(
                                store.platform.snapshot(switch (section) {
                                  0 => '/me/saved-search-matches',
                                  1 => '/me/jobs',
                                  _ => '/me/notifications',
                                })['meta'],
                              )['next_cursor'] !=
                              null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: OutlinedButton(
                              onPressed: refreshing
                                  ? null
                                  : () async {
                                      setState(() => refreshing = true);
                                      try {
                                        await store.platform.loadMore(
                                          switch (section) {
                                            0 => '/me/saved-search-matches',
                                            1 => '/me/jobs',
                                            _ => '/me/notifications',
                                          },
                                        );
                                      } catch (e) {
                                        message(e.toString());
                                      } finally {
                                        if (mounted) {
                                          setState(() => refreshing = false);
                                        }
                                      }
                                    },
                              child: const Text('عرض المزيد'),
                            ),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: SafeArea(
                          top: false,
                          minimum: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              if (!kIsWeb)
                                ListTile(
                                  title: const Text('إعدادات إشعارات الهاتف'),
                                  leading: const AppIcon(
                                    CupertinoIcons.bell,
                                    size: 20,
                                  ),
                                  trailing: AppIcon(
                                    showPushSettings
                                        ? CupertinoIcons.chevron_up
                                        : CupertinoIcons.chevron_down,
                                    size: 16,
                                  ),
                                  onTap: () => setState(
                                    () => showPushSettings = !showPushSettings,
                                  ),
                                ),
                              if (showPushSettings) _pushStatus(),
                              localNotice(),
                            ],
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
      );
    },
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
          'تُحدّث المتابعة داخل التطبيق عند السحب أو فتح الصفحة.',
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
              ? 'اطّلعت على جميع الفرص الجديدة'
              : store.savedSearches.isEmpty
              ? 'لا توجد عمليات بحث محفوظة'
              : 'لا توجد فرص مطابقة حالياً',
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
              ? 'يمكنك العودة إلى جميع النتائج في أي وقت.'
              : store.savedSearches.isEmpty
              ? 'احفظ بحثك من الصفحة الرئيسية، وستظهر هنا الفرص المطابقة لتراجعها بسهولة.'
              : 'لا توجد فرص مطابقة حالياً. حدّث النتائج لاحقاً أو استخدم عوامل تصفية أوسع من الصفحة الرئيسية.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.sanad.secondary,
            fontSize: 13,
            height: 1.8,
          ),
        ),
        const SizedBox(height: 20),
        SanadPrimaryButton.tonal(
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
            'withdrawn' => 'سُحب هذا الإعلان ولم يعد ظاهراً للباحثين.',
            'expired' => 'انتهت مدة الإعلان ولم يعد ضمن الفرص المتاحة.',
            _ => 'إعلانك بانتظار المراجعة. سيظهر للباحثين عن عمل بعد الموافقة.',
          };
    final expanded = expandedSubmissions.contains(submission.job.id);
    final confirming = confirmingWithdrawals.contains(submission.id);
    final withdrawing = withdrawingSubmissions.contains(submission.id);
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
          if (!submission.isDemo && state != 'withdrawn') ...[
            const SizedBox(height: 8),
            if (!confirming)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: withdrawing
                      ? null
                      : () => setState(
                          () => confirmingWithdrawals.add(submission.id),
                        ),
                  child: const Text('سحب الإعلان'),
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'سيُحذف الإعلان من نتائج البحث وإعلاناتك على هذا الجهاز. لا يمكن التراجع عن هذه الخطوة.',
                    style: TextStyle(fontSize: 12, height: 1.7),
                  ),
                  const SizedBox(height: 4),
                  SanadActions(
                    children: [
                      TextButton(
                        onPressed: withdrawing
                            ? null
                            : () => setState(
                                () =>
                                    confirmingWithdrawals.remove(submission.id),
                              ),
                        child: const Text('إلغاء'),
                      ),
                      TextButton(
                        onPressed: withdrawing
                            ? null
                            : () => withdrawSubmission(submission),
                        child: Text(
                          withdrawing ? 'جارٍ السحب…' : 'تأكيد السحب',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
          ],
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
