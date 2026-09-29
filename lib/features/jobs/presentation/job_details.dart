import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/app_links.dart';
import '../../../core/design.dart';
import '../../../core/motion.dart';
import '../../../core/native_bridge.dart';
import '../../../core/adaptive_text_field.dart';
import '../../../core/web_layout.dart';
import '../domain/job.dart';
import '../domain/company_website.dart';
import '../data/jobs_store.dart';

class JobDetails extends StatefulWidget {
  const JobDetails({
    super.key,
    required this.job,
    required this.store,
    this.heroTag,
  });
  final Job job;
  final JobsStore store;
  final String? heroTag;

  @override
  State<JobDetails> createState() => _JobDetailsState();
}

class _JobDetailsState extends State<JobDetails> {
  final scroll = ScrollController();
  final feedbackKey = GlobalKey();
  final reportKey = GlobalKey();
  final hideKey = GlobalKey();
  final websiteKey = GlobalKey();
  bool contacting = false, saving = false, sharing = false, compact = false;
  bool reporting = false, hiding = false, reportOpen = false, hideOpen = false;
  bool openingWebsite = false;
  String? websiteFeedback;
  late final bool initiallyPublic;
  String? feedback, reportReason, reportFeedback;

  Job get job => widget.store.jobs.firstWhere(
    (candidate) => candidate.id == widget.job.id,
    orElse: () => widget.job,
  );
  bool get available =>
      job.isAvailable &&
      (!initiallyPublic ||
          widget.store.jobs.any((candidate) => candidate.id == job.id));

  @override
  void initState() {
    super.initState();
    initiallyPublic = widget.store.jobs.any((item) => item.id == widget.job.id);
    scroll.addListener(onScroll);
  }

  void onScroll() {
    final next = scroll.offset > 170;
    if (next != compact) setState(() => compact = next);
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void reveal(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || key.currentContext == null) return;
      Scrollable.ensureVisible(
        key.currentContext!,
        alignment: .12,
        duration: motionDuration(context, 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void message(String text) {
    if (!mounted) return;
    setState(() => feedback = text);
    reveal(feedbackKey);
  }

  Future<void> revealPanel(GlobalKey key) async {
    final duration = motionDuration(context, 230);
    if (duration != Duration.zero) await Future<void>.delayed(duration);
    if (mounted) reveal(key);
  }

  Uri? whatsappUri(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    return Uri.https('wa.me', '/$digits');
  }

  Future<void> contact(bool email) async {
    if (contacting) return;
    if (job.isDemo || widget.store.isDemo) {
      message('هذه فرصة توضيحية. التواصل مع الشركات يتاح بعد ربط الخدمة.');
      return;
    }
    if (!available) {
      message('هذه الفرصة لم تعد متاحة. ارجع للفرص لتشوف خيارات جديدة.');
      return;
    }
    setState(() => contacting = true);
    try {
      final current = await widget.store.verifyAvailableJob(job);
      if (!mounted) return;
      final raw = email ? current.email : current.phone;
      if (raw.isEmpty) {
        message('وسيلة التواصل لم تعد متاحة.');
        return;
      }
      final uri = email
          ? Uri(
              scheme: 'mailto',
              path: raw,
              query:
                  'subject=${Uri.encodeComponent('بخصوص فرصة ${current.title}')}',
            )
          : whatsappUri(raw);
      if (uri == null) return;
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        // Silent: do not show a failure panel for WhatsApp or email.
      }
    } catch (error) {
      message(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => contacting = false);
    }
  }

  Future<void> openCompanyWebsite() async {
    if (openingWebsite) return;
    void websiteMessage(String text) {
      if (!mounted) return;
      setState(() => websiteFeedback = text);
      reveal(websiteKey);
    }

    if (job.isDemo || widget.store.isDemo) {
      websiteMessage('هذه فرصة توضيحية. رابط الجهة ما بينفتح بوضع العرض.');
      return;
    }
    if (!available) {
      websiteMessage('هذه الفرصة لم تعد متاحة.');
      return;
    }
    setState(() {
      openingWebsite = true;
      websiteFeedback = null;
    });
    try {
      final current = await widget.store.verifyAvailableJob(job);
      if (!mounted) return;
      final website = normalizeCompanyWebsite(current.companyWebsite);
      if (website == null || website.isEmpty) {
        websiteMessage('رابط الجهة لم يعد متاحاً.');
        return;
      }
      final opened = await launchUrl(
        Uri.parse(website),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) websiteMessage('تعذّر فتح الرابط. جرّب مرة ثانية.');
    } catch (error) {
      websiteMessage(
        error is JobsException
            ? error.toString().replaceFirst('Exception: ', '')
            : 'تعذّر فتح رابط الجهة. جرّب مرة ثانية.',
      );
    } finally {
      if (mounted) setState(() => openingWebsite = false);
    }
  }

  Future<void> sendReport() async {
    if (reporting || reportReason == null) return;
    setState(() {
      reporting = true;
      reportFeedback = null;
    });
    try {
      await widget.store.report(job, reportReason!);
      if (!mounted) return;
      setState(() {
        reportOpen = false;
        reportFeedback = job.isDemo || widget.store.isDemo
            ? 'تمت تجربة الإبلاغ محلياً، ولم يُرسل بلاغ فعلي.'
            : 'وصل بلاغك للمراجعة. شكراً لمساعدتك.';
      });
    } catch (error) {
      if (mounted) {
        setState(() => reportFeedback = error.toString());
      }
    } finally {
      if (mounted) setState(() => reporting = false);
    }
  }

  Future<void> hideEmployer() async {
    if (hiding) return;
    setState(() => hiding = true);
    try {
      await widget.store.hideEmployer(job);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      message('تعذّر حفظ التغيير. حاول مرة ثانية.');
    } finally {
      if (mounted) setState(() => hiding = false);
    }
  }

  Future<void> save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await widget.store.toggleSaved(job.id);
      await NativeBridge.selectionHaptic();
      if (mounted && widget.store.error != null) {
        message(widget.store.error!);
      }
    } catch (_) {
      message('تعذّر حفظ التغيير. حاول مرة ثانية.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> shareJob() async {
    if (sharing) return;
    if (job.isDemo || widget.store.isDemo) {
      message('هالفرصة تجريبية. المشاركة بتتاح بعد ربط الخدمة.');
      return;
    }
    if (!available) {
      message('هالفرصة ما عادت متاحة للمشاركة.');
      return;
    }
    setState(() => sharing = true);
    try {
      final link = AppLinks.jobShareUri(job.id);
      final text = [
        job.title,
        '${job.company} · ${job.locationLabel}',
        '${job.workType} · ${job.workMode}',
        if (link != null) ...['', 'شوف الفرصة على سند:', link.toString()],
        if (link == null) ...['', 'فرصة من تطبيق سند'],
      ].join('\n');
      await SharePlus.instance.share(
        ShareParams(text: text, subject: job.title, title: 'مشاركة فرصة'),
      );
      await NativeBridge.selectionHaptic();
    } catch (_) {
      message('تعذّرت المشاركة. جرّب مرة ثانية.');
    } finally {
      if (mounted) setState(() => sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final webWide = kIsWeb && WebLayout.of(context) != WebBreakpoint.compact;
      final contentMax = kIsWeb ? WebLayout.readingMax : 720.0;
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: context.sanad.isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: ReferenceBackdrop(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            bottomNavigationBar: webWide ? null : contactDock(),
            body: SafeArea(
              bottom: false,
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: webWide ? WebLayout.contentMax : contentMax,
                  ),
                  child: webWide
                      ? Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: WebLayout.pagePadding(
                              WebLayout.of(context),
                            ).left,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 7,
                                child: detailsScroll(
                                  contentMax: contentMax,
                                  showInlineContact: false,
                                ),
                              ),
                              const SizedBox(width: 24),
                              SizedBox(width: 300, child: webActionRail()),
                            ],
                          ),
                        )
                      : detailsScroll(
                          contentMax: contentMax,
                          showInlineContact: kIsWeb,
                        ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget detailsScroll({
    required double contentMax,
    required bool showInlineContact,
  }) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: contentMax),
    child: CustomScrollView(
      controller: scroll,
      slivers: [
        SliverAppBar(
          pinned: true,
          toolbarHeight: 72,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          flexibleSpace: sanadHeaderFill(context),
          leading: IconButton(
            tooltip: 'رجوع',
            onPressed: () => Navigator.pop(context),
            icon: AppIcon(
              CupertinoIcons.chevron_right,
              color: context.sanad.ink,
            ),
          ),
          title: AnimatedSwitcher(
            duration: motionDuration(context, 180),
            child: Text(
              compact ? job.title : 'تفاصيل الفرصة',
              key: ValueKey(compact),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.sanad.ink,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          actions: [
            shareButton(),
            const SizedBox(width: 4),
            saveButton(),
            const SizedBox(width: 12),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
          sliver: SliverList.list(
            children: [
              if (feedback != null)
                Padding(
                  key: feedbackKey,
                  padding: const EdgeInsets.only(bottom: 16),
                  child: SignalCard(
                    feedback!,
                    onClose: () => setState(() => feedback = null),
                  ),
                ),
              if (!available)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: SignalCard(
                    'هذه الفرصة لم تعد متاحة. فيك ترجع وتستكشف فرصاً جديدة.',
                  ),
                ),
              if (showInlineContact) ...[
                webContactCard(),
                const SizedBox(height: 18),
              ],
              overview(),
              if (job.companyWebsite.isNotEmpty) ...[
                const SizedBox(height: 18),
                companyWebsiteCard(),
              ],
              const SizedBox(height: 18),
              salaryCard(),
              const SizedBox(height: 18),
              surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    section('عن الفرصة'),
                    Text(
                      job.description,
                      textDirection: textDirectionFor(job.description),
                      style: TextStyle(
                        color: context.sanad.secondary,
                        height: 1.9,
                      ),
                    ),
                  ],
                ),
              ),
              if (job.requirements.isNotEmpty) ...[
                const SizedBox(height: 14),
                surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      section('شو المطلوب؟'),
                      for (final requirement in job.requirements)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: AppIcon(
                                  Icons.check_circle_outline,
                                  color: context.sanad.primary,
                                  size: 19,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  requirement,
                                  textDirection: textDirectionFor(requirement),
                                  style: TextStyle(
                                    color: context.sanad.secondary,
                                    height: 1.75,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              surface(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppIcon(
                      CupertinoIcons.calendar,
                      color: context.sanad.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'مدة الإعلان',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'من ${date(job.createdAt)} إلى ${date(job.expiresAt)}',
                            style: TextStyle(
                              color: context.sanad.secondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (job.isDemo || widget.store.isDemo)
                Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'فرصة تجريبية للتعرّف على التطبيق، وليست إعلان توظيف فعلياً.',
                    style: TextStyle(
                      color: context.sanad.secondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              actionsPanel(),
              const SizedBox(height: 16),
              Text(
                'التواصل مباشر مع جهة العمل. لا تدفع أي مبلغ مقابل التقديم.',
                style: TextStyle(
                  color: context.sanad.secondary,
                  fontSize: 12,
                  height: 1.8,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget webActionRail() => Padding(
    padding: const EdgeInsets.only(top: 88, bottom: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        webContactCard(),
        const SizedBox(height: 14),
        surface(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'إجراءات',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: context.sanad.ink,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: shareButton()),
                  const SizedBox(width: 8),
                  Expanded(child: saveButton()),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget webContactCard() => surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'تواصل مع المعلن',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: context.sanad.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'التواصل مباشر مع صاحب الإعلان عبر واتساب أو الإيميل.',
          style: TextStyle(
            color: context.sanad.secondary,
            fontSize: 12,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed:
              !available ||
                  contacting ||
                  (job.phone.isEmpty && job.email.isEmpty)
              ? null
              : () => contact(job.phone.isEmpty),
          icon: contacting
              ? const SanadLoader(size: 26)
              : AppIcon(
                  job.phone.isEmpty
                      ? CupertinoIcons.envelope
                      : CupertinoIcons.chat_bubble_2_fill,
                  color: Theme.of(context).colorScheme.onPrimary,
                  size: 19,
                ),
          label: Text(
            !available
                ? 'الفرصة غير متاحة'
                : contacting
                ? 'نتأكد من توفرها…'
                : job.phone.isNotEmpty
                ? 'تواصل واتساب'
                : job.email.isNotEmpty
                ? 'تواصل بالإيميل'
                : 'لا توجد وسيلة تواصل',
          ),
        ),
        if (job.phone.isNotEmpty && job.email.isNotEmpty) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: !available || contacting ? null : () => contact(true),
            icon: AppIcon(
              CupertinoIcons.envelope,
              color: context.sanad.primary,
              size: 18,
            ),
            label: const Text('تواصل بالإيميل'),
          ),
        ],
      ],
    ),
  );

  Widget overview() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          CompanyMark(job.category, size: 60),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.company,
                  textDirection: textDirectionFor(job.company),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.sanad.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  job.category,
                  style: TextStyle(
                    color: context.sanad.secondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 22),
      Text(
        job.title,
        textDirection: textDirectionFor(job.title),
        style: TextStyle(
          fontSize: 27,
          height: 1.45,
          color: context.sanad.ink,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          AppIcon(
            CupertinoIcons.location,
            size: 17,
            color: context.sanad.secondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              job.locationLabel,
              style: TextStyle(color: context.sanad.secondary),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [tag(job.workMode), tag(job.workType), tag(job.experience)],
      ),
    ],
  );

  Widget salaryCard() => surface(
    color: context.sanad.tint,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'الراتب',
          style: TextStyle(color: context.sanad.secondary, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              job.salaryLabel,
              textDirection: job.hasSalary
                  ? TextDirection.ltr
                  : TextDirection.rtl,
              style: TextStyle(
                color: context.sanad.primary,
                fontSize: job.hasSalary ? 25 : 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (job.hasSalary)
              Text(
                '/ ${job.salaryPeriod}',
                style: TextStyle(color: context.sanad.secondary, fontSize: 13),
              ),
          ],
        ),
      ],
    ),
  );

  Widget companyWebsiteCard() => surface(
    key: websiteKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AppIcon(
              CupertinoIcons.globe,
              color: context.sanad.primary,
              size: 22,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'تعرّف على جهة العمل',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          job.companyWebsite,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.start,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: context.sanad.secondary),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: !available || openingWebsite ? null : openCompanyWebsite,
          child: openingWebsite
              ? const SanadLoader(size: 22, label: 'عم نفتح الرابط…')
              : const Text('زيارة موقع الجهة'),
        ),
        if (websiteFeedback != null) ...[
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(
              websiteFeedback!,
              style: TextStyle(color: context.sanad.secondary, fontSize: 12),
            ),
          ),
        ],
      ],
    ),
  );

  Widget actionsPanel() => surface(
    padding: const EdgeInsets.all(8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Theme(
          data: Theme.of(context).copyWith(
            splashFactory: NoSplash.splashFactory,
            highlightColor: context.sanad.tint.withValues(alpha: .55),
          ),
          child: ListTile(
            minTileHeight: 52,
            leading: sharing
                ? const SanadLoader(size: 22)
                : AppIcon(
                    CupertinoIcons.share,
                    color: context.sanad.primary,
                    size: 21,
                  ),
            title: const Text('مشاركة الفرصة', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              'ابعت التفاصيل لصديق أو مجموعة',
              style: TextStyle(color: context.sanad.secondary, fontSize: 12),
            ),
            onTap: !available || sharing ? null : shareJob,
          ),
        ),
        Divider(
          height: 1,
          indent: 12,
          endIndent: 12,
          color: context.sanad.border,
        ),
        Theme(
          data: Theme.of(context).copyWith(
            splashFactory: NoSplash.splashFactory,
            highlightColor: context.sanad.tint.withValues(alpha: .55),
          ),
          child: ListTile(
            minTileHeight: 52,
            leading: AppIcon(
              Icons.flag_outlined,
              color: context.sanad.secondary,
              size: 21,
            ),
            title: const Text(
              'الإبلاغ عن الفرصة',
              style: TextStyle(fontSize: 14),
            ),
            trailing: AppIcon(
              reportOpen
                  ? CupertinoIcons.chevron_up
                  : CupertinoIcons.chevron_down,
              color: context.sanad.secondary,
              size: 16,
            ),
            onTap: reporting
                ? null
                : () {
                    setState(() {
                      reportOpen = !reportOpen;
                      hideOpen = false;
                    });
                    if (reportOpen) revealPanel(reportKey);
                  },
          ),
        ),
        MotionSize(
          duration: motionDuration(context, 220),
          alignment: Alignment.topCenter,
          curve: Curves.easeOutCubic,
          child: reportOpen
              ? reportChoices()
              : const SizedBox(width: double.infinity),
        ),
        if (reportFeedback != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                reportFeedback!,
                style: TextStyle(color: context.sanad.primary, fontSize: 13),
              ),
            ),
          ),
        Divider(
          height: 1,
          indent: 12,
          endIndent: 12,
          color: context.sanad.border,
        ),
        Theme(
          data: Theme.of(context).copyWith(
            splashFactory: NoSplash.splashFactory,
            highlightColor: context.sanad.tint.withValues(alpha: .55),
          ),
          child: ListTile(
            minTileHeight: 52,
            leading: AppIcon(
              Icons.visibility_off_outlined,
              color: context.sanad.secondary,
              size: 21,
            ),
            title: const Text(
              'إخفاء فرص هذه الجهة',
              style: TextStyle(fontSize: 14),
            ),
            trailing: AppIcon(
              hideOpen
                  ? CupertinoIcons.chevron_up
                  : CupertinoIcons.chevron_down,
              color: context.sanad.secondary,
              size: 16,
            ),
            onTap: hiding
                ? null
                : () {
                    setState(() {
                      hideOpen = !hideOpen;
                      reportOpen = false;
                    });
                    if (hideOpen) revealPanel(hideKey);
                  },
          ),
        ),
        MotionSize(
          duration: motionDuration(context, 220),
          alignment: Alignment.topCenter,
          curve: Curves.easeOutCubic,
          child: hideOpen
              ? Padding(
                  key: hideKey,
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'لن تظهر فرص ${job.company} على هذا الجهاز. يمكنك التراجع من صفحة الخصوصية.',
                        style: TextStyle(
                          color: context.sanad.secondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: hiding ? null : hideEmployer,
                        child: Text(
                          hiding ? 'جارٍ الحفظ…' : 'تأكيد إخفاء الجهة',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: hiding
                            ? null
                            : () => setState(() => hideOpen = false),
                        child: const Text('إلغاء'),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    ),
  );

  Widget reportChoices() => Padding(
    key: reportKey,
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'اختر السبب لنساعدك بشكل أفضل',
          style: TextStyle(color: context.sanad.secondary, fontSize: 13),
        ),
        const SizedBox(height: 8),
        for (final reason in const [
          'طلب دفع مقابل التوظيف',
          'معلومات مضللة أو جهة وهمية',
          'محتوى غير مناسب',
          'الفرصة لم تعد متاحة',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Semantics(
              selected: reportReason == reason,
              child: Material(
                color: reportReason == reason
                    ? context.sanad.tint
                    : context.sanad.background,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: reporting
                      ? null
                      : () => setState(() => reportReason = reason),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        AppIcon(
                          reportReason == reason
                              ? CupertinoIcons.checkmark_circle_fill
                              : CupertinoIcons.circle,
                          color: context.sanad.primary,
                          size: 21,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            reason,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: reporting || reportReason == null ? null : sendReport,
          child: Text(reporting ? 'جارٍ الإرسال…' : 'إرسال البلاغ'),
        ),
      ],
    ),
  );

  Widget shareButton() => Semantics(
    button: true,
    label: 'مشاركة الفرصة',
    child: IconButton(
      tooltip: 'مشاركة الفرصة',
      onPressed: !available || sharing ? null : shareJob,
      style: IconButton.styleFrom(
        backgroundColor: context.sanad.surface,
        minimumSize: const Size(48, 48),
      ),
      icon: sharing
          ? const SanadLoader(size: 22)
          : AppIcon(
              CupertinoIcons.share,
              color: context.sanad.primary,
              size: 21,
            ),
    ),
  );

  Widget saveButton() {
    final saved = widget.store.savedIds.contains(job.id);
    return Semantics(
      toggled: saved,
      button: true,
      excludeSemantics: true,
      label: saved ? 'إزالة من المحفوظة' : 'حفظ الفرصة',
      onTap: saving ? null : save,
      child: IconButton(
        tooltip: saved ? 'إزالة من المحفوظة' : 'حفظ الفرصة',
        onPressed: saving ? null : save,
        style: IconButton.styleFrom(
          backgroundColor: context.sanad.surface,
          minimumSize: const Size(48, 48),
        ),
        icon: AnimatedSaveIcon(saved: saved, size: 22),
      ),
    );
  }

  Widget contactDock() => DecoratedBox(
    decoration: BoxDecoration(
      color: context.sanad.surface,
      border: Border(top: BorderSide(color: context.sanad.border)),
    ),
    child: SafeArea(
      top: false,
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        !available ||
                            contacting ||
                            (job.phone.isEmpty && job.email.isEmpty)
                        ? null
                        : () => contact(job.phone.isEmpty),
                    icon: contacting
                        ? const SanadLoader(size: 26)
                        : AppIcon(
                            job.phone.isEmpty
                                ? CupertinoIcons.envelope
                                : CupertinoIcons.chat_bubble_2_fill,
                            color: Theme.of(context).colorScheme.onPrimary,
                            size: 19,
                          ),
                    label: Text(
                      !available
                          ? 'الفرصة غير متاحة'
                          : contacting
                          ? 'نتأكد من توفرها…'
                          : job.phone.isNotEmpty
                          ? 'تواصل واتساب'
                          : job.email.isNotEmpty
                          ? 'تواصل بالإيميل'
                          : 'لا توجد وسيلة تواصل',
                    ),
                  ),
                ),
                if (job.phone.isNotEmpty && job.email.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                    tooltip: 'تواصل بالإيميل',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(54, 54),
                      backgroundColor: context.sanad.tint,
                    ),
                    onPressed: !available || contacting
                        ? null
                        : () => contact(true),
                    icon: AppIcon(
                      CupertinoIcons.envelope,
                      color: context.sanad.primary,
                      size: 22,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget tag(String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: context.sanad.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.sanad.border),
    ),
    child: Text(
      value,
      style: TextStyle(fontSize: 12, color: context.sanad.secondary),
    ),
  );

  Widget section(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: context.sanad.ink,
      ),
    ),
  );

  Widget surface({
    Key? key,
    required Widget child,
    Color? color,
    EdgeInsetsGeometry padding = const EdgeInsets.all(20),
  }) => Material(
    key: key,
    color: color ?? context.sanad.surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(color: context.sanad.border),
    ),
    child: Padding(padding: padding, child: child),
  );

  String date(DateTime value) {
    final local = value.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }
}
