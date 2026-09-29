import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../../../core/adaptive_text_field.dart';
import '../../../core/design.dart';
import '../../../core/motion.dart';
import '../../../core/sanad_refresh.dart';
import '../../../core/native_bridge.dart';
import '../../../core/native_navigation.dart';
import '../../../core/theme_controls.dart';
import '../data/jobs_store.dart';
import '../domain/job.dart';
import '../domain/job_filters.dart';
import 'about_page.dart';
import 'filter_sheet.dart';
import 'job_details.dart';
import 'notifications.dart';
import 'post_job.dart';

class JobsHome extends StatefulWidget {
  const JobsHome({super.key, required this.store});
  final JobsStore store;
  @override
  State<JobsHome> createState() => _JobsHomeState();
}

class _JobsHomeState extends State<JobsHome> with WidgetsBindingObserver {
  int tab = 0;
  final search = TextEditingController();
  final searchFocus = FocusNode();
  final scroll = ScrollController();
  final heroPages = PageController(viewportFraction: .92);
  final navKey = GlobalKey();
  final feedRefreshKey = GlobalKey<SanadRefreshState>();
  final savedRefreshKey = GlobalKey<SanadRefreshState>();
  final publisherRefreshKey = GlobalKey<SanadRefreshState>();
  final savedNavKey = GlobalKey();
  final Map<String, GlobalKey> cardKeys = {};
  final Set<String> saving = {};
  final Set<String> departing = {};
  final Map<String, (Job, int)> pendingSavedRemoval = {};
  final Set<String> withdrawing = {};
  bool routeOpening = false, refreshing = false;
  int heroIndex = 0;
  Timer? heroTimer;
  bool foreground = true;
  String? draggedId, expandedCard, withdrawId, feedback;
  Job? lastSaved;
  JobsStore get store => widget.store;
  bool get searching => store.filters.activeCount > 0 || store.query.isNotEmpty;
  List<Job> get feed => store.visibleJobs
      .where((j) => !store.savedIds.contains(j.id) || saving.contains(j.id))
      .toList();

  List<Job> get savedCards {
    final jobs = store.savedJobs.toList();
    final pending = pendingSavedRemoval.values.toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));
    for (final entry in pending) {
      if (!jobs.any((job) => job.id == entry.$1.id)) {
        jobs.insert(entry.$2.clamp(0, jobs.length), entry.$1);
      }
    }
    return jobs;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    search.text = store.query;
    searchFocus.addListener(searchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => startHeroRotation());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      heroTimer?.cancel();
    } else {
      startHeroRotation();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      startHeroRotation();
    } else {
      heroTimer?.cancel();
    }
  }

  void startHeroRotation() {
    if (!mounted || !foreground || MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    heroTimer?.cancel();
    heroTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted ||
          tab != 0 ||
          routeOpening ||
          searchFocus.hasFocus ||
          !heroPages.hasClients ||
          (scroll.hasClients &&
              (scroll.offset > 160 ||
                  scroll.position.isScrollingNotifier.value)) ||
          heroPages.position.isScrollingNotifier.value) {
        return;
      }
      final next = (heroIndex + 1) % heroContent.length;
      heroPages.animateToPage(
        next,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeInOutCubicEmphasized,
      );
    });
  }

  void searchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    heroTimer?.cancel();
    heroPages.dispose();
    searchFocus.removeListener(searchChanged);
    searchFocus.dispose();
    search.dispose();
    scroll.dispose();
    // The app entry owns JobsStore, including the optional welcome route.
    super.dispose();
  }

  GlobalKey cardKey(Job job) =>
      cardKeys.putIfAbsent('${job.id}-$tab', GlobalKey.new);
  void message(String text) {
    if (mounted) {
      setState(() {
        feedback = text;
        lastSaved = null;
      });
    }
  }

  void chooseTab(int value) {
    if (tab == value) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      tab = value;
      expandedCard = null;
      feedback = null;
      lastSaved = null;
    });
  }

  Future<void> navigate(Future<dynamic> Function() action) async {
    if (routeOpening) return;
    routeOpening = true;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await action();
    } finally {
      routeOpening = false;
    }
  }

  Future<void> filters() => navigate(() async {
    final result = await showFilters(context, store);
    if (result != null && mounted) {
      store.updateFilters(result);
      NativeBridge.selectionHaptic();
    }
  });
  void clearFilters() {
    search.clear();
    store.setQuery('');
    store.updateFilters(const JobFilters());
  }

  Future<void> details(Job job) async {
    if (saving.contains(job.id) || draggedId != null) return;
    await navigate(
      () => openFromCard(
        context,
        cardKeys['${job.id}-$tab'],
        JobDetails(job: job, store: store),
      ),
    );
  }

  Future<void> latest() => navigate(
    () => openPage<void>(
      context,
      NotificationsPage(
        store: store,
        onJob: (job) =>
            openPage<void>(context, JobDetails(job: job, store: store)),
      ),
    ),
  );
  Future<void> about() =>
      navigate(() => openPage<void>(context, AboutPage(store: store)));
  Future<void> post() => navigate(() => showPostJob(context, store));

  Future<void> favorite(Job job, {bool fromDrop = false}) async {
    if (fromDrop && store.savedIds.contains(job.id)) return;
    if (!saving.add(job.id)) return;
    final adding = !store.savedIds.contains(job.id);
    final originTab = tab;
    final animated = !MediaQuery.disableAnimationsOf(context);
    setState(() {
      draggedId = null;
      if (!adding && originTab == 1) {
        final visible = savedCards;
        pendingSavedRemoval[job.id] = (
          job,
          visible.indexWhere((j) => j.id == job.id).clamp(0, visible.length),
        );
      }
    });
    try {
      await store.toggleSaved(job.id);
      await NativeBridge.selectionHaptic();
      if (!mounted) return;
      setState(() {
        lastSaved = adding ? job : null;
        feedback =
            store.error ??
            (adding
                ? 'صارت بالمحفوظة. ارجعلها بوقتك.'
                : 'شِلنا الفرصة من المحفوظة.');
      });
      // Let the confirmation pulse finish in place, then gently close its slot.
      if (animated) {
        await Future<void>.delayed(const Duration(milliseconds: 520));
      }
      if (!mounted) return;
      final leavesList =
          (adding && originTab == 0) || (!adding && originTab == 1);
      if (animated && tab == originTab && leavesList) {
        setState(() => departing.add(job.id));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    } finally {
      if (mounted) {
        setState(() {
          saving.remove(job.id);
          departing.remove(job.id);
          final removed = pendingSavedRemoval.remove(job.id);
          if (removed != null && !store.savedIds.contains(job.id)) {
            for (final entry in pendingSavedRemoval.entries.toList()) {
              if (entry.value.$2 > removed.$2) {
                pendingSavedRemoval[entry.key] = (
                  entry.value.$1,
                  entry.value.$2 - 1,
                );
              }
            }
          }
        });
      }
    }
  }

  Future<void> undoSave() async {
    final job = lastSaved;
    if (job == null || saving.contains(job.id)) return;
    if (store.savedIds.contains(job.id)) await store.toggleSaved(job.id);
    if (mounted) {
      setState(() {
        lastSaved = null;
        feedback = null;
      });
    }
  }

  Future<void> saveSearch() async {
    await store.saveSearch();
    if (mounted && store.error != null) message(store.error!);
  }

  bool get searchIsSaved => store.savedSearches.any(
    (s) =>
        s['query'] == store.query &&
        JobFilters.fromJson(
              Map<String, dynamic>.from(s['filters'] as Map),
            ).toJson().toString() ==
            store.filters.toJson().toString(),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final size = MediaQuery.sizeOf(context);
      final wide = kIsWeb
          ? size.width >= 980
          : size.width >= 1000 && size.height >= 700;
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value:
            (context.sanad.isDark
                    ? SystemUiOverlayStyle.light
                    : SystemUiOverlayStyle.dark)
                .copyWith(statusBarColor: Colors.transparent),
        child: Scaffold(
          extendBody: true,
          body: ReferenceBackdrop(
            child: Stack(
              fit: StackFit.expand,
              children: [
                SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      if (wide) sidebar(),
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1120),
                            child: Column(
                              children: [
                                sanadHeaderChrome(
                                  context: context,
                                  from: 0,
                                  to: .42,
                                  edge: false,
                                  child: header(),
                                ),
                                Expanded(
                                  child: AnimatedSwitcher(
                                    duration: motionDuration(context, 320),
                                    switchInCurve: Curves.easeOutCubic,
                                    transitionBuilder: (child, animation) =>
                                        FadeTransition(
                                          opacity: animation,
                                          child: child,
                                        ),
                                    layoutBuilder: (current, previous) =>
                                        current ?? const SizedBox.shrink(),
                                    child: KeyedSubtree(
                                      key: ValueKey(tab),
                                      child: switch (tab) {
                                        1 => saved(),
                                        2 => publisher(),
                                        _ => discover(wide),
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: MediaQuery.paddingOf(context).top,
                  child: sanadHeaderChrome(
                    context: context,
                    from: 0,
                    to: .08,
                    edge: false,
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: wide
              ? null
              : SizedBox(
                  key: navKey,
                  child: NativeNavigation(
                    selectedIndex: tab,
                    onSelected: chooseTab,
                  ),
                ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
          floatingActionButton: draggedId == null
              ? null
              : DragTarget<Job>(
                  onAcceptWithDetails: (d) => favorite(d.data, fromDrop: true),
                  builder: (context, candidates, _) => AnimatedContainer(
                    duration: motionDuration(context, 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 17,
                    ),
                    decoration: BoxDecoration(
                      color: candidates.isEmpty
                          ? context.sanad.tint
                          : context.sanad.primary,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(
                          CupertinoIcons.heart,
                          color: candidates.isEmpty
                              ? context.sanad.ink
                              : Theme.of(context).colorScheme.onPrimary,
                          size: 21,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'نزّلها هون • المحفوظة',
                          style: TextStyle(
                            color: candidates.isEmpty
                                ? context.sanad.ink
                                : Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      );
    },
  );

  Widget brand({bool hero = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SanadLogo(size: 38, bare: true, hero: hero),
      const SizedBox(width: 10),
      Text(
        'سند',
        style: TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w700,
          color: context.sanad.ink,
        ),
      ),
    ],
  );

  Widget header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
    child: Row(
      children: [
        Semantics(
          button: true,
          label: 'عن سند',
          child: InkWell(
            onTap: about,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: brand(hero: true),
            ),
          ),
        ),
        const Spacer(),
        const SanadThemePicker(compact: true),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'تحديث ${tab == 2 ? 'إعلاناتي' : 'الفرص'}',
          style: IconButton.styleFrom(backgroundColor: context.sanad.tint),
          onPressed: store.loading || refreshing || store.busy
              ? null
              : refreshCurrentTab,
          icon: store.loading || refreshing
              ? const SanadLoader(size: 23)
              : AppIcon(
                  CupertinoIcons.arrow_clockwise,
                  color: context.sanad.primary,
                  size: 21,
                ),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          tooltip: 'على بالك • الإشعارات',
          style: IconButton.styleFrom(backgroundColor: context.sanad.tint),
          onPressed: latest,
          icon: AppIcon(
            CupertinoIcons.bell,
            color: context.sanad.ink,
            size: 22,
          ),
        ),
      ],
    ),
  );

  double searchHeaderExtent() {
    final textScale = MediaQuery.textScalerOf(context).scale(14) - 14;
    return 84 + 1.7 * textScale;
  }

  SliverPersistentHeader pinnedSearchHeader() {
    final extent = searchHeaderExtent();
    return SliverPersistentHeader(
      pinned: true,
      delegate: MorphHeader(
        expanded: extent,
        collapsed: extent,
        builder: (context, _) => sanadHeaderChrome(
          context: context,
          from: .42,
          to: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
            child: searchBar(),
          ),
        ),
      ),
    );
  }

  Widget sidebar() => Container(
    width: 224,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: context.sanad.surface,
      border: Border(left: BorderSide(color: context.sanad.border)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        brand(),
        const SizedBox(height: 8),
        Text(
          'سندك للخطوة الجاية.',
          style: TextStyle(color: context.sanad.secondary),
        ),
        const SizedBox(height: 36),
        for (final item in [
          (CupertinoIcons.square_grid_2x2, 'الفرص'),
          (CupertinoIcons.heart, 'المحفوظة'),
          (CupertinoIcons.plus_app, 'أضف فرصة'),
        ].indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: tab == item.$1
                  ? context.sanad.tint
                  : context.sanad.surface,
              borderRadius: BorderRadius.circular(16),
              child: ListTile(
                key: item.$1 == 1 ? savedNavKey : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: AppIcon(
                  item.$2.$1,
                  color: tab == item.$1
                      ? context.sanad.primary
                      : context.sanad.secondary,
                  size: 20,
                ),
                title: Text(item.$2.$2),
                onTap: () => chooseTab(item.$1),
              ),
            ),
          ),
        const Spacer(),
        TextButton.icon(
          onPressed: about,
          icon: const AppIcon(CupertinoIcons.info_circle, size: 18),
          label: const Text('عن سند والخصوصية'),
        ),
      ],
    ),
  );
  static const heroContent = [
    (
      eyebrow: 'سندك لخطوة جديدة',
      title: 'شغلك الجاي، أقرب.',
      caption: 'فرص بسوريا. تواصل مباشر، بدون حساب.',
      icon: CupertinoIcons.briefcase,
      start: Color(0xFF173D6B),
      end: Color(0xFF326AA8),
    ),
    (
      eyebrow: 'اختيارات أوضح',
      title: 'فرص على قياسك.',
      caption: 'فلتر حسب مدينتك، مجالك وطريقة الشغل.',
      icon: CupertinoIcons.slider_horizontal_3,
      start: Color(0xFF20508A),
      end: Color(0xFF566993),
    ),
    (
      eyebrow: 'أقصر طريق للتواصل',
      title: 'خطوة بسيطة، مباشرة.',
      caption: 'اقرأ التفاصيل وواتساب أو إيميل لصاحب الفرصة.',
      icon: CupertinoIcons.chat_bubble_2_fill,
      start: Color(0xFF254568),
      end: Color(0xFF306998),
    ),
  ];

  Widget hero() {
    final textScaler = MediaQuery.textScalerOf(context);
    final titleLines = textScaler.scale(26) > 32 ? 2 : 1;
    // Budget each bounded text row so larger Arabic type can wrap safely.
    final heroHeight =
        (32 +
                (textScaler.scale(12) * 1.7).clamp(32.0, double.infinity) +
                8 +
                textScaler.scale(26) * 1.35 * titleLines +
                5 +
                textScaler.scale(12) * 1.7 * 2)
            .clamp(150.0, double.infinity)
            .toDouble();
    return MotionSize(
      duration: motionDuration(context, 240),
      curve: Curves.easeOutCubic,
      child: searchFocus.hasFocus
          ? const SizedBox(width: double.infinity)
          : Column(
              children: [
                SizedBox(
                  height: heroHeight,
                  child: PageView.builder(
                    controller: heroPages,
                    // Center the first/last page too, including in RTL.
                    padEnds: true,
                    itemCount: heroContent.length,
                    onPageChanged: (value) => setState(() => heroIndex = value),
                    itemBuilder: (context, index) {
                      final item = heroContent[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Semantics(
                          button: true,
                          label: '${item.title} ابدأ البحث عن فرصتك',
                          child: Pressable(
                            onTap: searchFocus.requestFocus,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                gradient: LinearGradient(
                                  begin: Alignment.topRight,
                                  end: Alignment.bottomLeft,
                                  colors: [item.start, item.end],
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x2820508A),
                                    blurRadius: 24,
                                    offset: Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.eyebrow,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFFDCEEFF),
                                            fontSize: 12,
                                            height: 1.7,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFDCEEFF),
                                          borderRadius: BorderRadius.circular(
                                            11,
                                          ),
                                        ),
                                        child: AppIcon(
                                          item.icon,
                                          color: const Color(0xFF12233F),
                                          size: 17,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  Text(
                                    item.title,
                                    maxLines: titleLines,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 26,
                                      height: 1.35,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    item.caption,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFEAF4FF),
                                      height: 1.7,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < heroContent.length; i++)
                      AnimatedContainer(
                        duration: motionDuration(context, 220),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: heroIndex == i ? 20 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: heroIndex == i
                              ? context.sanad.primary
                              : context.sanad.primary.withValues(alpha: .24),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
    );
  }

  Widget discover(bool wide) {
    final jobs = feed;
    return SanadRefresh(
      key: feedRefreshKey,
      indicatorTop: searchHeaderExtent(),
      enabled: !store.loading && !store.busy,
      onRefresh: refreshFeed,
      successLabel: store.isDemo ? 'تحدّثت فرص العرض' : 'صارت الفرص محدّثة',
      child: CustomScrollView(
        key: const PageStorageKey('discover'),
        controller: scroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          pinnedSearchHeader(),
          SliverPadding(
            padding: const EdgeInsets.only(top: 20),
            sliver: SliverToBoxAdapter(child: hero()),
          ),
          SliverToBoxAdapter(child: quickFilters()),
          if (store.savedSearches.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: EdgeInsetsDirectional.fromSTEB(20, 0, 10, 0),
                        child: Text(
                          'بحوثك',
                          style: TextStyle(
                            color: context.sanad.secondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      for (final preset in store.savedSearches)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: InputChip(
                            label: Text(preset['name'] as String),
                            avatar: const AppIcon(
                              CupertinoIcons.bookmark,
                              size: 16,
                            ),
                            backgroundColor: context.sanad.surface,
                            deleteButtonTooltipMessage: 'حذف البحث المحفوظ',
                            onPressed: () {
                              store.applySearch(preset);
                              search.text = store.query;
                              animateScrollTo(context, scroll, 0);
                            },
                            onDeleted: () async {
                              await store.removeSearch(preset);
                              if (mounted && store.error != null) {
                                message(store.error!);
                              }
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.list(
              children: [
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            searching ? 'على قياسك' : 'فرص تستاهل تشوفها',
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${jobs.length} فرصة${searching ? ' مطابقة لبحثك' : ' متاحة'}',
                            style: TextStyle(
                              color: context.sanad.secondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (searching)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton.icon(
                            onPressed: searchIsSaved ? null : saveSearch,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                12,
                                8,
                                14,
                                8,
                              ),
                            ),
                            icon: AppIcon(
                              searchIsSaved
                                  ? CupertinoIcons.checkmark
                                  : CupertinoIcons.bookmark,
                              size: 17,
                            ),
                            label: Text(searchIsSaved ? 'محفوظ' : 'احفظ البحث'),
                          ),
                          const SizedBox(width: 14),
                          IconButton(
                            tooltip: 'مسح الفلاتر',
                            onPressed: clearFilters,
                            style: IconButton.styleFrom(
                              backgroundColor: context.sanad.tint,
                              minimumSize: const Size(44, 44),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: AppIcon(
                              CupertinoIcons.xmark,
                              size: 18,
                              color: context.sanad.primary,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                if (store.isDemo)
                  Padding(
                    padding: EdgeInsets.only(top: 9),
                    child: Text(
                      'نسخة عرض · فرص وجهات افتراضية',
                      style: TextStyle(
                        color: context.sanad.secondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                if (store.maintenance != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: SignalCard(store.maintenance!),
                  ),
                if (store.isOffline)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: SignalCard(
                      'بدون اتصال. عم تشوف آخر نتائج محفوظة على الجهاز.',
                    ),
                  ),
                if (store.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SignalCard(
                      store.error!,
                      action: refreshCurrentTab,
                      onClose: store.clearError,
                    ),
                  ),
                feedbackPanel(),
                const SizedBox(height: 14),
                if (store.loading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: SanadLoader(size: 32, label: 'عم نجهّز الفرص…'),
                  ),
                if (!store.loading && jobs.isEmpty)
                  empty(
                    store.visibleJobs.isNotEmpty
                        ? 'كل هالفرص عندك بالمحفوظة'
                        : 'خلّينا نوسّع الخيارات',
                    store.visibleJobs.isNotEmpty
                        ? 'حفظتها لوقتها المناسب. بتلاقيها كلها بمكان واحد.'
                        : 'ما لقينا نتيجة حالياً. غيّر كلمة البحث أو خفّف الفلاتر.',
                    action: store.visibleJobs.isNotEmpty
                        ? () => chooseTab(1)
                        : clearFilters,
                    label: store.visibleJobs.isNotEmpty
                        ? 'افتح المحفوظة'
                        : 'عرض كل الفرص',
                  ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.crossAxisExtent > 700 ? 2 : 1;
                if (columns == 1) {
                  final positions = <Key, int>{
                    for (var index = 0; index < jobs.length; index++)
                      ValueKey('feed-${jobs[index].id}'): index,
                  };
                  return SliverList.builder(
                    itemCount: jobs.length,
                    findChildIndexCallback: (key) => positions[key],
                    itemBuilder: (context, index) => Padding(
                      key: ValueKey('feed-${jobs[index].id}'),
                      padding: const EdgeInsets.only(bottom: 14),
                      child: SanadReveal(
                        order: index,
                        child: card(jobs[index]),
                      ),
                    ),
                  );
                }
                return SliverList.builder(
                  itemCount: (jobs.length / columns).ceil(),
                  itemBuilder: (context, row) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var col = 0; col < columns; col++) ...[
                          if (col > 0) const SizedBox(width: 14),
                          Expanded(
                            child: row * columns + col < jobs.length
                                ? SanadReveal(
                                    key: ValueKey(
                                      'arrival-${jobs[row * columns + col].id}',
                                    ),
                                    order: row,
                                    child: card(jobs[row * columns + col]),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 124),
              child: Text(
                'بدون حساب. تواصل مباشر مع صاحب الفرصة.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: context.sanad.secondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget searchBar() => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: context.sanad.isDark
            ? [context.sanad.surface, context.sanad.fieldFill]
            : const [Color(0xFFE7F0FA), Color(0xFFD8E9F8)],
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: context.sanad.isDark
            ? context.sanad.border
            : Colors.white.withValues(alpha: .88),
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1820508A),
          blurRadius: 18,
          offset: Offset(0, 7),
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
              textDirection: direction,
              textAlign: TextAlign.start,
              focusNode: searchFocus,
              onChanged: store.setQuery,
              style: TextStyle(
                color: context.sanad.ink,
                fontSize: 14,
                height: 1.7,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => searchFocus.unfocus(),
              decoration: InputDecoration(
                filled: false,
                hintText: 'دوّر على شغل، جهة أو مهارة',
                hintStyle: TextStyle(
                  color: context.sanad.secondary,
                  fontSize: 13,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
                prefixIcon: Padding(
                  padding: EdgeInsets.all(15),
                  child: AppIcon(
                    CupertinoIcons.search,
                    color: context.sanad.primary,
                    size: 20,
                  ),
                ),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'مسح البحث',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          side: BorderSide.none,
                        ),
                        onPressed: () {
                          search.clear();
                          store.setQuery('');
                        },
                        icon: AppIcon(
                          CupertinoIcons.xmark_circle_fill,
                          color: context.sanad.secondary,
                          size: 18,
                        ),
                      ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
              ),
            ),
          ),
        ),
        Container(
          width: 1,
          height: 30,
          color: context.sanad.primary.withValues(alpha: .15),
        ),
        Semantics(
          label: 'تصفية الفرص',
          button: true,
          excludeSemantics: true,
          onTap: filters,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Badge(
              isLabelVisible: store.filters.activeCount > 0,
              label: Text('${store.filters.activeCount}'),
              backgroundColor: context.sanad.primary,
              textColor: Theme.of(context).colorScheme.onPrimary,
              child: IconButton(
                tooltip: 'تصفية الفرص',
                onPressed: filters,
                style: IconButton.styleFrom(
                  foregroundColor: context.sanad.primary,
                  backgroundColor: Colors.transparent,
                  side: BorderSide.none,
                  minimumSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                icon: AppIcon(
                  CupertinoIcons.slider_horizontal_3,
                  color: context.sanad.primary,
                  size: 21,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget quickFilters() {
    final chips = [
      quickChip(
        store.filters.city ?? 'كل سوريا',
        store.filters.city != null,
        filters,
        icon: CupertinoIcons.location,
      ),
      quickChip(
        'عن بُعد',
        store.filters.workMode == 'عن بُعد',
        () => store.updateFilters(
          store.filters.copyWith(
            workMode: store.filters.workMode == 'عن بُعد' ? null : 'عن بُعد',
          ),
        ),
        icon: CupertinoIcons.globe,
      ),
      quickChip(
        'بدون خبرة',
        store.filters.experience == 'بدون خبرة',
        () => store.updateFilters(
          store.filters.copyWith(
            experience: store.filters.experience == 'بدون خبرة'
                ? null
                : 'بدون خبرة',
          ),
        ),
        icon: CupertinoIcons.sparkles,
      ),
      quickChip(
        'راتب معلن',
        store.filters.salaryOnly,
        () => store.updateFilters(
          store.filters.copyWith(salaryOnly: !store.filters.salaryOnly),
        ),
      ),
    ];
    return SizedBox(
      height: 52 + (MediaQuery.textScalerOf(context).scale(12) - 12) * 1.7,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) => chips[index],
      ),
    );
  }

  Widget quickChip(
    String label,
    bool selected,
    VoidCallback onTap, {
    IconData? icon,
  }) => Semantics(
    button: true,
    selected: selected,
    child: AnimatedContainer(
      duration: motionDuration(context, 250),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: selected
              ? [
                  context.sanad.isDark
                      ? context.sanad.accent
                      : const Color(0xFF37699F),
                  context.sanad.primary,
                ]
              : context.sanad.isDark
              ? [context.sanad.tint, context.sanad.fieldFill]
              : const [Color(0xFFEAF3FC), Color(0xFFDCEBFA)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: context.sanad.isDark
              ? context.sanad.border
              : Colors.white.withValues(alpha: .65),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            NativeBridge.selectionHaptic();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  AppIcon(
                    icon,
                    size: 16,
                    color: selected
                        ? Theme.of(context).colorScheme.onPrimary
                        : context.sanad.primary,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: selected
                        ? Theme.of(context).colorScheme.onPrimary
                        : context.sanad.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Widget feedbackPanel() => MotionSize(
    duration: motionDuration(context, 300),
    curve: Curves.easeInOutCubicEmphasized,
    alignment: Alignment.topCenter,
    child: feedback == null
        ? const SizedBox(width: double.infinity)
        : Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SignalCard(
              feedback!,
              action: lastSaved == null ? null : undoSave,
              actionLabel: 'تراجع عن الحفظ',
              onClose: () => setState(() {
                feedback = null;
                lastSaved = null;
              }),
            ),
          ),
  );
  Widget card(Job job) => MotionSize(
    key: ValueKey('card-${job.id}-$tab'),
    duration: motionDuration(context, 300),
    curve: Curves.easeInOutCubicEmphasized,
    alignment: Alignment.topCenter,
    child: departing.contains(job.id)
        ? const SizedBox(width: double.infinity)
        : LongPressDraggable<Job>(
            data: job,
            maxSimultaneousDrags:
                saving.contains(job.id) || store.savedIds.contains(job.id)
                ? 0
                : 1,
            onDragStarted: () {
              NativeBridge.selectionHaptic();
              setState(() => draggedId = job.id);
            },
            onDragEnd: (_) {
              if (mounted) setState(() => draggedId = null);
            },
            onDraggableCanceled: (_, _) {
              if (mounted) setState(() => draggedId = null);
            },
            dragAnchorStrategy: (_, _, _) => const Offset(120, 38),
            feedback: Material(
              color: Colors.transparent,
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Container(
                  width: 240,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: context.sanad.primary,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [
                      BoxShadow(color: Color(0x24315F86), blurRadius: 24),
                    ],
                  ),
                  child: Row(
                    children: [
                      AppIcon(
                        CupertinoIcons.heart_fill,
                        color: Theme.of(context).colorScheme.onPrimary,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          job.title,
                          textDirection: textDirectionFor(job.title),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            child: RepaintBoundary(
              key: cardKey(job),
              child: AnimatedOpacity(
                duration: motionDuration(context, 140),
                opacity: draggedId == job.id ? .25 : 1,
                child: cardSurface(job),
              ),
            ),
          ),
  );
  Widget cardSurface(Job job) => Glass(
    padding: EdgeInsets.zero,
    radius: 24,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
          child: Row(
            children: [
              CompanyMark(job.category, size: 42),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.company,
                      textDirection: textDirectionFor(job.company),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      age(job.createdAt),
                      style: TextStyle(
                        fontSize: 10,
                        color: context.sanad.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: store.savedIds.contains(job.id)
                    ? 'إزالة من المحفوظة'
                    : 'حفظ الفرصة',
                onPressed: saving.contains(job.id) ? null : () => favorite(job),
                icon: AnimatedSaveIcon(saved: store.savedIds.contains(job.id)),
              ),
            ],
          ),
        ),
        Semantics(
          button: true,
          label: '${job.title} لدى ${job.company}',
          child: Pressable(
            onTap: () {
              if (!saving.contains(job.id) && draggedId == null) details(job);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.title,
                    textDirection: textDirectionFor(job.title),
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.5,
                      fontWeight: FontWeight.w700,
                      color: context.sanad.ink,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      AppIcon(
                        CupertinoIcons.location,
                        size: 14,
                        color: context.sanad.secondary,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          '${job.locationLabel} · ${job.workMode}',
                          style: TextStyle(
                            color: context.sanad.secondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      AppTag(job.workType, color: context.sanad.primary),
                      AppTag(job.experience, color: context.sanad.primary),
                    ],
                  ),
                  const SizedBox(height: 15),
                  Wrap(
                    spacing: 5,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        job.salaryLabel,
                        textDirection: job.hasSalary
                            ? TextDirection.ltr
                            : TextDirection.rtl,
                        style: TextStyle(
                          color: context.sanad.ink,
                          fontSize: job.hasSalary ? 19 : 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (job.hasSalary)
                        Text(
                          '/ ${job.salaryPeriod}',
                          style: TextStyle(
                            color: context.sanad.secondary,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
          child: Row(
            children: [
              TextButton(
                onPressed: () => details(job),
                child: const Text(
                  'شوف التفاصيل',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'خيارات الفرصة',
                onPressed: () => setState(
                  () => expandedCard = expandedCard == job.id ? null : job.id,
                ),
                icon: AppIcon(
                  expandedCard == job.id
                      ? CupertinoIcons.xmark
                      : CupertinoIcons.ellipsis,
                  size: 20,
                  color: context.sanad.secondary,
                ),
              ),
            ],
          ),
        ),
        MotionSize(
          duration: motionDuration(context, 200),
          alignment: Alignment.topCenter,
          child: expandedCard != job.id
              ? const SizedBox(width: double.infinity)
              : Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                  color: context.sanad.tint,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'كل التفاصيل قبل ما تاخد قرارك.',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.sanad.secondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => details(job),
                        icon: const AppIcon(
                          CupertinoIcons.info_circle,
                          size: 17,
                        ),
                        label: const Text(
                          'التواصل والإبلاغ عن الفرصة',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    ),
  );
  String age(DateTime date) {
    final days = DateTime.now().difference(date).inDays;
    if (days <= 0) return 'أُضيفت اليوم';
    if (days == 1) return 'أُضيفت أمس';
    return 'منذ $days أيام';
  }

  Widget empty(
    String title,
    String subtitle, {
    VoidCallback? action,
    String label = 'اكتشف الفرص',
  }) => Glass(
    child: Column(
      children: [
        const SanadLogo(size: 68),
        const SizedBox(height: 8),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.sanad.secondary, fontSize: 13),
        ),
        if (action != null) ...[
          const SizedBox(height: 18),
          FilledButton(onPressed: action, child: Text(label)),
        ],
      ],
    ),
  );
  Widget saved() => SanadRefresh(
    key: savedRefreshKey,
    indicatorTop: 0,
    enabled: !store.loading && !store.busy,
    onRefresh: refreshFeed,
    successLabel: store.isDemo
        ? 'تحدّثت فرص العرض المحفوظة'
        : 'تحدّثت حالة فرصك المحفوظة',
    child: CustomScrollView(
      key: const PageStorageKey('saved'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 124),
          sliver: SliverList.list(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'فرص حطّيتها ببالك',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${store.savedJobs.length} فرصة · محفوظة على هالجهاز',
                      style: TextStyle(
                        color: context.sanad.secondary,
                        fontSize: 13,
                      ),
                    ),
                    feedbackPanel(),
                  ],
                ),
              ),
              if (savedCards.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: empty(
                    'لسّا ما حفظت أي فرصة',
                    'القلب بيحفظ الفرصة. والضغط المطوّل بيخلّيك تسحبها لهون.',
                    action: () => chooseTab(0),
                  ),
                )
              else
                ...savedCards.map(
                  (j) => Padding(
                    key: ValueKey('saved-${j.id}'),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: card(j),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> refreshCurrentTab() async {
    final refreshKey = switch (tab) {
      1 => savedRefreshKey,
      2 => publisherRefreshKey,
      _ => feedRefreshKey,
    };
    await refreshKey.currentState?.refresh();
  }

  Future<String?> refreshFeed() async {
    if (store.loading) return 'التحديث جارٍ. انتظر اكتماله.';
    await store.refresh();
    return store.error;
  }

  Future<String?> refreshSubmissions() async {
    if (refreshing || store.busy) {
      return 'انتظر انتهاء الطلب الحالي، وجرّب مجدداً.';
    }
    setState(() => refreshing = true);
    try {
      for (final s in store.submissions.toList()) {
        await store.refreshSubmission(s);
      }
      return null;
    } catch (_) {
      const error = 'تعذّر تحديث بعض الإعلانات. جرّب مرة تانية.';
      message(error);
      return error;
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  Future<void> withdraw(Submission s) async {
    if (!withdrawing.add(s.id)) return;
    setState(() {});
    try {
      await store.withdraw(s);
      if (mounted) setState(() => withdrawId = null);
    } catch (_) {
      message('تعذّر سحب الإعلان. بقي موجوداً، جرّب مرة تانية.');
    } finally {
      if (mounted) setState(() => withdrawing.remove(s.id));
    }
  }

  Widget publisher() => SanadRefresh(
    key: publisherRefreshKey,
    indicatorTop: 0,
    enabled: !refreshing && !store.busy,
    onRefresh: refreshSubmissions,
    loadingLabel: 'عم نتابع إعلاناتك…',
    successLabel: store.submissions.isEmpty
        ? 'ما عندك إعلانات لتحديثها بعد'
        : 'تحدّثت حالات إعلاناتك',
    child: CustomScrollView(
      key: const PageStorageKey('publisher'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 124),
          sliver: SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'شخص مناسب، لفرصتك.',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'تفاصيل واضحة، وتواصل مباشر مع المهتمين.',
                    style: TextStyle(
                      color: context.sanad.secondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Glass(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: context.sanad.tint,
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: AppIcon(
                            CupertinoIcons.briefcase,
                            color: context.sanad.primary,
                            size: 27,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'خلّي الفرصة تلاقي صاحبها',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final item in [
                          ('١', 'احكي عن الشغل'),
                          ('٢', 'اختار وسيلة التواصل'),
                          ('٣', 'تابع المراجعة من هون'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Text(
                                  item.$1,
                                  style: TextStyle(
                                    color: context.sanad.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    item.$2,
                                    style: TextStyle(
                                      color: context.sanad.secondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: post,
                            icon: AppIcon(
                              CupertinoIcons.plus,
                              color: Theme.of(context).colorScheme.onPrimary,
                              size: 18,
                            ),
                            label: const Text('أضف فرصة بدون حساب'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  feedbackPanel(),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'إعلاناتك',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: refreshing || store.busy
                            ? null
                            : refreshCurrentTab,
                        icon: refreshing
                            ? const SanadLoader(size: 20)
                            : const AppIcon(CupertinoIcons.refresh, size: 17),
                        label: Text(refreshing ? 'عم نحدّث…' : 'تحديث'),
                      ),
                    ],
                  ),
                  if (store.submissions.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        'أول إعلان بتضيفه رح يظهر هون، مع حالته.',
                        style: TextStyle(
                          color: context.sanad.secondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  for (final s in store.submissions)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Glass(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.job.title,
                              textDirection: textDirectionFor(s.job.title),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              s.job.company,
                              textDirection: textDirectionFor(s.job.company),
                              style: TextStyle(
                                color: context.sanad.secondary,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 12),
                            AppTag(
                              s.status == 'withdrawn'
                                  ? 'مسحوبة'
                                  : s.job.isExpired
                                  ? 'انتهت مدة الإعلان'
                                  : statusLabel(s.status, s.isDemo),
                              color: context.sanad.primary,
                            ),
                            if (s.status != 'withdrawn') ...[
                              const SizedBox(height: 8),
                              MotionSize(
                                duration: motionDuration(context, 200),
                                child: withdrawId != s.id
                                    ? Align(
                                        alignment:
                                            AlignmentDirectional.centerStart,
                                        child: TextButton(
                                          onPressed: () =>
                                              setState(() => withdrawId = s.id),
                                          child: Text(
                                            'سحب الإعلان',
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.error,
                                            ),
                                          ),
                                        ),
                                      )
                                    : Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'تأكيد سحب الإعلان؟',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            'رح يتوقف ظهوره وتُحذف بيانات تواصله. هالخطوة ما في تراجع عنها.',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: context.sanad.secondary,
                                            ),
                                          ),
                                          Wrap(
                                            spacing: 8,
                                            children: [
                                              TextButton(
                                                onPressed:
                                                    withdrawing.contains(s.id)
                                                    ? null
                                                    : () => setState(
                                                        () => withdrawId = null,
                                                      ),
                                                child: const Text('خليه موجود'),
                                              ),
                                              TextButton(
                                                onPressed:
                                                    withdrawing.contains(s.id)
                                                    ? null
                                                    : () => withdraw(s),
                                                child: Text(
                                                  withdrawing.contains(s.id)
                                                      ? 'عم نسحب…'
                                                      : 'تأكيد السحب',
                                                  style: TextStyle(
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.error,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
  String statusLabel(String status, bool demo) =>
      '${demo ? 'تجريبي · ' : ''}${switch (status) {
        'published' => 'منشورة',
        'rejected' => 'لم تُقبل',
        'expired' => 'منتهية',
        'withdrawn' => 'مسحوبة',
        _ => 'قيد المراجعة',
      }}';
}
