import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/adaptive_text_field.dart';
import '../../../../core/design.dart';
import '../../../../core/motion.dart';
import '../../../../core/sanad_refresh.dart';
import '../../../../core/web_layout.dart';
import '../../data/jobs_store.dart';
import '../../domain/job.dart';
import '../../domain/job_filters.dart';
import '../about_page.dart';
import '../filter_sheet.dart';
import '../job_details.dart';
import '../notifications.dart';
import '../post_job.dart';
import 'sanad_web_shell.dart';

/// Adaptive website entry for Flutter web — not the mobile app chrome.
class SanadWebApp extends StatefulWidget {
  const SanadWebApp({super.key, required this.store});
  final JobsStore store;

  @override
  State<SanadWebApp> createState() => _SanadWebAppState();
}

class _SanadWebAppState extends State<SanadWebApp> {
  int section = 0;
  bool menuOpen = false;
  bool routeOpening = false;
  bool refreshing = false;
  final search = TextEditingController();
  final searchFocus = FocusNode();
  final scroll = ScrollController();
  final refreshKey = GlobalKey<SanadRefreshState>();
  final Set<String> saving = {};
  String? feedback;

  JobsStore get store => widget.store;
  bool get searching => store.filters.activeCount > 0 || store.query.isNotEmpty;
  List<Job> get feed => store.visibleJobs;

  @override
  void initState() {
    super.initState();
    search.text = store.query;
  }

  @override
  void dispose() {
    searchFocus.dispose();
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> navigate(Future<dynamic> Function() action) async {
    if (routeOpening) return;
    routeOpening = true;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => menuOpen = false);
    try {
      await action();
    } finally {
      routeOpening = false;
    }
  }

  Future<void> openFilters() => navigate(() async {
    final result = await showFilters(context, store);
    if (result != null && mounted) store.updateFilters(result);
  });

  void clearFilters() {
    search.clear();
    store.setQuery('');
    store.updateFilters(const JobFilters());
  }

  Future<void> openDetails(Job job) => navigate(
    () => openPage<void>(context, JobDetails(job: job, store: store)),
  );

  Future<void> openNotices() => navigate(
    () => openPage<void>(
      context,
      NotificationsPage(
        store: store,
        onJob: (job) =>
            openPage<void>(context, JobDetails(job: job, store: store)),
      ),
    ),
  );

  Future<void> openAbout() =>
      navigate(() => openPage<void>(context, AboutPage(store: store)));

  Future<void> openPost() => navigate(() => showPostJob(context, store));

  Future<void> favorite(Job job) async {
    if (!saving.add(job.id)) return;
    setState(() {});
    try {
      await store.toggleSaved(job.id);
      if (!mounted) return;
      setState(() {
        feedback =
            store.error ??
            (store.savedIds.contains(job.id)
                ? 'صارت بالمحفوظة.'
                : 'شِلنا الفرصة من المحفوظة.');
      });
    } finally {
      saving.remove(job.id);
      if (mounted) setState(() {});
    }
  }

  Future<String?> refreshFeed() async {
    if (refreshing || store.loading || store.busy) {
      return 'التحديث جارٍ. انتظر اكتماله.';
    }
    setState(() => refreshing = true);
    try {
      await store.refresh();
      return store.error;
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  String age(DateTime date) {
    final days = DateTime.now().difference(date).inDays;
    if (days <= 0) return 'أُضيفت اليوم';
    if (days == 1) return 'منذ يوم';
    if (days < 7) return 'منذ $days أيام';
    return 'منذ ${(days / 7).floor()} أسابيع';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => SanadWebShell(
      section: section,
      menuOpen: menuOpen,
      onToggleMenu: () => setState(() => menuOpen = !menuOpen),
      onSection: (value) {
        if (value == 2) {
          openPost();
          return;
        }
        setState(() {
          section = value;
          menuOpen = false;
          feedback = null;
        });
      },
      onNotices: openNotices,
      onAbout: openAbout,
      child: switch (section) {
        1 => _SavedSection(
          store: store,
          saving: saving,
          onOpen: openDetails,
          onFavorite: favorite,
          age: age,
          onRefresh: refreshFeed,
        ),
        _ => _DiscoverSection(
          store: store,
          feed: feed,
          searching: searching,
          search: search,
          searchFocus: searchFocus,
          scroll: scroll,
          refreshKey: refreshKey,
          saving: saving,
          feedback: feedback,
          onClearFeedback: () => setState(() => feedback = null),
          onFilters: openFilters,
          onClearFilters: clearFilters,
          onOpen: openDetails,
          onFavorite: favorite,
          onRefresh: refreshFeed,
          age: age,
        ),
      },
    ),
  );
}

class _DiscoverSection extends StatelessWidget {
  const _DiscoverSection({
    required this.store,
    required this.feed,
    required this.searching,
    required this.search,
    required this.searchFocus,
    required this.scroll,
    required this.refreshKey,
    required this.saving,
    required this.feedback,
    required this.onClearFeedback,
    required this.onFilters,
    required this.onClearFilters,
    required this.onOpen,
    required this.onFavorite,
    required this.onRefresh,
    required this.age,
  });

  final JobsStore store;
  final List<Job> feed;
  final bool searching;
  final TextEditingController search;
  final FocusNode searchFocus;
  final ScrollController scroll;
  final GlobalKey<SanadRefreshState> refreshKey;
  final Set<String> saving;
  final String? feedback;
  final VoidCallback onClearFeedback;
  final VoidCallback onFilters;
  final VoidCallback onClearFilters;
  final Future<void> Function(Job) onOpen;
  final Future<void> Function(Job) onFavorite;
  final Future<String?> Function() onRefresh;
  final String Function(DateTime) age;

  @override
  Widget build(BuildContext context) {
    final breakpoint = WebLayout.of(context);
    final columns = WebLayout.jobColumns(breakpoint);
    final padding = WebLayout.pagePadding(breakpoint);
    final gutter = WebLayout.gutter(breakpoint);

    return SanadRefresh(
      key: refreshKey,
      enabled: !store.loading && !store.busy,
      onRefresh: onRefresh,
      successLabel: store.isDemo ? 'تحدّثت فرص العرض' : 'صارت الفرص محدّثة',
      child: CustomScrollView(
        controller: scroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _SiteHero(
              breakpoint: breakpoint,
              search: search,
              searchFocus: searchFocus,
              store: store,
              onFilters: onFilters,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(padding.left, 8, padding.right, 0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: WebLayout.contentMax,
                  ),
                  child: _QuickFilters(store: store, onFilters: onFilters),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(padding.left, 28, padding.right, 40),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: WebLayout.contentMax,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (feedback != null) ...[
                        SignalCard(feedback!, onClose: onClearFeedback),
                        const SizedBox(height: 16),
                      ],
                      if (store.error != null) ...[
                        SignalCard(
                          store.error!,
                          action: () => refreshKey.currentState?.refresh(),
                          onClose: store.clearError,
                        ),
                        const SizedBox(height: 16),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  searching
                                      ? 'نتائج بحثك'
                                      : 'فرص تستاهل تشوفها',
                                  style: TextStyle(
                                    fontSize:
                                        breakpoint == WebBreakpoint.compact
                                        ? 22
                                        : 28,
                                    fontWeight: FontWeight.w800,
                                    color: context.sanad.ink,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${feed.length} فرصة${searching ? ' مطابقة' : ' متاحة'}',
                                  style: TextStyle(
                                    color: context.sanad.secondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (searching)
                            TextButton.icon(
                              onPressed: onClearFilters,
                              icon: AppIcon(
                                CupertinoIcons.xmark,
                                size: 16,
                                color: context.sanad.primary,
                              ),
                              label: const Text('مسح البحث'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (feed.isEmpty)
                        _EmptyJobs(searching: searching)
                      else
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.maxWidth;
                            final cardWidth = columns == 1
                                ? width
                                : (width - gutter * (columns - 1)) / columns;
                            return Wrap(
                              spacing: gutter,
                              runSpacing: gutter,
                              children: [
                                for (final job in feed)
                                  SizedBox(
                                    width: cardWidth,
                                    child: _WebJobCard(
                                      job: job,
                                      saved: store.savedIds.contains(job.id),
                                      busy: saving.contains(job.id),
                                      ageLabel: age(job.createdAt),
                                      onOpen: () => onOpen(job),
                                      onFavorite: () => onFavorite(job),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SiteHero extends StatelessWidget {
  const _SiteHero({
    required this.breakpoint,
    required this.search,
    required this.searchFocus,
    required this.store,
    required this.onFilters,
  });

  final WebBreakpoint breakpoint;
  final TextEditingController search;
  final FocusNode searchFocus;
  final JobsStore store;
  final VoidCallback onFilters;

  @override
  Widget build(BuildContext context) {
    final padding = WebLayout.pagePadding(breakpoint);
    final stacked = breakpoint == WebBreakpoint.compact;
    return Padding(
      padding: EdgeInsets.fromLTRB(padding.left, 28, padding.right, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: WebLayout.contentMax),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: context.sanad.isDark
                    ? [
                        context.sanad.surface,
                        context.sanad.tint,
                        context.sanad.background,
                      ]
                    : const [
                        Color(0xFFFFFFFF),
                        Color(0xFFE7F0FA),
                        Color(0xFFB6D1EE),
                      ],
              ),
              border: Border.all(color: context.sanad.border),
              boxShadow: [
                BoxShadow(
                  color: context.sanad.primary.withValues(alpha: .08),
                  blurRadius: 32,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: stacked ? 22 : 36,
                vertical: stacked ? 28 : 40,
              ),
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _heroCopy(context, stacked: true),
                        const SizedBox(height: 22),
                        _heroSearch(context),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(flex: 5, child: _heroCopy(context)),
                        const SizedBox(width: 36),
                        Expanded(flex: 6, child: _heroSearch(context)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heroCopy(BuildContext context, {bool stacked = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'فرص بسوريا',
        style: TextStyle(
          color: context.sanad.primary,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'شغلك الجاي، أقرب.',
        style: TextStyle(
          color: context.sanad.ink,
          fontWeight: FontWeight.w800,
          fontSize: stacked ? 30 : 40,
          height: 1.25,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'تصفّح الفرص وتواصل مباشرة مع صاحب الإعلان بواتساب أو الإيميل، بلا حساب.',
        style: TextStyle(
          color: context.sanad.secondary,
          fontSize: stacked ? 14 : 16,
          height: 1.7,
        ),
      ),
    ],
  );

  Widget _heroSearch(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.sanad.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: context.sanad.border),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1420508A),
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      children: [
        Expanded(
          child: AdaptiveFieldDirection(
            controller: search,
            builder: (context, direction) => TextField(
              controller: search,
              focusNode: searchFocus,
              textDirection: direction,
              onChanged: store.setQuery,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => searchFocus.unfocus(),
              style: TextStyle(color: context.sanad.ink, fontSize: 15),
              decoration: InputDecoration(
                filled: false,
                hintText: 'دوّر على شغل، جهة أو مهارة',
                hintStyle: TextStyle(
                  color: context.sanad.secondary,
                  fontSize: 14,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(14),
                  child: AppIcon(
                    CupertinoIcons.search,
                    color: context.sanad.primary,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Badge(
            isLabelVisible: store.filters.activeCount > 0,
            label: Text('${store.filters.activeCount}'),
            child: FilledButton.tonal(
              onPressed: onFilters,
              child: const Text('فلتر'),
            ),
          ),
        ),
      ],
    ),
  );
}

class _QuickFilters extends StatelessWidget {
  const _QuickFilters({required this.store, required this.onFilters});
  final JobsStore store;
  final VoidCallback onFilters;

  @override
  Widget build(BuildContext context) {
    final chips = <(String, bool, VoidCallback, IconData?)>[
      (
        store.filters.city ?? 'كل سوريا',
        store.filters.city != null,
        onFilters,
        CupertinoIcons.location,
      ),
      (
        'عن بُعد',
        store.filters.workMode == 'عن بُعد',
        () => store.updateFilters(
          store.filters.copyWith(
            workMode: store.filters.workMode == 'عن بُعد' ? null : 'عن بُعد',
          ),
        ),
        CupertinoIcons.globe,
      ),
      (
        'بدون خبرة',
        store.filters.experience == 'بدون خبرة',
        () => store.updateFilters(
          store.filters.copyWith(
            experience: store.filters.experience == 'بدون خبرة'
                ? null
                : 'بدون خبرة',
          ),
        ),
        CupertinoIcons.sparkles,
      ),
      (
        'راتب معلن',
        store.filters.salaryOnly,
        () => store.updateFilters(
          store.filters.copyWith(salaryOnly: !store.filters.salaryOnly),
        ),
        null,
      ),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final chip in chips)
          _FilterChip(
            label: chip.$1,
            selected: chip.$2,
            onTap: chip.$3,
            icon: chip.$4,
          ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? context.sanad.primary : context.sanad.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? context.sanad.primary : context.sanad.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                AppIcon(
                  icon,
                  size: 15,
                  color: selected
                      ? Theme.of(context).colorScheme.onPrimary
                      : context.sanad.primary,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? Theme.of(context).colorScheme.onPrimary
                      : context.sanad.ink,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _WebJobCard extends StatelessWidget {
  const _WebJobCard({
    required this.job,
    required this.saved,
    required this.busy,
    required this.ageLabel,
    required this.onOpen,
    required this.onFavorite,
  });

  final Job job;
  final bool saved;
  final bool busy;
  final String ageLabel;
  final VoidCallback onOpen;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) => Material(
    color: context.sanad.surface,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(color: context.sanad.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CompanyMark(job.category, size: 44),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.company,
                        textDirection: textDirectionFor(job.company),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        ageLabel,
                        style: TextStyle(
                          color: context.sanad.secondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: saved ? 'إزالة من المحفوظة' : 'حفظ الفرصة',
                  onPressed: busy ? null : onFavorite,
                  icon: AnimatedSaveIcon(saved: saved),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              job.title,
              textDirection: textDirectionFor(job.title),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.sanad.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${job.locationLabel} · ${job.workMode}',
              style: TextStyle(color: context.sanad.secondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                AppTag(job.workType, color: context.sanad.primary),
                AppTag(job.experience, color: context.sanad.primary),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              job.salaryLabel,
              textDirection: job.hasSalary
                  ? TextDirection.ltr
                  : TextDirection.rtl,
              style: TextStyle(
                color: context.sanad.ink,
                fontWeight: FontWeight.w700,
                fontSize: job.hasSalary ? 18 : 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'شوف التفاصيل',
              style: TextStyle(
                color: context.sanad.primary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyJobs extends StatelessWidget {
  const _EmptyJobs({required this.searching});
  final bool searching;

  @override
  Widget build(BuildContext context) => _EmptyPanel(
    icon: searching ? CupertinoIcons.search : CupertinoIcons.briefcase,
    title: searching ? 'ما لقينا فرص بهالبحث' : 'ما في فرص معروضة هلّق',
    body: searching
        ? 'جرّب كلمات أوسع أو امسح الفلاتر.'
        : 'حدّث الصفحة لاحقاً أو انشر فرصة إذا كنت معلناً.',
  );
}

class _EmptySaved extends StatelessWidget {
  const _EmptySaved();

  @override
  Widget build(BuildContext context) => const _EmptyPanel(
    icon: CupertinoIcons.heart,
    title: 'ما حفظت شي بعد',
    body: 'من صفحة الفرص احفظ اللي يعجبك لترجع له بسهولة.',
  );
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: context.sanad.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: context.sanad.border),
    ),
    child: Column(
      children: [
        AppIcon(icon, size: 28, color: context.sanad.primary),
        const SizedBox(height: 14),
        Text(
          title,
          style: TextStyle(
            color: context.sanad.ink,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.sanad.secondary, height: 1.6),
        ),
      ],
    ),
  );
}

class _SavedSection extends StatelessWidget {
  const _SavedSection({
    required this.store,
    required this.saving,
    required this.onOpen,
    required this.onFavorite,
    required this.age,
    required this.onRefresh,
  });

  final JobsStore store;
  final Set<String> saving;
  final Future<void> Function(Job) onOpen;
  final Future<void> Function(Job) onFavorite;
  final String Function(DateTime) age;
  final Future<String?> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final breakpoint = WebLayout.of(context);
    final padding = WebLayout.pagePadding(breakpoint);
    final columns = WebLayout.jobColumns(breakpoint);
    final gutter = WebLayout.gutter(breakpoint);
    final jobs = store.savedJobs;

    return SanadRefresh(
      enabled: !store.loading && !store.busy,
      onRefresh: onRefresh,
      successLabel: 'صارت المحفوظة محدّثة',
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(padding.left, 28, padding.right, 40),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: WebLayout.contentMax,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'المحفوظة',
                        style: TextStyle(
                          fontSize: breakpoint == WebBreakpoint.compact
                              ? 24
                              : 30,
                          fontWeight: FontWeight.w800,
                          color: context.sanad.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'فرص حفظتها على هذا المتصفح لتراجعها لاحقاً.',
                        style: TextStyle(
                          color: context.sanad.secondary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (jobs.isEmpty)
                        const _EmptySaved()
                      else
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.maxWidth;
                            final cardWidth = columns == 1
                                ? width
                                : (width - gutter * (columns - 1)) / columns;
                            return Wrap(
                              spacing: gutter,
                              runSpacing: gutter,
                              children: [
                                for (final job in jobs)
                                  SizedBox(
                                    width: cardWidth,
                                    child: _WebJobCard(
                                      job: job,
                                      saved: true,
                                      busy: saving.contains(job.id),
                                      ageLabel: age(job.createdAt),
                                      onOpen: () => onOpen(job),
                                      onFavorite: () => onFavorite(job),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
