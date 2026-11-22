import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import '../../../core/adaptive_text_field.dart';
import '../../../core/design.dart';
import '../../../core/motion.dart';
import '../../../core/home_back_guard.dart';
import '../../../core/sanad_refresh.dart';
import '../../ads/data/ads_controller.dart';
import '../../ads/data/native_ad_session.dart';
import '../../ads/domain/ad_config.dart';
import '../../ads/presentation/ad_slot.dart';
import '../../../core/native_bridge.dart';
import '../../../core/native_navigation.dart';
import '../../../core/theme_controls.dart';
import '../data/jobs_store.dart';
import '../domain/job.dart';
import '../domain/job_filters.dart';
import 'about_page.dart';
import '../../platform/presentation/auth_page.dart';
import '../../platform/presentation/account_page.dart';
import '../../platform/presentation/publisher_panel.dart';
import '../../platform/presentation/saved_panel.dart';
import '../../platform/presentation/platform_ui.dart';
import '../../platform/presentation/job_share_menu.dart';
import 'filter_sheet.dart';
import 'feed_scroll_header.dart';
import 'job_details.dart';
import 'notifications.dart';
import 'post_job.dart';
import 'saved_matches_notice.dart';
import 'country_flag.dart';
import '../domain/job_geography.dart';

class JobsHome extends StatefulWidget {
  const JobsHome({super.key, required this.store, this.nativeAds});
  final JobsStore store;
  final NativeAdSession? nativeAds;
  @override
  State<JobsHome> createState() => _JobsHomeState();
}

class _JobsHomeState extends State<JobsHome> with WidgetsBindingObserver {
  AdsController get adsController =>
      widget.nativeAds?.ads ?? AdsController.instance;
  NativeAdSession get nativeAds => widget.nativeAds ?? NativeAdSession.instance;
  int tab = 0;
  final search = TextEditingController();
  final searchFocus = FocusNode();
  final scroll = ScrollController();
  final heroPages = PageController(viewportFraction: .92);
  final navKey = GlobalKey();
  double feedHeaderExtent = 0;
  bool get adsActive =>
      AdConfig.supported &&
      !store.isDemo &&
      foreground &&
      !routeOpening &&
      tab == 0 &&
      !searchFocus.hasFocus &&
      (ModalRoute.isCurrentOf(context) ?? true);
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
  final heroIndex = ValueNotifier<int>(0);
  // Cards fade in once when results arrive, never again while scrolling.
  final Set<String> revealedCards = {};
  Timer? heroTimer;
  bool foreground = true;
  String? draggedId, expandedCard, withdrawId, feedback;
  Job? lastSaved;
  JobsStore get store => widget.store;
  int get notificationCount =>
      store.noticesUnread +
      store.savedSearchMatches
          .where((job) => store.isNewSavedMatch(job.id))
          .length;
  bool get searching => store.filters.activeCount > 0 || store.query.isNotEmpty;
  List<Job> get feed => store.visibleJobs
      .where((j) => !store.savedIds.contains(j.id) || saving.contains(j.id))
      .toList();

  void loadMoreNearEnd(int index, int length) {
    if (store.hasMore && index >= length - 5) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && tab == 0) unawaited(store.loadMore());
      });
    }
  }

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      startHeroRotation();
      if (mounted) unawaited(store.refreshSavedSearchMatches());
      if (mounted && !store.isDemo) unawaited(adsController.start());
    });
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
    if (mounted) {
      setState(() => foreground = state == AppLifecycleState.resumed);
    }
    if (state == AppLifecycleState.resumed) {
      startHeroRotation();
      unawaited(store.refreshSavedSearchMatches());
      if (!store.isDemo) unawaited(adsController.start());
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
      final next = (heroIndex.value + 1) % heroContent.length;
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
    heroIndex.dispose();
    searchFocus.removeListener(searchChanged);
    searchFocus.dispose();
    search.dispose();
    scroll.dispose();
    // The app entry owns JobsStore, including the optional welcome route.
    super.dispose();
  }

  /// Only the first screenful animates, and each card only on its first
  /// arrival; scrolling back to a card must not replay its entry.
  bool revealOnce(Job job, int order) =>
      order < 6 && revealedCards.add('${job.id}-$tab');

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
    setState(() => routeOpening = true);
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await action();
    } finally {
      if (mounted) setState(() => routeOpening = false);
    }
  }

  Future<void> filters() => navigate(() async {
    final result = await showFilters(context, store);
    if (result != null && mounted) {
      store.updateFilters(result);
      NativeBridge.selectionHaptic();
    }
  });
  Future<void> cityFilter() => navigate(() => showCityFilter(context, store));
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
  Future<void> viewNewMatches() async {
    final ids = store.newMatchAlertJobs.map((job) => job.id).toSet();
    if (ids.isEmpty) return;
    await store.acknowledgeMatchAlert(ids);
    if (!mounted) return;
    await navigate(
      () => openPage<void>(
        context,
        NotificationsPage(
          store: store,
          initialNewOnly: true,
          focusJobIds: ids,
          onJob: (job) =>
              openPage<void>(context, JobDetails(job: job, store: store)),
        ),
      ),
    );
  }

  Future<void> about() => navigate(
    () => openPage<void>(
      context,
      store.accountsEnabled
          ? AccountPage(store: store)
          : AboutPage(store: store),
    ),
  );
  Future<void> post() => navigate(() => showPostJob(context, store));

  Future<void> favorite(Job job, {bool fromDrop = false}) async {
    final adding = !store.savedIds.contains(job.id);
    if (store.accountsEnabled &&
            !await ensureAccount(
              context,
              store.platform,
              reason: 'لحفظ الفرصة',
            ) ||
        !mounted) {
      return;
    }
    if (fromDrop && store.savedIds.contains(job.id)) return;
    if (!saving.add(job.id)) return;
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
      await store.toggleSaved(job.id, desired: adding);
      await NativeBridge.selectionHaptic();
      if (!mounted) return;
      setState(() {
        lastSaved = adding ? job : null;
        feedback =
            store.error ??
            (adding
                ? 'أُضيفت الفرصة إلى المحفوظات.'
                : 'أُزيلت الفرصة من المحفوظات.');
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
    if (store.accountsEnabled &&
            !await ensureAccount(
              context,
              store.platform,
              reason: 'لحفظ البحث وإشعارات الفرص الجديدة',
            ) ||
        !mounted) {
      return;
    }
    try {
      await store.saveSearch();
    } catch (e) {
      message(e.toString());
    }

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
    listenable: Listenable.merge([store, adsController]),
    builder: (context, _) {
      final size = MediaQuery.sizeOf(context);
      final wide = kIsWeb
          ? size.width >= 980
          : size.width >= 1000 && size.height >= 700;
      return HomeBackGuard(
        isHome: tab == 0,
        onHome: () => chooseTab(0),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: sanadSystemBars(context.sanad),
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
                                    opaque: true,
                                    edge: false,
                                    blur: false,
                                    child: header(),
                                  ),
                                  Expanded(
                                    child: Builder(
                                      builder: (contentContext) => tabContent(
                                        wide,
                                        bottomInset: wide
                                            ? 0
                                            : MediaQuery.paddingOf(
                                                contentContext,
                                              ).bottom,
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
                      to: 0,
                      opaque: true,
                      edge: false,
                      blur: false,
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: wide
                ? null
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        key: navKey,
                        child: NativeNavigation(
                          selectedIndex: tab,
                          onSelected: chooseTab,
                        ),
                      ),
                    ],
                  ),
            floatingActionButtonLocation:
                FloatingActionButtonLocation.centerFloat,
            floatingActionButton: draggedId == null
                ? null
                : DragTarget<Job>(
                    onAcceptWithDetails: (d) =>
                        favorite(d.data, fromDrop: true),
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
                            'أفلتها هنا • المحفوظات',
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
        ),
      );
    },
  );

  Widget tabContent(
    bool wide, {
    required double bottomInset,
  }) => AnimatedSwitcher(
    duration: motionDuration(context, 320),
    switchInCurve: Curves.easeOutCubic,
    transitionBuilder: (child, animation) =>
        FadeTransition(opacity: animation, child: child),
    layoutBuilder: (current, previous) => current ?? const SizedBox.shrink(),
    child: KeyedSubtree(
      key: ValueKey(tab),
      child: switch (tab) {
        1 => store.accountsEnabled ? SavedPanel(store: store) : saved(),
        2 => store.accountsEnabled ? PublisherPanel(store: store) : publisher(),
        _ => discover(wide, bottomInset: bottomInset),
      },
    ),
  );

  Widget brand({bool hero = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SanadLogo(size: 38, bare: true, hero: hero),
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          'سند',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w700,
            color: context.sanad.ink,
          ),
        ),
      ),
    ],
  );

  Widget header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: 'عن سند',
            child: InkWell(
              onTap: about,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: brand(hero: true),
                ),
              ),
            ),
          ),
        ),
        const SanadThemePicker(compact: true),
        const SizedBox(width: sanadActionGap),
        if (tab != 2 || store.accountsEnabled) ...[
          if (store.accountsEnabled)
            IconButton.filledTonal(
              tooltip: 'حسابي',
              onPressed: about,
              style: IconButton.styleFrom(backgroundColor: context.sanad.tint),
              icon: AppIcon(
                CupertinoIcons.person_crop_circle,
                color: context.sanad.ink,
                size: 22,
              ),
            )
          else
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
          const SizedBox(width: sanadActionGap),
        ],
        IconButton.filledTonal(
          tooltip: 'الإشعارات',
          style: IconButton.styleFrom(backgroundColor: context.sanad.tint),
          onPressed: latest,
          icon: Badge(
            isLabelVisible: notificationCount > 0,
            label: Text('$notificationCount'),
            child: AppIcon(
              CupertinoIcons.bell,
              color: context.sanad.ink,
              size: 22,
            ),
          ),
        ),
      ],
    ),
  );

  double searchHeaderExtent() {
    final textScale = MediaQuery.textScalerOf(context).scale(14) - 14;
    return 84 + 1.7 * textScale;
  }

  Widget feedHeader() => FeedScrollHeader(
    searchFocused: searchFocus.hasFocus,
    onExtentChanged: (value) {
      if (mounted && feedHeaderExtent != value) {
        setState(() => feedHeaderExtent = value);
      }
    },
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: searchHeaderExtent(),
          child: sanadHeaderChrome(
            context: context,
            from: .42,
            to: 1,
            opaque: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
              child: searchBar(),
            ),
          ),
        ),
      ],
    ),
  );

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
          'منصة فرص العمل والتواصل المهني.',
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
          label: const Text('حسابي'),
        ),
      ],
    ),
  );
  static const heroContent = [
    (
      eyebrow: 'فرص العمل',
      title: 'فرص العمل المتاحة',
      caption: 'فرص عمل حسب البلد، وتواصل مباشر مع المعلنين دون حساب.',
      icon: CupertinoIcons.briefcase,
      start: Color(0xFF173D6B),
      end: Color(0xFF326AA8),
    ),
    (
      eyebrow: 'تصفية نتائج البحث',
      title: 'تصفية فرص العمل',
      caption: 'صفِّ الفرص حسب المحافظة والمجال وطريقة العمل.',
      icon: CupertinoIcons.slider_horizontal_3,
      start: Color(0xFF20508A),
      end: Color(0xFF566993),
    ),
    (
      eyebrow: 'التواصل مع الجهات المعلنة',
      title: 'التواصل مع المعلن',
      caption: 'اقرأ التفاصيل وتواصل مع صاحب الفرصة عبر واتساب أو البريد.',
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
                    onPageChanged: (value) => heroIndex.value = value,
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
                ValueListenableBuilder<int>(
                  valueListenable: heroIndex,
                  builder: (context, current, _) => Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < heroContent.length; i++)
                        AnimatedContainer(
                          duration: motionDuration(context, 220),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: current == i ? 20 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: current == i
                                ? context.sanad.primary
                                : context.sanad.primary.withValues(alpha: .24),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
    );
  }

  Widget discover(bool wide, {required double bottomInset}) {
    final jobs = feed;
    if (store.hasMore && jobs.length < 6) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && tab == 0) unawaited(store.loadMore());
      });
    }
    return SanadRefresh(
      key: feedRefreshKey,
      indicatorTop: feedHeaderExtent,
      enabled: !store.loading && !store.busy,
      onRefresh: refreshFeed,
      successLabel: store.isDemo ? 'تحدّثت فرص العرض' : 'تم تحديث الفرص',
      child: CustomScrollView(
        key: const PageStorageKey('discover'),
        controller: scroll,
        scrollCacheExtent: AdConfig.supported && !store.isDemo
            ? const ScrollCacheExtent.pixels(650)
            : null,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          feedHeader(),
          SliverToBoxAdapter(
            child: SavedMatchesNotice(store: store, onView: viewNewMatches),
          ),
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
                          padding: const EdgeInsetsDirectional.only(
                            end: sanadActionGap,
                          ),
                          child: InputChip(
                            label: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 44),
                              child: Center(
                                widthFactor: 1,
                                heightFactor: 1,
                                child: Text(preset['name'] as String),
                              ),
                            ),
                            labelPadding: const EdgeInsetsDirectional.fromSTEB(
                              8,
                              0,
                              sanadActionGap,
                              0,
                            ),
                            deleteIconBoxConstraints:
                                const BoxConstraints.tightFor(
                                  width: 44,
                                  height: 44,
                                ),
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
                              try {
                                await store.removeSearch(preset);
                              } catch (e) {
                                message(e.toString());
                              }
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
                SanadActionHeader(
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        searching ? 'نتائج البحث' : 'فرص العمل المتاحة',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${store.pagedCatalog ? store.totalCount : jobs.length} فرصة${searching ? ' مطابقة لبحثك' : ' متاحة'}',
                        style: TextStyle(
                          color: context.sanad.secondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    if (searching) ...[
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
                if (store.isOffline)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: SignalCard(
                      'لا يوجد اتصال. تعرض أحدث النتائج المحفوظة على الجهاز.',
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
                    child: SanadLoader(size: 32, label: 'جارٍ تحميل الفرص…'),
                  ),
                if (store.discoveryLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: SanadLoader(
                      size: 24,
                      label: 'جارٍ تحديث نتائج البحث…',
                    ),
                  ),
                if (!store.loading && !store.discoveryLoading && jobs.isEmpty)
                  empty(
                    store.visibleJobs.isNotEmpty
                        ? 'جميع هذه الفرص محفوظة لديك'
                        : 'وسّع نطاق البحث',
                    store.visibleJobs.isNotEmpty
                        ? 'حُفظت هذه الفرص لتراجعها لاحقاً من مكان واحد.'
                        : 'لم نعثر على نتائج حالياً. غيّر كلمة البحث أو خفّف عوامل التصفية.',
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
                final layout = AdFeedLayout(
                  jobs: jobs.length,
                  columns: columns,
                  enabled: AdConfig.supported && !store.isDemo,
                );
                final positions = <Key, int>{
                  for (var row = 0; row < layout.rows; row++)
                    ValueKey('feed-${jobs[row * columns].id}'): layout
                        .itemForRow(row),
                  for (var slot = 0; slot < layout.ads; slot++)
                    ValueKey('feed-ad-$slot'):
                        layout.first + slot * (layout.interval + 1),
                };
                return SliverList.builder(
                  itemCount: layout.itemCount,
                  findChildIndexCallback: (key) => positions[key],
                  itemBuilder: (context, index) {
                    if (layout.isAd(index)) {
                      final slot = layout.slotAt(index);
                      return SanadAdSlot(
                        key: ValueKey('feed-ad-$slot'),
                        native: true,
                        nativeSession: nativeAds,
                        active: adsActive,
                        placement: 'feed_native_$slot',
                      );
                    }
                    final row = layout.rowAt(index);
                    final leadRow = row + 2;
                    if (layout.enabled &&
                        leadRow >= layout.first &&
                        (leadRow - layout.first) % layout.interval == 0) {
                      final slot = (leadRow - layout.first) ~/ layout.interval;
                      if (slot < layout.ads) {
                        final width = constraints.crossAxisExtent.floor().clamp(
                          0,
                          420,
                        );
                        final spec = NativeAdSpec(
                          width: width,
                          colors: context.sanad,
                        );
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && adsActive) {
                            nativeAds.prefetch('feed_native_$slot', spec);
                          }
                        });
                      }
                    }
                    final first = row * columns;
                    loadMoreNearEnd(first, jobs.length);
                    Widget jobCard(int position) => SanadReveal(
                      key: ValueKey('arrival-${jobs[position].id}'),
                      order: position,
                      animate: revealOnce(jobs[position], position),
                      child: card(jobs[position]),
                    );
                    return Padding(
                      key: ValueKey('feed-${jobs[first].id}'),
                      padding: const EdgeInsets.only(bottom: 14),
                      child: columns == 1
                          ? jobCard(first)
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (var col = 0; col < columns; col++) ...[
                                  if (col > 0) const SizedBox(width: 14),
                                  Expanded(
                                    child: first + col < jobs.length
                                        ? jobCard(first + col)
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ],
                            ),
                    );
                  },
                );
              },
            ),
          ),
          if (jobs.isNotEmpty &&
              (store.loadingMore || store.loadMoreError != null))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
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
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 24),
              child: Text(
                'دون حساب. تواصل مباشرة مع صاحب الفرصة.',
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
              onTapOutside: (event) {
                if (event.kind != PointerDeviceKind.touch) {
                  searchFocus.unfocus();
                }
              },
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
                hintText: 'ابحث عن وظيفة أو جهة أو مهارة',
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
                    : Padding(
                        padding: const EdgeInsetsDirectional.only(
                          end: sanadActionGap,
                        ),
                        child: IconButton(
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
        store.filters.locationLabel,
        store.filters.country != null || store.filters.city != null,
        cityFilter,
        icon: CupertinoIcons.location,
        leading: countryFor(store.filters.country) == null
            ? null
            : CountryFlag(
                country: countryFor(store.filters.country)!,
                size: 18,
              ),
        showChevron: true,
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
        icon: CupertinoIcons.money_dollar_circle,
      ),
    ];
    return SizedBox(
      height: 52 + (MediaQuery.textScalerOf(context).scale(12) - 12) * 1.7,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: sanadActionGap),
        itemBuilder: (_, index) => chips[index],
      ),
    );
  }

  Widget quickChip(
    String label,
    bool selected,
    VoidCallback onTap, {
    IconData? icon,
    Widget? leading,
    bool showChevron = false,
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
                if (leading != null) ...[
                  leading,
                  const SizedBox(width: 6),
                ] else if (icon != null) ...[
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
        : GestureDetector(
            onLongPressStart: (details) =>
                showJobShareMenu(context, job, details.globalPosition),
            child: RepaintBoundary(key: cardKey(job), child: cardSurface(job)),
          ),
  );
  Widget cardSurface(Job job) => Pressable(
    onTap: () {
      if (!saving.contains(job.id) && draggedId == null) details(job);
    },
    child: Glass(
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
                  onPressed: saving.contains(job.id)
                      ? null
                      : () => favorite(job),
                  icon: AnimatedSaveIcon(
                    saved: store.savedIds.contains(job.id),
                  ),
                ),
              ],
            ),
          ),
          Padding(
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
                    if (job.viewsCount > 0) ...[
                      const SizedBox(width: 8),
                      AppIcon(
                        CupertinoIcons.eye,
                        size: 13,
                        color: context.sanad.secondary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${job.viewsCount}',
                        style: TextStyle(
                          color: context.sanad.secondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 13),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    AppTag(job.workType, color: context.sanad.primary),
                    AppTag(job.experienceLabel, color: context.sanad.primary),
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
                    if (job.salaryPeriodLabel != null)
                      Text(
                        job.salaryPeriodLabel!,
                        style: TextStyle(
                          color: context.sanad.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => details(job),
                    child: const Text(
                      'عرض التفاصيل',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: sanadActionGap),
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
                          'اطّلع على التفاصيل قبل اتخاذ قرارك.',
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
          SanadPrimaryButton(onPressed: action, child: Text(label)),
        ],
      ],
    ),
  );
  Widget saved() => store.accountsEnabled && !store.platform.signedIn
      ? ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
          children: [
            EmptyPanel(
              icon: CupertinoIcons.heart,
              title: 'احتفظ بالفرص التي تهمّك',
              description:
                  'سجّل الدخول لتبقى فرصك المحفوظة مرتبطة بحسابك ومتاحة على أجهزتك.',
              action: SanadPrimaryButton(
                onPressed: () =>
                    ensureAccount(context, store.platform, reason: 'لحفظ فرصك'),
                child: const Text('تسجيل الدخول أو إنشاء حساب'),
              ),
            ),
          ],
        )
      : SanadRefresh(
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
                            'الفرص المحفوظة',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${store.savedJobs.length} فرصة · محفوظة على هذا الجهاز',
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
                          'لم تحفظ أي فرصة بعد.',
                          'احفظ الفرصة بالضغط على القلب، أو اضغط مطولاً واسحبها إلى هنا.',
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
    await store.refreshSavedSearchMatches(force: true);
    return store.error;
  }

  Future<String?> refreshSubmissions() async {
    if (refreshing || store.busy) {
      return 'انتظر اكتمال الطلب الحالي، ثم حاول مجدداً.';
    }
    setState(() => refreshing = true);
    try {
      await store.refreshMySubmissions();
      return null;
    } catch (exception) {
      final error = exception is JobsException
          ? exception.message
          : 'تعذّر تحديث إعلاناتك. حاول مرة أخرى.';
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
      message('تعذّر سحب الإعلان وما زال ظاهراً. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => withdrawing.remove(s.id));
    }
  }

  Widget publisher() => SanadRefresh(
    key: publisherRefreshKey,
    indicatorTop: 0,
    enabled: !refreshing && !store.busy,
    onRefresh: refreshSubmissions,
    loadingLabel: 'جارٍ تحميل إعلاناتك…',
    successLabel: store.submissions.isEmpty
        ? 'لا توجد إعلانات لتحديثها.'
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
                  SanadActionHeader(
                    minimumRowWidth: 280,
                    title: const Text(
                      'إعلاناتك',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    actions: [
                      SanadPrimaryButton.icon(
                        onPressed: post,
                        icon: AppIcon(
                          CupertinoIcons.plus,
                          size: 19,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                        label: const Text('أضف فرصة عمل'),
                      ),
                    ],
                  ),
                  feedbackPanel(),
                  const SizedBox(height: 12),
                  if (store.submissions.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        'سيظهر إعلانك الأول هنا مع حالته.',
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
                                            'سيتوقف ظهور الإعلان وستُحذف بيانات التواصل. لا يمكن التراجع عن هذه الخطوة.',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: context.sanad.secondary,
                                            ),
                                          ),
                                          SanadActions(
                                            children: [
                                              TextButton(
                                                onPressed:
                                                    withdrawing.contains(s.id)
                                                    ? null
                                                    : () => setState(
                                                        () => withdrawId = null,
                                                      ),
                                                child: const Text('إلغاء'),
                                              ),
                                              TextButton(
                                                onPressed:
                                                    withdrawing.contains(s.id)
                                                    ? null
                                                    : () => withdraw(s),
                                                child: Text(
                                                  withdrawing.contains(s.id)
                                                      ? 'جارٍ السحب…'
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
