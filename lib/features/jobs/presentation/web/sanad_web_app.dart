import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/adaptive_text_field.dart';
import '../../../../core/design.dart';
import '../../../../core/motion.dart';
import '../../../../core/sanad_refresh.dart';
import '../../../../core/web_layout.dart';
import '../../../../core/web_nav_history.dart';
import '../../data/jobs_store.dart';
import '../../domain/job.dart';
import '../../domain/job_filters.dart';
import '../about_page.dart';
import '../../../platform/presentation/auth_page.dart';
import '../../../platform/presentation/account_page.dart';
import '../../../platform/presentation/publisher_panel.dart';
import '../../../platform/presentation/saved_panel.dart';
import '../filter_sheet.dart';
import '../location_picker.dart';
import '../job_details.dart';
import '../notifications.dart';
import '../post_job.dart';
import '../saved_matches_notice.dart';
import '../country_flag.dart';
import '../../domain/job_geography.dart';
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
  Timer? _noticesTimer;

  JobsStore get store => widget.store;
  bool get searching => store.filters.activeCount > 0 || store.query.isNotEmpty;
  List<Job> get feed => store.visibleJobs;

  @override
  void initState() {
    super.initState();
    search.text = store.query;
    // Keep the follow-up center fresh while the site tab stays open.
    unawaited(store.refreshNotices());
    unawaited(store.refreshSavedSearchMatches());
    _noticesTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      unawaited(store.refreshNotices());
    });
  }

  @override
  void dispose() {
    _noticesTimer?.cancel();
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

  Future<void> leavePage([Future<void> Function()? next]) async {
    final nav = Navigator.of(context);
    while (nav.canPop()) {
      final depth = WebNavHistory.instance.pageDepth;
      await nav.maybePop();
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      // A draft veto keeps its inline confirmation visible.
      if (nav.canPop() && WebNavHistory.instance.pageDepth == depth) return;
    }
    final traversal = WebNavHistory.instance.pendingTraversal;
    if (traversal != null) await traversal;
    if (mounted && next != null) await next();
  }

  Widget siteFrame(Widget child) {
    var routeMenuOpen = false;
    return StatefulBuilder(
      builder: (context, updateShell) => SanadWebShell(
        section: section,
        menuOpen: routeMenuOpen,
        onToggleMenu: () => updateShell(() => routeMenuOpen = !routeMenuOpen),
        noticesUnread:
            store.noticesUnread +
            store.savedSearchMatches
                .where((job) => store.isNewSavedMatch(job.id))
                .length,
        onSection: (value) {
          if (value == 2) {
            unawaited(leavePage(openPost));
            return;
          }
          unawaited(leavePage());
          setState(() => section = value);
        },
        onNotices: () => unawaited(leavePage(openNotices)),
        onAbout: () => unawaited(leavePage(openAbout)),
        child: child,
      ),
    );
  }

  Future<void> openFilters() => navigate(() async {
    final result = await openPage<JobFilters>(
      context,
      siteFrame(FilterSheet(store: store)),
    );
    if (result != null && mounted) store.updateFilters(result);
  });

  Future<void> openCityFilter() => navigate(
    () => openPage<JobFilters>(
      context,
      siteFrame(
        LocationPickerPage(
          store: store,
          initial: store.filters,
          applyToStore: true,
        ),
      ),
    ).then((_) {}),
  );

  void clearFilters() {
    search.clear();
    store.setQuery('');
    store.updateFilters(const JobFilters());
  }

  Future<void> openDetails(Job job) => navigate(
    () => openPage<void>(
      context,
      siteFrame(JobDetails(job: job, store: store)),
      webPath: '/jobs/${Uri.encodeComponent(job.id)}',
    ),
  );

  Future<void> openNotices({Set<String>? focusJobIds}) => navigate(
    () => openPage<void>(
      context,
      siteFrame(
        NotificationsPage(
          store: store,
          focusJobIds: focusJobIds,
          initialNewOnly: focusJobIds != null,
          onJob: (job) => openPage<void>(
            context,
            siteFrame(JobDetails(job: job, store: store)),
            webPath: '/jobs/${Uri.encodeComponent(job.id)}',
          ),
        ),
      ),
    ),
  );

  Future<void> openNewMatches() async {
    final ids = store.newMatchAlertJobs.map((job) => job.id).toSet();
    if (ids.isEmpty) return;
    await store.acknowledgeMatchAlert(ids);
    if (mounted) await openNotices(focusJobIds: ids);
  }

  Future<void> openAbout() => navigate(
    () => openPage<void>(
      context,
      siteFrame(
        store.accountsEnabled
            ? AccountPage(store: store)
            : AboutPage(store: store),
      ),
    ),
  );

  Future<void> openPost() => navigate(
    () => openPage<void>(
      context,
      siteFrame(
        store.accountsEnabled
            ? PublisherPanel(store: store)
            : PostJobPage(store: store),
      ),
    ),
  );

  Future<void> favorite(Job job) async {
    final desired = !store.savedIds.contains(job.id);
    if (store.accountsEnabled &&
            !await ensureAccount(
              context,
              store.platform,
              reason: 'لحفظ الفرصة',
            ) ||
        !mounted) {
      return;
    }
    if (!saving.add(job.id)) return;
    setState(() {});
    try {
      await store.toggleSaved(job.id, desired: desired);
      if (!mounted) return;
      setState(() {
        // store.error already has its own SignalCard; avoid duplicating it.
        feedback = store.error != null
            ? null
            : (store.savedIds.contains(job.id)
                  ? 'أُضيفت الفرصة إلى المحفوظات.'
                  : 'أُزيلت الفرصة من المحفوظات.');
      });
    } catch (e) {
      if (mounted) setState(() => feedback = e.toString());
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
      await store.refreshSavedSearchMatches(force: true);
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
    builder: (context, _) {
      final compact = WebLayout.of(context) == WebBreakpoint.compact;
      final headerExtent =
          MediaQuery.paddingOf(context).top +
          70 +
          (compact && menuOpen ? 300 : 0);
      return SanadWebShell(
        section: section,
        menuOpen: menuOpen,
        overlayHeader: true,
        noticesUnread:
            store.noticesUnread +
            store.savedSearchMatches
                .where((job) => store.isNewSavedMatch(job.id))
                .length,
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
          1 when store.accountsEnabled => SavedPanel(store: store),
          1 => _SavedSection(
            store: store,
            saving: saving,
            headerExtent: headerExtent,
            onOpen: openDetails,
            onFavorite: favorite,
            age: age,
            onRefresh: refreshFeed,
          ),
          _ => _DiscoverSection(
            store: store,
            feed: feed,
            headerExtent: headerExtent,
            searching: searching,
            search: search,
            searchFocus: searchFocus,
            scroll: scroll,
            refreshKey: refreshKey,
            saving: saving,
            feedback: feedback,
            onClearFeedback: () => setState(() => feedback = null),
            onFilters: openFilters,
            onCityFilter: openCityFilter,
            onClearFilters: clearFilters,
            onNewMatches: openNewMatches,
            onOpen: openDetails,
            onFavorite: favorite,
            onRefresh: refreshFeed,
            age: age,
          ),
        },
      );
    },
  );
}

class _DiscoverSection extends StatelessWidget {
  const _DiscoverSection({
    required this.store,
    required this.feed,
    required this.headerExtent,
    required this.searching,
    required this.search,
    required this.searchFocus,
    required this.scroll,
    required this.refreshKey,
    required this.saving,
    required this.feedback,
    required this.onClearFeedback,
    required this.onFilters,
    required this.onCityFilter,
    required this.onClearFilters,
    required this.onNewMatches,
    required this.onOpen,
    required this.onFavorite,
    required this.onRefresh,
    required this.age,
  });

  final JobsStore store;
  final List<Job> feed;
  final double headerExtent;
  final bool searching;
  final TextEditingController search;
  final FocusNode searchFocus;
  final ScrollController scroll;
  final GlobalKey<SanadRefreshState> refreshKey;
  final Set<String> saving;
  final String? feedback;
  final VoidCallback onClearFeedback;
  final VoidCallback onFilters;
  final VoidCallback onCityFilter;
  final VoidCallback onClearFilters;
  final VoidCallback onNewMatches;
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
      successLabel: store.isDemo ? 'تحدّثت فرص العرض' : 'تم تحديث الفرص',
      child: CustomScrollView(
        controller: scroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: headerExtent)),
          SliverToBoxAdapter(
            child: SavedMatchesNotice(store: store, onView: onNewMatches),
          ),
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
                  child: _QuickFilters(store: store, onCity: onCityFilter),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(padding.left, 28, padding.right, 0),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: WebLayout.contentMax,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (store.isDemo) ...[
                        const SignalCard(
                          'وضع العرض: هذه فرص افتراضية لتجربة سند، والتواصل معها غير متاح.',
                        ),
                        const SizedBox(height: 16),
                      ],
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
                      SanadActionHeader(
                        title: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              searching ? 'نتائج البحث' : 'فرص العمل المتاحة',
                              style: TextStyle(
                                fontSize: breakpoint == WebBreakpoint.compact
                                    ? 22
                                    : 28,
                                fontWeight: FontWeight.w800,
                                color: context.sanad.ink,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              store.isDemo
                                  ? '${feed.length} فرصة تجريبية${searching ? ' مطابقة' : ''}'
                                  : '${store.pagedCatalog ? store.totalCount : feed.length} فرصة${searching ? ' مطابقة' : ' متاحة'}',
                              style: TextStyle(
                                color: context.sanad.secondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        actions: [
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
                      if (store.discoveryLoading)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: SanadLoader(
                            size: 24,
                            label: 'جارٍ تحديث نتائج البحث…',
                          ),
                        ),
                      if (feed.isEmpty && !store.discoveryLoading)
                        _EmptyJobs(searching: searching),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (feed.isNotEmpty)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 40),
              sliver: _WebJobCardsSliver(
                jobs: feed,
                columns: columns,
                gutter: gutter,
                // Next page starts loading before the visitor reaches the end.
                onNearEnd: store.hasMore ? store.loadMore : null,
                card: (job) => _WebJobCard(
                  key: ValueKey('feed-${job.id}'),
                  job: job,
                  saved: store.savedIds.contains(job.id),
                  busy: saving.contains(job.id),
                  ageLabel: age(job.createdAt),
                  onOpen: () => onOpen(job),
                  onFavorite: () => onFavorite(job),
                ),
              ),
            ),
          if (feed.isNotEmpty &&
              (store.loadingMore || store.loadMoreError != null))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: Center(
                  child: store.loadingMore
                      ? const SanadLoader(
                          size: 24,
                          label: 'جارٍ تحميل المزيد من الفرص…',
                        )
                      : TextButton(
                          onPressed: store.loadMore,
                          child: const Text('تعذّر التحميل، حاول مجدداً'),
                        ),
                ),
              ),
            ),
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SanadWebFooter(),
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
        'فرص عمل دولية',
        style: TextStyle(
          color: context.sanad.primary,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'فرص العمل المتاحة',
        style: TextStyle(
          color: context.sanad.ink,
          fontWeight: FontWeight.w800,
          fontSize: stacked ? 30 : 40,
          height: 1.25,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'تصفّح الفرص وتواصل مباشرة مع صاحب الإعلان عبر واتساب أو البريد الإلكتروني، دون حساب.',
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
                hintText: 'ابحث عن وظيفة أو جهة أو مهارة',
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
            child: SanadPrimaryButton.tonal(
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
  const _QuickFilters({required this.store, required this.onCity});
  final JobsStore store;
  final VoidCallback onCity;

  @override
  Widget build(BuildContext context) {
    final chips = <(String, bool, VoidCallback, IconData?)>[
      (
        store.filters.locationLabel,
        store.filters.country != null || store.filters.city != null,
        onCity,
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
    return SizedBox(
      height: compactWebControls(context) ? 44 : 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final chip = chips[index];
          return _FilterChip(
            label: chip.$1,
            selected: chip.$2,
            onTap: chip.$3,
            icon: chip.$4,
            leading: index == 0 && countryFor(store.filters.country) != null
                ? CountryFlag(
                    country: countryFor(store.filters.country)!,
                    size: 18,
                  )
                : null,
            showChevron: index == 0,
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.leading,
    this.showChevron = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? leading;
  final bool showChevron;

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
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 6),
              ] else if (icon != null) ...[
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
              if (showChevron) ...[
                const SizedBox(width: 8),
                AppIcon(
                  CupertinoIcons.chevron_down,
                  size: 12,
                  color: selected
                      ? Theme.of(context).colorScheme.onPrimary
                      : context.sanad.secondary,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// Lazily builds equal-height rows. A minimum height aligns ordinary cards
/// across the grid; intrinsic sizing still accommodates enlarged text.
class _WebJobCardsSliver extends StatelessWidget {
  const _WebJobCardsSliver({
    required this.jobs,
    required this.columns,
    required this.gutter,
    required this.card,
    this.onNearEnd,
  });

  final List<Job> jobs;
  final int columns;
  final double gutter;
  final Widget Function(Job job) card;
  final Future<void> Function()? onNearEnd;

  @override
  Widget build(BuildContext context) => SliverList.builder(
    itemCount: (jobs.length + columns - 1) ~/ columns,
    itemBuilder: (context, rowIndex) {
      final rows = (jobs.length + columns - 1) ~/ columns;
      final nearEnd = onNearEnd;
      if (nearEnd != null && rowIndex >= rows - 3) {
        WidgetsBinding.instance.addPostFrameCallback((_) => nearEnd());
      }
      final firstIndex = rowIndex * columns;
      return Padding(
        padding: EdgeInsets.only(bottom: gutter),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: WebLayout.contentMax),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    340 * MediaQuery.textScalerOf(context).scale(14) / 14,
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var column = 0; column < columns; column++) ...[
                      if (column > 0) SizedBox(width: gutter),
                      Expanded(
                        child: firstIndex + column < jobs.length
                            ? card(jobs[firstIndex + column])
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _WebJobCard extends StatelessWidget {
  const _WebJobCard({
    super.key,
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
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: Material(
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
                job.viewsCount > 0
                    ? '${job.locationLabel} · ${job.workMode} · ${job.viewsCount} مشاهدة'
                    : '${job.locationLabel} · ${job.workMode}',
                style: TextStyle(color: context.sanad.secondary, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  AppTag(job.workType, color: context.sanad.primary),
                  AppTag(job.experienceLabel, color: context.sanad.primary),
                ],
              ),
              const SizedBox(height: 14),
              const Spacer(),
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
              const SizedBox(height: 5),
              Text(
                job.salaryPeriodLabel ?? '',
                style: TextStyle(
                  color: context.sanad.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'عرض التفاصيل',
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
    ),
  );
}

class _EmptyJobs extends StatelessWidget {
  const _EmptyJobs({required this.searching});
  final bool searching;

  @override
  Widget build(BuildContext context) => _EmptyPanel(
    icon: searching ? CupertinoIcons.search : CupertinoIcons.briefcase,
    title: searching
        ? 'لم نعثر على فرص تطابق البحث'
        : 'لا توجد فرص معروضة حالياً',
    body: searching
        ? 'استخدم كلمات أكثر عمومية أو أزل بعض عوامل التصفية.'
        : 'حدّث الصفحة لاحقاً أو انشر فرصة إذا كنت معلناً.',
  );
}

class _EmptySaved extends StatelessWidget {
  const _EmptySaved();

  @override
  Widget build(BuildContext context) => const _EmptyPanel(
    icon: CupertinoIcons.heart,
    title: 'لم تحفظ أي فرصة بعد.',
    body: 'احفظ الفرص من الصفحة الرئيسية لتعود إليها بسهولة.',
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
    required this.headerExtent,
    required this.onOpen,
    required this.onFavorite,
    required this.age,
    required this.onRefresh,
  });

  final JobsStore store;
  final Set<String> saving;
  final double headerExtent;
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
      successLabel: 'تم تحديث المحفوظات',
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: headerExtent)),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(padding.left, 28, padding.right, 0),
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
                      if (store.isDemo) ...[
                        const SignalCard(
                          'وضع العرض: المحفوظات هنا فرص افتراضية للتجربة فقط.',
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (jobs.isEmpty) const _EmptySaved(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (jobs.isNotEmpty)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 40),
              sliver: _WebJobCardsSliver(
                jobs: jobs,
                columns: columns,
                gutter: gutter,
                card: (job) => _WebJobCard(
                  key: ValueKey('saved-${job.id}'),
                  job: job,
                  saved: true,
                  busy: saving.contains(job.id),
                  ageLabel: age(job.createdAt),
                  onOpen: () => onOpen(job),
                  onFavorite: () => onFavorite(job),
                ),
              ),
            ),
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SanadWebFooter(),
            ),
          ),
        ],
      ),
    );
  }
}
