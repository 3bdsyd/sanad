import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_links.dart';
import 'core/design.dart';
import 'core/firebase_bootstrap.dart';
import 'core/job_link_host.dart';
import 'core/motion.dart';
import 'core/network_client.dart';
import 'core/robot_speech.dart';
import 'features/app_access/data/app_access_controller.dart';
import 'features/app_access/data/app_access_service.dart';
import 'features/app_access/domain/app_access.dart';
import 'features/app_access/presentation/app_access_page.dart';
import 'core/theme_preference.dart';
import 'core/web_browser_chrome.dart';
import 'core/web_nav_history.dart';
import 'features/jobs/data/jobs_store.dart';
import 'features/jobs/presentation/home.dart';
import 'features/jobs/presentation/country_setup.dart';
import 'features/jobs/presentation/web/sanad_web_app.dart';
import 'features/jobs/presentation/welcome.dart';
import 'features/platform/presentation/auth_page.dart';
import 'features/platform/presentation/web_download_gate.dart';

void main() {
  WebNavHistory.instance.initialize();
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Native launch screens must stay visible until Flutter has prepared the
  // brand mark. Web has no OS launch screen to preserve, so it can paint now.
  if (!kIsWeb) binding.deferFirstFrame();
  // Draw behind Android's system bars on every version, not only Android 15+,
  // so screens such as the robot pages can leave the buttons bar-free.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  runApp(SanadApp(ownsNativeFrame: !kIsWeb));
}

class SanadApp extends StatefulWidget {
  const SanadApp({super.key, this.ownsNativeFrame = false});
  final bool ownsNativeFrame;
  @override
  State<SanadApp> createState() => _SanadAppState();
}

class _SanadAppState extends State<SanadApp> {
  late Future<JobsStore> loading = load();
  final theme = SanadThemeController();
  bool showWelcome = true;
  bool themeReady = false;

  Future<JobsStore> load() async {
    AppLinks.validateRelease();
    await FirebaseBootstrap.initialize();
    final preferences = await SharedPreferences.getInstance();
    // Keep the existing key: rebranding must not reset people's preferences.
    showWelcome = !(preferences.getBool('snad.welcome.seen') ?? false);
    await theme.load();
    if (mounted) setState(() => themeReady = true);
    try {
      return await JobsStore.create();
    } catch (error) {
      throw Exception('تعذّر تجهيز بيانات الفرص: $error');
    }
  }

  void continueToJobs() {
    setState(() => showWelcome = false);
    SharedPreferences.getInstance()
        .then((preferences) async {
          await preferences.setBool('snad.welcome.seen', true);
        })
        .catchError((Object _) {
          // A failed preference write may show the welcome next launch.
        });
  }

  @override
  void dispose() {
    theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SanadThemeScope(
    controller: theme,
    child: ListenableBuilder(
      listenable: theme,
      builder: (context, _) => MaterialApp(
        title: 'سند | فرص العمل والتواصل المهني',
        debugShowCheckedModeBanner: false,
        theme: sanadTheme(),
        darkTheme: sanadTheme(brightness: Brightness.dark),
        themeMode: themeReady ? theme.mode : ThemeMode.system,
        scrollBehavior: const SanadScrollBehavior(),
        themeAnimationDuration:
            WidgetsBinding
                .instance
                .platformDispatcher
                .accessibilityFeatures
                .disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 260),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) {
          var content = child ?? const SizedBox.shrink();
          if (kIsWeb) {
            final colors = context.sanad;
            final header = Color.alphaBlend(
              sanadHeaderTone(colors, 0),
              colors.backdropColors[1],
            );
            WebBrowserChrome.apply(
              isDark: Theme.of(context).brightness == Brightness.dark,
              headerColor:
                  '#${header.toARGB32().toRadixString(16).substring(2)}',
            );
          }
          if (compactWebControls(context)) {
            content = Theme(
              data: sanadTheme(
                brightness: Theme.of(context).brightness,
                compactWeb: true,
              ),
              child: content,
            );
          }
          return kIsWeb
              ? WebBrowserChrome.wrap(WebDownloadGate(child: content))
              : content;
        },
        home: _SanadEntry(
          loading: loading,
          ownsNativeFrame: widget.ownsNativeFrame,
          welcome: () => showWelcome,
          onContinue: continueToJobs,
          onRetry: () => setState(() => loading = load()),
        ),
      ),
    ),
  );
}

class _SanadEntry extends StatefulWidget {
  const _SanadEntry({
    required this.loading,
    required this.ownsNativeFrame,
    required this.welcome,
    required this.onContinue,
    required this.onRetry,
  });
  final Future<JobsStore> loading;
  final bool ownsNativeFrame;
  final bool Function() welcome;
  final VoidCallback onContinue, onRetry;

  @override
  State<_SanadEntry> createState() => _SanadEntryState();
}

class _SanadEntryState extends State<_SanadEntry>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _reveal =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 460),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) setState(() {});
      });
  final _navKey = GlobalKey<NavigatorState>();
  final _accessClient = createNetworkClient();
  late final _access = AppAccessController(_checkAccess);

  Future<AppAccess> _checkAccess() async {
    const configured = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://admin.jobsnad.com',
    );
    final base = configured.trim().isEmpty
        ? 'https://admin.jobsnad.com'
        : configured.trim();
    if (base == 'demo') return const AppAccess();
    final platform = kIsWeb
        ? null
        : switch (defaultTargetPlatform) {
            TargetPlatform.android => 'android',
            TargetPlatform.iOS => 'ios',
            _ => null,
          };
    final version = platform == null
        ? null
        : (await PackageInfo.fromPlatform().timeout(
            const Duration(seconds: 8),
          )).version;
    return AppAccessService(
      base: base,
      client: _accessClient,
    ).check(platform: platform, version: version);
  }

  void _accessChanged() {
    if (!mounted) return;
    setState(() {});
    if (_access.allowed) _enter();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _store != null && !_failed) {
      unawaited(_access.refresh());
    }
  }

  JobsStore? _store;
  bool _prepared = false, _firstFrame = false, _failed = false;
  bool _retryable = true;
  String? _failureDetail;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _access.addListener(_accessChanged);
    _observe();
  }

  @override
  void didUpdateWidget(covariant _SanadEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loading != widget.loading) {
      _failed = false;
      _reveal.value = 0;
      _observe();
    }
  }

  void _observe() {
    final generation = ++_generation;
    widget.loading.then(
      (store) {
        if (!mounted || generation != _generation) {
          store.dispose();
          return;
        }
        _store?.dispose();
        setState(() {
          _store = store;
          _failed = false;
          _failureDetail = null;
        });
        unawaited(_access.refresh());
        _enter();
      },
      onError: (Object error, StackTrace _) {
        if (mounted && generation == _generation) {
          setState(() {
            _failed = true;
            _retryable = error is! ReleaseConfigError;
            _failureDetail = error.toString().replaceFirst('Exception: ', '');
          });
        }
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_prepared) {
      _prepared = true;
      final logoPreparation = Future.wait([
        precacheImage(
          const AssetImage(SanadLogo.asset),
          context,
          onError: (Object _, StackTrace? _) {},
        ),
        precacheImage(
          const AssetImage(SanadLogo.contrastAsset),
          context,
          onError: (Object _, StackTrace? _) {},
        ),
      ]);
      if (kIsWeb) {
        // Avoid holding the first browser frame on image decoding. The logo
        // asset can finish decoding while the local cache/app state loads.
        _firstFrame = true;
        unawaited(logoPreparation);
        _enter();
      } else {
        logoPreparation.whenComplete(() {
          // Never keep the OS launch screen stuck, including an asset failure.
          if (widget.ownsNativeFrame) {
            WidgetsBinding.instance.allowFirstFrame();
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _firstFrame = true);
            _enter();
          });
          WidgetsBinding.instance.scheduleFrame();
        });
      }
    }
    if (_reveal.isAnimating && MediaQuery.disableAnimationsOf(context)) {
      _reveal.value = 1;
    }
  }

  void _enter() {
    if (!_firstFrame ||
        _store == null ||
        !mounted ||
        !_access.allowed ||
        _reveal.isCompleted) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _reveal.value = 1;
      setState(() {});
    } else {
      _reveal.forward();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _access.dispose();
    _accessClient.close();
    _reveal.dispose();
    _store?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _store != null;
    final completed = _reveal.isCompleted && _access.allowed;
    final pages = <Page<void>>[
      if (ready)
        SanadFadePage(
          key: const ValueKey('home'),
          name: 'home',
          child: CountryGate(
            store: _store!,
            child: kIsWeb
                ? SanadWebApp(store: _store!)
                : JobsHome(store: _store!),
          ),
        ),
      if (ready && widget.welcome())
        SanadFadePage(
          key: const ValueKey('welcome'),
          name: 'welcome',
          child: PopScope(
            canPop: false,
            child: WelcomePage(
              onContinue: widget.onContinue,
              onLogin: _store!.accountsEnabled
                  ? () async {
                      final entered = await ensureAccount(
                        context,
                        _store!.platform,
                      );
                      if (entered) widget.onContinue();
                    }
                  : null,
            ),
          ),
        ),
    ];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: sanadSystemBars(context.sanad),
      child: ColoredBox(
        color: context.sanad.background,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: !_access.allowed,
              child: TickerMode(
                enabled: _access.allowed,
                child: ExcludeSemantics(
                  excluding: !completed,
                  child: IgnorePointer(
                    ignoring: !completed,
                    child: ExcludeFocus(
                      excluding: !completed,
                      child: FadeTransition(
                        opacity: _reveal,
                        child: ready
                            ? JobLinkHost(
                                store: _store!,
                                pushEnabled: completed && !widget.welcome(),
                                navigatorKey: _navKey,
                                welcomeVisible: widget.welcome,
                                onDismissWelcome: widget.onContinue,
                                child: Builder(
                                  builder: (context) {
                                    if (kIsWeb) {
                                      WebNavHistory.instance.bind(_navKey);
                                    }
                                    return NavigatorPopHandler<void>(
                                      enabled: _access.allowed,
                                      onPopWithResult: (_) {
                                        if (_access.allowed) {
                                          _navKey.currentState?.maybePop();
                                        }
                                      },
                                      child: Navigator(
                                        key: _navKey,
                                        pages: pages,
                                        onDidRemovePage: (page) {},
                                      ),
                                    );
                                  },
                                ),
                              )
                            : const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (!_reveal.isCompleted && (_failed || !ready || _access.allowed))
              AnimatedBuilder(
                animation: _reveal,
                builder: (context, _) => Opacity(
                  opacity: 1 - Curves.easeInOut.transform(_reveal.value),
                  child: Material(
                    color: context.sanad.background,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (!_failed)
                          Center(
                            child: Transform.translate(
                              offset: Offset(0, -20 * _reveal.value),
                              child: Transform.scale(
                                scale: 1 + .08 * _reveal.value,
                                child: const SanadLogoIntro(size: 112),
                              ),
                            ),
                          ),
                        if (_failed)
                          RobotMessagePage(
                            title: 'تعذّر تشغيل سند',
                            message: _retryable
                                ? 'تعذّر تشغيل التطبيق أو التحقق من حالة الخدمة. يرجى إعادة المحاولة.'
                                : 'إعدادات هذا الإصدار غير مكتملة. يرجى تثبيت إصدار مكتمل من فريق سند.',
                            actions: [
                              if (_retryable)
                                SanadPrimaryButton(
                                  onPressed: widget.onRetry,
                                  child: const Text('إعادة المحاولة'),
                                ),
                              if (_failureDetail != null)
                                ExpansionTile(
                                  title: const Text('تفاصيل المشكلة'),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Text(_failureDetail!),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            if (ready && !_access.allowed && !_failed)
              PopScope(
                canPop: false,
                child: AppAccessPage(controller: _access),
              ),
          ],
        ),
      ),
    );
  }
}
