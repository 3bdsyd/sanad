import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_links.dart';
import 'core/design.dart';
import 'core/firebase_bootstrap.dart';
import 'core/motion.dart';
import 'core/theme_preference.dart';
import 'features/jobs/data/jobs_store.dart';
import 'features/jobs/presentation/home.dart';
import 'features/jobs/presentation/web/sanad_web_app.dart';
import 'features/jobs/presentation/welcome.dart';

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Rasterize the exact native mark before replacing the native launch screen.
  binding.deferFirstFrame();
  runApp(const SanadApp(ownsNativeFrame: true));
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
    showWelcome = !(preferences.getBool('fursa.welcome.seen') ?? false);
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
          await preferences.setBool('fursa.welcome.seen', true);
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
        title: 'سند | سندك للخطوة الجاية',
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 460),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) setState(() {});
      });
  JobsStore? _store;
  bool _prepared = false, _firstFrame = false, _failed = false;
  String? _failureDetail;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
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
        _enter();
      },
      onError: (Object error, StackTrace _) {
        if (mounted && generation == _generation) {
          setState(() {
            _failed = true;
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
      Future.wait([
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
      ]).whenComplete(() {
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
    if (_reveal.isAnimating && MediaQuery.disableAnimationsOf(context)) {
      _reveal.value = 1;
    }
  }

  void _enter() {
    if (!_firstFrame || _store == null || !mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _reveal.value = 1;
      setState(() {});
    } else {
      _reveal.forward();
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    _store?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _store != null;
    final completed = _reveal.isCompleted;
    final pages = <Page<void>>[
      if (ready)
        SanadFadePage(
          key: const ValueKey('home'),
          name: 'home',
          child: kIsWeb
              ? SanadWebApp(store: _store!)
              : JobsHome(store: _store!),
        ),
      if (ready && widget.welcome())
        SanadFadePage(
          key: const ValueKey('welcome'),
          name: 'welcome',
          child: PopScope(
            canPop: false,
            child: WelcomePage(onContinue: widget.onContinue),
          ),
        ),
    ];
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          (context.sanad.isDark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: android
                    ? context.sanad.background
                    : Colors.transparent,
                systemNavigationBarDividerColor: android
                    ? context.sanad.background
                    : Colors.transparent,
                systemNavigationBarIconBrightness: context.sanad.isDark
                    ? Brightness.light
                    : Brightness.dark,
                systemNavigationBarContrastEnforced: android,
              ),
      child: ColoredBox(
        color: context.sanad.background,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              excluding: !completed,
              child: IgnorePointer(
                ignoring: !completed,
                child: ExcludeFocus(
                  excluding: !completed,
                  child: FadeTransition(
                    opacity: _reveal,
                    child: ready
                        ? Navigator(pages: pages, onDidRemovePage: (page) {})
                        : const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            if (!completed)
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
                          SafeArea(
                            child: Center(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(24),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 360,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Semantics(
                                        label: 'سند',
                                        child: const SanadLogo(size: 96),
                                      ),
                                      const SizedBox(height: 24),
                                      SignalCard(
                                        _failureDetail == null ||
                                                _failureDetail!.isEmpty
                                            ? 'ما قدرنا نفتح سند. جرّب مرة تانية.'
                                            : 'ما قدرنا نفتح سند.\n$_failureDetail',
                                        actionLabel: 'إعادة المحاولة',
                                        action: widget.onRetry,
                                      ),
                                    ],
                                  ),
                                ),
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
    );
  }
}
